#include "include/flutter_classic_bluetooth/flutter_classic_bluetooth_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <atomic>
#include <vector>

#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>
#include <bluetooth/rfcomm.h>

#include "bluetooth_helper.h"
#include "bluetooth_dbus.h"
#include "bluetooth_agent.h"
#include "bluetooth_connection.h"
#include "bluetooth_server.h"

#define FLUTTER_CLASSIC_BLUETOOTH_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_classic_bluetooth_plugin_get_type(), \
                              FlutterClassicBluetoothPlugin))

// Per-connection event channels (data + state).
struct ConnectionChannels {
    FlEventChannel* data_channel;
    FlEventChannel* state_channel;
};

struct _FlutterClassicBluetoothPlugin {
    GObject parent_instance;
    FlBinaryMessenger* messenger;  // borrowed; valid for the plugin's lifetime
    // Global event channels.
    FlEventChannel* adapter_state_channel;
    FlEventChannel* discovery_state_channel;
    FlEventChannel* discovery_results_channel;
    FlEventChannel* bond_state_channel;
    // Dynamic per-connection / per-server channels.
    std::map<int, ConnectionChannels>* connection_channels;
    std::map<int, FlEventChannel*>* server_channels;
    std::map<int, std::unique_ptr<BluetoothConnection>>* connections;
    std::map<int, std::unique_ptr<BluetoothServer>>* servers;
    std::mutex* connections_mutex;
    std::mutex* servers_mutex;
    int next_connection_id;
    int next_server_id;
    std::atomic<bool>* discovering;
    // Discovery scan generation, so a stale auto-stop timer can't cancel a
    // newer scan. Touched only on the platform (main-loop) thread.
    int discovery_session;
    // Persistent system-bus connection to BlueZ (org.bluez) and the live signal
    // subscriptions it carries. Owned; null when no system bus is available.
    GDBusConnection* system_bus;
    guint sub_iface_added;
    guint sub_device_props;
    guint sub_adapter_props;
    // Auto-accepting pairing agent (org.bluez.Agent1) registration.
    guint agent_reg_id;
    GDBusNodeInfo* agent_node;
};

G_DEFINE_TYPE(FlutterClassicBluetoothPlugin, flutter_classic_bluetooth_plugin, g_object_get_type())

static int get_hci_device_id() {
    return hci_get_route(nullptr);
}

// ── Main-thread event delivery ─────────────────────────────────────────────
//
// Bluetooth I/O happens on background threads, but FlEventChannel sends must
// run on the platform (main-loop) thread. post_event() takes ownership of
// `value` and schedules the send on the GLib main context.

struct SendPayload {
    FlEventChannel* channel;
    FlValue* value;  // owned
};

static gboolean send_on_main_thread_cb(gpointer data) {
    SendPayload* p = static_cast<SendPayload*>(data);
    fl_event_channel_send(p->channel, p->value, nullptr, nullptr);
    fl_value_unref(p->value);
    delete p;
    return G_SOURCE_REMOVE;
}

static void post_event(FlEventChannel* channel, FlValue* value /* transfer full */) {
    if (!channel || !value) {
        if (value) fl_value_unref(value);
        return;
    }
    SendPayload* p = new SendPayload{channel, value};
    g_idle_add(send_on_main_thread_cb, p);
}

// ── Generic stream handlers ────────────────────────────────────────────────

static FlMethodErrorResponse* event_listen_noop(FlEventChannel*, FlValue*, gpointer) {
    return nullptr;
}
static FlMethodErrorResponse* event_cancel_noop(FlEventChannel*, FlValue*, gpointer) {
    return nullptr;
}

static const char* current_adapter_state_string(FlutterClassicBluetoothPlugin* self) {
    // BlueZ D-Bus is the source of truth and works for an unprivileged user.
    bool powered = false;
    if (self->system_bus && dbus_try_powered(self->system_bus, &powered)) {
        return powered ? "on" : "off";
    }
    // Fallback: raw HCI (needs CAP_NET_RAW / root).
    int dev_id = get_hci_device_id();
    if (dev_id < 0) return "unsupported";
    int sock = hci_open_dev(dev_id);
    if (sock < 0) return "unsupported";
    const char* state = "off";
    struct hci_dev_info di;
    memset(&di, 0, sizeof(di));
    di.dev_id = dev_id;
    if (ioctl(sock, HCIGETDEVINFO, &di) >= 0) {
        state = hci_test_bit(HCI_UP, &di.flags) ? "on" : "off";
    }
    close(sock);
    return state;
}

// Adapter state: emit the current state on subscribe. Live changes are pushed
// by on_adapter_properties_changed (BlueZ Adapter1 Powered signal).
static FlMethodErrorResponse* adapter_state_listen(FlEventChannel* channel,
                                                   FlValue*, gpointer user_data) {
    FlutterClassicBluetoothPlugin* self =
        FLUTTER_CLASSIC_BLUETOOTH_PLUGIN(user_data);
    post_event(channel, fl_value_new_string(current_adapter_state_string(self)));
    return nullptr;
}

// Bond state: emit the device's real Paired snapshot (via BlueZ D-Bus) for the
// address the listener subscribed with, falling back to "none".
static FlMethodErrorResponse* bond_state_listen(FlEventChannel* channel,
                                                FlValue* args, gpointer user_data) {
    FlutterClassicBluetoothPlugin* self =
        FLUTTER_CLASSIC_BLUETOOTH_PLUGIN(user_data);
    const char* state = "none";
    if (self->system_bus && args &&
        fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
        FlValue* addr = fl_value_lookup_string(args, "address");
        if (addr && fl_value_get_type(addr) == FL_VALUE_TYPE_STRING) {
            bool paired = false;
            if (dbus_try_device_paired(self->system_bus,
                                       fl_value_get_string(addr), &paired)) {
                state = paired ? "bonded" : "none";
            }
        }
    }
    post_event(channel, fl_value_new_string(state));
    return nullptr;
}

// ── BlueZ live signal handlers (run on the GLib main loop) ─────────────────

// org.freedesktop.DBus.ObjectManager.InterfacesAdded: a new device appeared.
static void on_interfaces_added(GDBusConnection*, const gchar*, const gchar*,
                                const gchar*, const gchar*, GVariant* params,
                                gpointer user_data) {
    FlutterClassicBluetoothPlugin* self =
        FLUTTER_CLASSIC_BLUETOOTH_PLUGIN(user_data);
    if (!self->discovering->load()) return;

    const gchar* obj_path = nullptr;
    GVariant* ifaces = nullptr;
    g_variant_get(params, "(&o@a{sa{sv}})", &obj_path, &ifaces);
    GVariant* dev_props =
        g_variant_lookup_value(ifaces, "org.bluez.Device1",
                               G_VARIANT_TYPE("a{sv}"));
    if (dev_props) {
        FlValue* map = dbus_device_map_from_props(
            dev_props, dbus_address_from_path(obj_path));
        if (map) post_event(self->discovery_results_channel, map);
        g_variant_unref(dev_props);
    }
    g_variant_unref(ifaces);
}

// org.bluez.Device1 PropertiesChanged: a known device updated (e.g. RSSI) as
// it is rediscovered. Forward it as a discovery result while scanning.
static void on_device_properties_changed(GDBusConnection*, const gchar*,
                                         const gchar* object_path, const gchar*,
                                         const gchar*, GVariant* params,
                                         gpointer user_data) {
    FlutterClassicBluetoothPlugin* self =
        FLUTTER_CLASSIC_BLUETOOTH_PLUGIN(user_data);
    if (!self->discovering->load()) return;

    GVariant* changed = g_variant_get_child_value(params, 1);  // a{sv}
    // Only forward changes that carry discovery-relevant data (a freshly seen
    // signal strength or name), not unrelated churn like Connected/Paired.
    auto has_key = [changed](const char* key) {
        GVariant* v = g_variant_lookup_value(changed, key, nullptr);
        if (v) { g_variant_unref(v); return true; }
        return false;
    };
    bool relevant = has_key("RSSI") || has_key("Name") || has_key("Alias");
    if (relevant) {
        FlValue* map = dbus_device_map_from_props(
            changed, dbus_address_from_path(object_path));
        if (map) post_event(self->discovery_results_channel, map);
    }
    g_variant_unref(changed);
}

// org.bluez.Adapter1 PropertiesChanged: push live adapter power changes.
static void on_adapter_properties_changed(GDBusConnection*, const gchar*,
                                          const gchar*, const gchar*,
                                          const gchar*, GVariant* params,
                                          gpointer user_data) {
    FlutterClassicBluetoothPlugin* self =
        FLUTTER_CLASSIC_BLUETOOTH_PLUGIN(user_data);
    GVariant* changed = g_variant_get_child_value(params, 1);  // a{sv}
    GVariant* powered =
        g_variant_lookup_value(changed, "Powered", G_VARIANT_TYPE_BOOLEAN);
    if (powered) {
        post_event(self->adapter_state_channel,
                   fl_value_new_string(g_variant_get_boolean(powered) ? "on"
                                                                      : "off"));
        g_variant_unref(powered);
    }
    g_variant_unref(changed);
}

// ── Per-connection channel wiring ──────────────────────────────────────────

static void setup_connection_channels(FlutterClassicBluetoothPlugin* self,
                                      int conn_id, BluetoothConnection* conn) {
    // Caller holds connections_mutex.
    std::string data_name =
        "flutter_classic_bluetooth/connection/" + std::to_string(conn_id);
    std::string state_name =
        "flutter_classic_bluetooth/connection_state/" + std::to_string(conn_id);

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    FlEventChannel* data_ch = fl_event_channel_new(
        self->messenger, data_name.c_str(), FL_METHOD_CODEC(codec));
    FlEventChannel* state_ch = fl_event_channel_new(
        self->messenger, state_name.c_str(), FL_METHOD_CODEC(codec));
    fl_event_channel_set_stream_handlers(data_ch, event_listen_noop,
                                         event_cancel_noop, nullptr, nullptr);
    fl_event_channel_set_stream_handlers(state_ch, event_listen_noop,
                                         event_cancel_noop, nullptr, nullptr);
    (*self->connection_channels)[conn_id] = {data_ch, state_ch};

    conn->StartReading(
        [data_ch](const std::vector<uint8_t>& data) {
            post_event(data_ch,
                       fl_value_new_uint8_list(data.data(), data.size()));
        },
        [state_ch]() {
            post_event(state_ch, fl_value_new_string("disconnected"));
        });

    // Initial state for any listener that subscribes promptly.
    post_event(state_ch, fl_value_new_string("connected"));
}

// ── Method handlers ────────────────────────────────────────────────────────

static FlMethodResponse* handle_is_supported(FlutterClassicBluetoothPlugin* self) {
    bool supported =
        (self->system_bus && dbus_adapter_present(self->system_bus)) ||
        get_hci_device_id() >= 0;
    g_autoptr(FlValue) result = fl_value_new_bool(supported);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_is_enabled(FlutterClassicBluetoothPlugin* self) {
    bool enabled = false;
    if (!(self->system_bus && dbus_try_powered(self->system_bus, &enabled))) {
        // Fallback: raw HCI.
        int dev_id = get_hci_device_id();
        if (dev_id >= 0) {
            int sock = hci_open_dev(dev_id);
            if (sock >= 0) {
                struct hci_dev_info di;
                memset(&di, 0, sizeof(di));
                di.dev_id = dev_id;
                if (ioctl(sock, HCIGETDEVINFO, &di) >= 0) {
                    enabled = hci_test_bit(HCI_UP, &di.flags);
                }
                close(sock);
            }
        }
    }
    g_autoptr(FlValue) result = fl_value_new_bool(enabled);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_get_adapter_name(FlutterClassicBluetoothPlugin* self) {
    std::string name;
    if (self->system_bus &&
        (dbus_try_adapter_string(self->system_bus, "Alias", &name) ||
         dbus_try_adapter_string(self->system_bus, "Name", &name)) &&
        !name.empty()) {
        g_autoptr(FlValue) result = fl_value_new_string(name.c_str());
        return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
    // Fallback: raw HCI.
    int dev_id = get_hci_device_id();
    int sock = dev_id >= 0 ? hci_open_dev(dev_id) : -1;
    if (sock >= 0) {
        char buf[249];
        memset(buf, 0, sizeof(buf));
        if (hci_read_local_name(sock, sizeof(buf), buf, 0) >= 0) {
            close(sock);
            g_autoptr(FlValue) result = fl_value_new_string(buf);
            return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
        }
        close(sock);
    }
    g_autoptr(FlValue) result = fl_value_new_null();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_get_adapter_address(FlutterClassicBluetoothPlugin* self) {
    std::string addr;
    if (self->system_bus &&
        dbus_try_adapter_string(self->system_bus, "Address", &addr) &&
        !addr.empty()) {
        for (auto& c : addr) if (c >= 'a' && c <= 'f') c = c - 'a' + 'A';
        g_autoptr(FlValue) result = fl_value_new_string(addr.c_str());
        return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
    // Fallback: raw HCI.
    int dev_id = get_hci_device_id();
    int sock = dev_id >= 0 ? hci_open_dev(dev_id) : -1;
    if (sock >= 0) {
        struct hci_dev_info di;
        memset(&di, 0, sizeof(di));
        di.dev_id = dev_id;
        if (ioctl(sock, HCIGETDEVINFO, &di) >= 0) {
            close(sock);
            char buf[18];
            ba2str(&di.bdaddr, buf);
            for (int i = 0; buf[i]; i++) {
                if (buf[i] >= 'a' && buf[i] <= 'f') buf[i] -= 32;
            }
            g_autoptr(FlValue) result = fl_value_new_string(buf);
            return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
        }
        close(sock);
    }
    g_autoptr(FlValue) result = fl_value_new_null();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// Ends a BlueZ discovery scan once the bounded window elapses, unless a newer
// scan has since started (guarded by discovery_session). Runs on the main loop.
struct DiscoveryAutoStop {
    FlutterClassicBluetoothPlugin* self;
    int session;
};

static gboolean discovery_autostop_cb(gpointer data) {
    DiscoveryAutoStop* d = static_cast<DiscoveryAutoStop*>(data);
    FlutterClassicBluetoothPlugin* self = d->self;
    if (self->discovering->load() && self->discovery_session == d->session) {
        if (self->system_bus) dbus_stop_discovery(self->system_bus);
        self->discovering->store(false);
        post_event(self->discovery_state_channel, fl_value_new_bool(false));
    }
    delete d;
    return G_SOURCE_REMOVE;
}

static FlMethodResponse* handle_start_discovery(FlutterClassicBluetoothPlugin* self) {
    if (self->discovering->load()) {
        g_autoptr(FlValue) result = fl_value_new_null();
        return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }

    // Primary path: BlueZ D-Bus discovery (works unprivileged). Results stream
    // in via on_interfaces_added / on_device_properties_changed.
    if (self->system_bus && dbus_start_discovery(self->system_bus)) {
        self->discovering->store(true);
        self->discovery_session++;
        post_event(self->discovery_state_channel, fl_value_new_bool(true));

        // Surface devices BlueZ already knows about immediately.
        dbus_for_each_device(
            self->system_bus, [self](const char* path, GVariant* props) {
                FlValue* map = dbus_device_map_from_props(
                    props, dbus_address_from_path(path));
                if (map) post_event(self->discovery_results_channel, map);
            });

        // Bounded scan window (~12s) to mirror the other platforms.
        DiscoveryAutoStop* d = new DiscoveryAutoStop{self, self->discovery_session};
        g_timeout_add_seconds(12, discovery_autostop_cb, d);

        g_autoptr(FlValue) result = fl_value_new_null();
        return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }

    // Fallback: raw HCI inquiry (needs CAP_NET_RAW / root).
    self->discovering->store(true);
    post_event(self->discovery_state_channel, fl_value_new_bool(true));

    std::thread([self]() {
        int dev_id = get_hci_device_id();
        if (dev_id < 0) {
            self->discovering->store(false);
            post_event(self->discovery_state_channel, fl_value_new_bool(false));
            return;
        }
        int sock = hci_open_dev(dev_id);
        if (sock < 0) {
            self->discovering->store(false);
            post_event(self->discovery_state_channel, fl_value_new_bool(false));
            return;
        }

        int max_rsp = 255;
        int flags = IREQ_CACHE_FLUSH;
        inquiry_info* ii = (inquiry_info*)malloc(max_rsp * sizeof(inquiry_info));
        int num_rsp = hci_inquiry(dev_id, 8, max_rsp, nullptr, &ii, flags);

        for (int i = 0; i < num_rsp && self->discovering->load(); i++) {
            char addr[18];
            ba2str(&ii[i].bdaddr, addr);
            for (int j = 0; addr[j]; j++) {
                if (addr[j] >= 'a' && addr[j] <= 'f') addr[j] -= 32;
            }
            char name[249] = {};
            hci_read_remote_name(sock, &ii[i].bdaddr, sizeof(name), name, 0);
            post_event(self->discovery_results_channel,
                       device_to_map(addr, name[0] ? name : nullptr, false));
        }

        if (ii) free(ii);
        close(sock);
        self->discovering->store(false);
        post_event(self->discovery_state_channel, fl_value_new_bool(false));
    }).detach();

    g_autoptr(FlValue) result = fl_value_new_null();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_stop_discovery(FlutterClassicBluetoothPlugin* self) {
    if (self->discovering->load()) {
        if (self->system_bus) dbus_stop_discovery(self->system_bus);
        self->discovering->store(false);
        // The D-Bus path has no worker thread, so emit the stop here. (The HCI
        // fallback thread also emits a stop when its inquiry returns.)
        post_event(self->discovery_state_channel, fl_value_new_bool(false));
    }
    g_autoptr(FlValue) result = fl_value_new_null();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_get_paired_devices(FlutterClassicBluetoothPlugin* self) {
    // Enumerate bonded devices via the BlueZ D-Bus ObjectManager.
    g_autoptr(FlValue) devices = fl_value_new_list();
    dbus_append_paired_devices(self->system_bus, devices);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(devices));
}

static FlMethodResponse* handle_connect(FlutterClassicBluetoothPlugin* self, FlValue* args) {
    FlValue* addr_val = fl_value_lookup_string(args, "address");
    if (!addr_val) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "connectionFailed", "Address is required", nullptr));
    }
    const char* address = fl_value_get_string(addr_val);

    const char* uuid = "00001101-0000-1000-8000-00805F9B34FB";
    FlValue* uuid_val = fl_value_lookup_string(args, "uuid");
    if (uuid_val && fl_value_get_type(uuid_val) == FL_VALUE_TYPE_STRING) {
        uuid = fl_value_get_string(uuid_val);
    }
    bool secure = true;
    FlValue* secure_val = fl_value_lookup_string(args, "secure");
    if (secure_val && fl_value_get_type(secure_val) == FL_VALUE_TYPE_BOOL) {
        secure = fl_value_get_bool(secure_val);
    }

    int sock = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);
    if (sock < 0) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "connectionFailed", "Failed to create socket", nullptr));
    }

    // Honor the secure flag via the RFCOMM link mode.
    if (secure) {
        int lm = RFCOMM_LM_AUTH | RFCOMM_LM_ENCRYPT;
        setsockopt(sock, SOL_RFCOMM, RFCOMM_LM, &lm, sizeof(lm));
    }

    struct sockaddr_rc addr = {};
    addr.rc_family = AF_BLUETOOTH;
    str2ba(address, &addr.rc_bdaddr);

    // Resolve the RFCOMM channel from the service UUID via SDP. Fall back to an
    // explicit "channel" argument, then to channel 1 (SPP default).
    int channel = sdp_find_rfcomm_channel(&addr.rc_bdaddr, uuid);
    FlValue* channel_val = fl_value_lookup_string(args, "channel");
    if (channel_val && fl_value_get_type(channel_val) == FL_VALUE_TYPE_INT) {
        channel = (int)fl_value_get_int(channel_val);
    }
    if (channel <= 0) channel = 1;
    addr.rc_channel = (uint8_t)channel;

    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(sock);
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "connectionFailed", "Failed to connect", nullptr));
    }

    int conn_id;
    {
        std::lock_guard<std::mutex> lock(*self->connections_mutex);
        conn_id = self->next_connection_id++;
        auto connection = std::make_unique<BluetoothConnection>(conn_id, sock, std::string(address));
        setup_connection_channels(self, conn_id, connection.get());
        (*self->connections)[conn_id] = std::move(connection);
    }

    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "id", fl_value_new_int(conn_id));
    fl_value_set_string_take(result, "address", fl_value_new_string(address));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_disconnect(FlutterClassicBluetoothPlugin* self, FlValue* args) {
    FlValue* id_val = fl_value_lookup_string(args, "id");
    if (!id_val) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "connectionFailed", "Connection ID is required", nullptr));
    }
    int id = fl_value_get_int(id_val);

    std::lock_guard<std::mutex> lock(*self->connections_mutex);
    auto it = self->connections->find(id);
    if (it != self->connections->end()) {
        it->second->Close();
        self->connections->erase(it);
    }
    // The per-connection channels are kept until plugin dispose to avoid racing
    // with any send still queued on the main loop.

    g_autoptr(FlValue) result = fl_value_new_null();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_write(FlutterClassicBluetoothPlugin* self, FlValue* args) {
    FlValue* id_val = fl_value_lookup_string(args, "id");
    FlValue* data_val = fl_value_lookup_string(args, "data");

    if (!id_val || !data_val) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "writeFailed", "Connection ID and data are required", nullptr));
    }

    int id = fl_value_get_int(id_val);
    size_t len = fl_value_get_length(data_val);
    const uint8_t* bytes = fl_value_get_uint8_list(data_val);

    std::lock_guard<std::mutex> lock(*self->connections_mutex);
    auto it = self->connections->find(id);
    if (it == self->connections->end()) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "connectionFailed", "Connection not found", nullptr));
    }

    std::vector<uint8_t> data(bytes, bytes + len);
    if (it->second->Write(data)) {
        g_autoptr(FlValue) result = fl_value_new_null();
        return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "writeFailed", "Failed to write data", nullptr));
    }
}

static FlMethodResponse* handle_bond_device(FlutterClassicBluetoothPlugin* self, FlValue* args) {
    FlValue* addr_val = fl_value_lookup_string(args, "address");
    if (!addr_val || fl_value_get_type(addr_val) != FL_VALUE_TYPE_STRING) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "invalidAddress", "Address is required", nullptr));
    }
    // Pair via BlueZ D-Bus (org.bluez.Device1.Pair).
    bool ok = dbus_pair_device(self->system_bus, fl_value_get_string(addr_val));
    g_autoptr(FlValue) result = fl_value_new_bool(ok);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_unbond_device(FlutterClassicBluetoothPlugin* self, FlValue* args) {
    FlValue* addr_val = fl_value_lookup_string(args, "address");
    if (!addr_val || fl_value_get_type(addr_val) != FL_VALUE_TYPE_STRING) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "invalidAddress", "Address is required", nullptr));
    }
    // Unpair via BlueZ D-Bus (org.bluez.Adapter1.RemoveDevice).
    bool ok = dbus_remove_device(self->system_bus, fl_value_get_string(addr_val));
    g_autoptr(FlValue) result = fl_value_new_bool(ok);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_start_server(FlutterClassicBluetoothPlugin* self, FlValue* args) {
    const char* uuid = "00001101-0000-1000-8000-00805F9B34FB";
    const char* service_name = "FlutterBluetooth";
    bool secure = true;

    FlValue* uuid_val = fl_value_lookup_string(args, "uuid");
    if (uuid_val && fl_value_get_type(uuid_val) == FL_VALUE_TYPE_STRING) {
        uuid = fl_value_get_string(uuid_val);
    }
    FlValue* name_val = fl_value_lookup_string(args, "serviceName");
    if (name_val && fl_value_get_type(name_val) == FL_VALUE_TYPE_STRING) {
        service_name = fl_value_get_string(name_val);
    }
    FlValue* secure_val = fl_value_lookup_string(args, "secure");
    if (secure_val && fl_value_get_type(secure_val) == FL_VALUE_TYPE_BOOL) {
        secure = fl_value_get_bool(secure_val);
    }

    int server_id;
    {
        std::lock_guard<std::mutex> lock(*self->servers_mutex);
        server_id = self->next_server_id++;

        // Register the server/{id} event channel that delivers accepted clients.
        std::string ch_name =
            "flutter_classic_bluetooth/server/" + std::to_string(server_id);
        g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
        FlEventChannel* server_ch = fl_event_channel_new(
            self->messenger, ch_name.c_str(), FL_METHOD_CODEC(codec));
        fl_event_channel_set_stream_handlers(server_ch, event_listen_noop,
                                             event_cancel_noop, nullptr, nullptr);
        (*self->server_channels)[server_id] = server_ch;

        auto server = std::make_unique<BluetoothServer>(server_id, uuid, service_name, secure);

        bool started = server->Start(1, [self, server_ch](int client_socket,
                                                          const std::string& address) {
            // Accept loop runs on a background thread. Register the client's
            // connection channels and notify Dart on the main thread.
            int conn_id;
            {
                std::lock_guard<std::mutex> lock(*self->connections_mutex);
                conn_id = self->next_connection_id++;
                auto connection = std::make_unique<BluetoothConnection>(
                    conn_id, client_socket, address);
                setup_connection_channels(self, conn_id, connection.get());
                (*self->connections)[conn_id] = std::move(connection);
            }
            FlValue* accepted = fl_value_new_map();
            fl_value_set_string_take(accepted, "id", fl_value_new_int(conn_id));
            fl_value_set_string_take(accepted, "address", fl_value_new_string(address.c_str()));
            post_event(server_ch, accepted);
        });

        if (!started) {
            return FL_METHOD_RESPONSE(fl_method_error_response_new(
                "connectionFailed", "Failed to start server", nullptr));
        }
        (*self->servers)[server_id] = std::move(server);
    }

    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "id", fl_value_new_int(server_id));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_stop_server(FlutterClassicBluetoothPlugin* self, FlValue* args) {
    FlValue* id_val = fl_value_lookup_string(args, "id");
    if (!id_val) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "connectionFailed", "Server ID is required", nullptr));
    }
    int id = fl_value_get_int(id_val);

    std::lock_guard<std::mutex> lock(*self->servers_mutex);
    auto it = self->servers->find(id);
    if (it != self->servers->end()) {
        it->second->Stop();
        self->servers->erase(it);
    }

    g_autoptr(FlValue) result = fl_value_new_null();
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static gboolean reset_discoverable_cb(gpointer) {
    int dev_id = get_hci_device_id();
    if (dev_id >= 0) {
        int sock = hci_open_dev(dev_id);
        if (sock >= 0) {
            struct hci_dev_req dr;
            dr.dev_id = dev_id;
            dr.dev_opt = SCAN_PAGE;  // connectable but no longer discoverable
            ioctl(sock, HCISETSCAN, &dr);
            close(sock);
        }
    }
    return G_SOURCE_REMOVE;
}

static FlMethodResponse* handle_set_discoverable(FlutterClassicBluetoothPlugin* self, FlValue* args) {
    int duration = 120;
    FlValue* dur_val = fl_value_lookup_string(args, "duration");
    if (dur_val && fl_value_get_type(dur_val) == FL_VALUE_TYPE_INT) {
        duration = (int)fl_value_get_int(dur_val);
    }

    // Primary path: BlueZ D-Bus. BlueZ auto-reverts after DiscoverableTimeout,
    // so no manual reset timer is needed.
    bool ok = self->system_bus &&
              dbus_set_discoverable(self->system_bus, true, duration);

    if (!ok) {
        // Fallback: raw HCI scan mode (needs CAP_NET_RAW / root).
        int dev_id = get_hci_device_id();
        if (dev_id >= 0) {
            int sock = hci_open_dev(dev_id);
            if (sock >= 0) {
                struct hci_dev_req dr;
                dr.dev_id = dev_id;
                dr.dev_opt = SCAN_PAGE | SCAN_INQUIRY;
                ok = ioctl(sock, HCISETSCAN, &dr) >= 0;
                close(sock);
            }
        }
        // Revert to connectable-only after the requested duration.
        if (ok && duration > 0) {
            g_timeout_add_seconds(duration, reset_discoverable_cb, nullptr);
        }
    }

    g_autoptr(FlValue) result = fl_value_new_bool(ok);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_get_platform_capabilities(FlutterClassicBluetoothPlugin* self) {
    g_autoptr(FlValue) caps = fl_value_new_map();
    fl_value_set_string_take(caps, "canEnableBluetooth", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "canDisableBluetooth", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "canDiscoverDevices", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "canGetPairedDevices", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "canBondDevices", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "canUnbondDevices", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "canCreateServer", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "canSetDiscoverable", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "supportsMultipleConnections", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "supportsSecureConnection", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "supportsInsecureConnection", fl_value_new_bool(true));
    fl_value_set_string_take(caps, "requiresMfiCertification", fl_value_new_bool(false));
    fl_value_set_string_take(caps, "platformNote",
        fl_value_new_string("Linux: Bluetooth Classic via BlueZ. Adapter state/power, discovery, discoverability, paired-device listing and pairing/unpairing use the BlueZ D-Bus API (org.bluez), so they work for an unprivileged desktop user; connect, server and data streaming use AF_BLUETOOTH RFCOMM sockets. Raw HCI is used only as a fallback when no system bus is available. The plugin registers an auto-accepting pairing agent, so Secure Simple Pairing (\"just works\") devices pair from bondDevice() without a desktop dialog; devices that require the user to type a PIN/passkey still need a system agent."));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(caps));
}

static void flutter_classic_bluetooth_plugin_handle_method_call(
    FlutterClassicBluetoothPlugin* self,
    FlMethodCall* method_call) {
    g_autoptr(FlMethodResponse) response = nullptr;
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);

    // BlueZ access is granted by the system's D-Bus policy, not by a runtime
    // prompt this plugin can raise, so there is no permission to request.
    if (strcmp(method, "checkPermissions") == 0 ||
        strcmp(method, "requestPermissions") == 0) {
        g_autoptr(FlValue) result = fl_value_new_string("notRequired");
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else if (strcmp(method, "openAppSettings") == 0) {
        g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else if (strcmp(method, "isSupported") == 0) {
        response = handle_is_supported(self);
    } else if (strcmp(method, "isEnabled") == 0) {
        response = handle_is_enabled(self);
    } else if (strcmp(method, "enableBluetooth") == 0 || strcmp(method, "disableBluetooth") == 0) {
        // Toggle the adapter Powered property via BlueZ D-Bus.
        bool enable = strcmp(method, "enableBluetooth") == 0;
        bool ok = dbus_set_adapter_powered(self->system_bus, enable);
        g_autoptr(FlValue) result = fl_value_new_bool(ok);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else if (strcmp(method, "getAdapterName") == 0) {
        response = handle_get_adapter_name(self);
    } else if (strcmp(method, "getAdapterAddress") == 0) {
        response = handle_get_adapter_address(self);
    } else if (strcmp(method, "startDiscovery") == 0) {
        response = handle_start_discovery(self);
    } else if (strcmp(method, "stopDiscovery") == 0) {
        response = handle_stop_discovery(self);
    } else if (strcmp(method, "isDiscovering") == 0) {
        g_autoptr(FlValue) result = fl_value_new_bool(self->discovering->load());
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else if (strcmp(method, "getPairedDevices") == 0) {
        response = handle_get_paired_devices(self);
    } else if (strcmp(method, "bondDevice") == 0) {
        response = handle_bond_device(self, args);
    } else if (strcmp(method, "unbondDevice") == 0) {
        response = handle_unbond_device(self, args);
    } else if (strcmp(method, "connect") == 0) {
        response = handle_connect(self, args);
    } else if (strcmp(method, "disconnect") == 0) {
        response = handle_disconnect(self, args);
    } else if (strcmp(method, "write") == 0) {
        response = handle_write(self, args);
    } else if (strcmp(method, "startServer") == 0) {
        response = handle_start_server(self, args);
    } else if (strcmp(method, "stopServer") == 0) {
        response = handle_stop_server(self, args);
    } else if (strcmp(method, "setDiscoverable") == 0) {
        response = handle_set_discoverable(self, args);
    } else if (strcmp(method, "getPlatformCapabilities") == 0) {
        response = handle_get_platform_capabilities(self);
    } else {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }

    fl_method_call_respond(method_call, response, nullptr);
}

static void flutter_classic_bluetooth_plugin_dispose(GObject* object) {
    FlutterClassicBluetoothPlugin* self = FLUTTER_CLASSIC_BLUETOOTH_PLUGIN(object);

    if (self->discovering) self->discovering->store(false);

    if (self->connections) {
        for (auto& [id, conn] : *self->connections) {
            conn->Close();
        }
        delete self->connections;
        self->connections = nullptr;
    }
    if (self->servers) {
        for (auto& [id, server] : *self->servers) {
            server->Stop();
        }
        delete self->servers;
        self->servers = nullptr;
    }
    if (self->connection_channels) {
        for (auto& [id, ch] : *self->connection_channels) {
            if (ch.data_channel) g_object_unref(ch.data_channel);
            if (ch.state_channel) g_object_unref(ch.state_channel);
        }
        delete self->connection_channels;
        self->connection_channels = nullptr;
    }
    if (self->server_channels) {
        for (auto& [id, ch] : *self->server_channels) {
            if (ch) g_object_unref(ch);
        }
        delete self->server_channels;
        self->server_channels = nullptr;
    }
    g_clear_object(&self->adapter_state_channel);
    g_clear_object(&self->discovery_state_channel);
    g_clear_object(&self->discovery_results_channel);
    g_clear_object(&self->bond_state_channel);

    if (self->system_bus) {
        dbus_unregister_pairing_agent(self->system_bus, self->agent_reg_id,
                                      self->agent_node);
        self->agent_reg_id = 0;
        self->agent_node = nullptr;
        if (self->sub_iface_added)
            g_dbus_connection_signal_unsubscribe(self->system_bus,
                                                 self->sub_iface_added);
        if (self->sub_device_props)
            g_dbus_connection_signal_unsubscribe(self->system_bus,
                                                 self->sub_device_props);
        if (self->sub_adapter_props)
            g_dbus_connection_signal_unsubscribe(self->system_bus,
                                                 self->sub_adapter_props);
        g_object_unref(self->system_bus);
        self->system_bus = nullptr;
    }

    delete self->connections_mutex;
    delete self->servers_mutex;
    delete self->discovering;

    G_OBJECT_CLASS(flutter_classic_bluetooth_plugin_parent_class)->dispose(object);
}

static void flutter_classic_bluetooth_plugin_class_init(FlutterClassicBluetoothPluginClass* klass) {
    G_OBJECT_CLASS(klass)->dispose = flutter_classic_bluetooth_plugin_dispose;
}

static void flutter_classic_bluetooth_plugin_init(FlutterClassicBluetoothPlugin* self) {
    self->connections = new std::map<int, std::unique_ptr<BluetoothConnection>>();
    self->servers = new std::map<int, std::unique_ptr<BluetoothServer>>();
    self->connection_channels = new std::map<int, ConnectionChannels>();
    self->server_channels = new std::map<int, FlEventChannel*>();
    self->connections_mutex = new std::mutex();
    self->servers_mutex = new std::mutex();
    self->next_connection_id = 0;
    self->next_server_id = 0;
    self->discovering = new std::atomic<bool>(false);
    self->discovery_session = 0;
    self->system_bus = nullptr;
    self->sub_iface_added = 0;
    self->sub_device_props = 0;
    self->sub_adapter_props = 0;
    self->agent_reg_id = 0;
    self->agent_node = nullptr;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
    FlutterClassicBluetoothPlugin* plugin = FLUTTER_CLASSIC_BLUETOOTH_PLUGIN(user_data);
    flutter_classic_bluetooth_plugin_handle_method_call(plugin, method_call);
}

void flutter_classic_bluetooth_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
    FlutterClassicBluetoothPlugin* plugin = FLUTTER_CLASSIC_BLUETOOTH_PLUGIN(
        g_object_new(flutter_classic_bluetooth_plugin_get_type(), nullptr));

    FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
    plugin->messenger = messenger;

    // Acquire the system bus and subscribe to BlueZ signals so adapter-power and
    // discovery events stream live. Best-effort: if there is no system bus the
    // plugin transparently falls back to the raw-HCI code paths.
    plugin->system_bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, nullptr);
    if (plugin->system_bus) {
        plugin->sub_iface_added = g_dbus_connection_signal_subscribe(
            plugin->system_bus, "org.bluez",
            "org.freedesktop.DBus.ObjectManager", "InterfacesAdded",
            nullptr, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
            on_interfaces_added, plugin, nullptr);
        plugin->sub_device_props = g_dbus_connection_signal_subscribe(
            plugin->system_bus, "org.bluez",
            "org.freedesktop.DBus.Properties", "PropertiesChanged",
            nullptr, "org.bluez.Device1", G_DBUS_SIGNAL_FLAGS_NONE,
            on_device_properties_changed, plugin, nullptr);
        plugin->sub_adapter_props = g_dbus_connection_signal_subscribe(
            plugin->system_bus, "org.bluez",
            "org.freedesktop.DBus.Properties", "PropertiesChanged",
            nullptr, "org.bluez.Adapter1", G_DBUS_SIGNAL_FLAGS_NONE,
            on_adapter_properties_changed, plugin, nullptr);

        // Become the default pairing agent so SSP "just works" devices can pair
        // from bondDevice() without a desktop dialog.
        plugin->agent_reg_id =
            dbus_register_pairing_agent(plugin->system_bus, &plugin->agent_node);
    }

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    // The method channel is kept alive by the messenger; the handler holds a ref
    // to the plugin. We do NOT store it on the plugin, to avoid a reference cycle.
    g_autoptr(FlMethodChannel) channel =
        fl_method_channel_new(messenger,
                              "flutter_classic_bluetooth/methods",
                              FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                              g_object_ref(plugin),
                                              g_object_unref);

    // Global event channels.
    plugin->adapter_state_channel = fl_event_channel_new(
        messenger, "flutter_classic_bluetooth/adapter_state", FL_METHOD_CODEC(codec));
    fl_event_channel_set_stream_handlers(plugin->adapter_state_channel,
                                         adapter_state_listen, event_cancel_noop,
                                         plugin, nullptr);

    plugin->discovery_state_channel = fl_event_channel_new(
        messenger, "flutter_classic_bluetooth/discovery_state", FL_METHOD_CODEC(codec));
    fl_event_channel_set_stream_handlers(plugin->discovery_state_channel,
                                         event_listen_noop, event_cancel_noop,
                                         nullptr, nullptr);

    plugin->discovery_results_channel = fl_event_channel_new(
        messenger, "flutter_classic_bluetooth/discovery_results", FL_METHOD_CODEC(codec));
    fl_event_channel_set_stream_handlers(plugin->discovery_results_channel,
                                         event_listen_noop, event_cancel_noop,
                                         nullptr, nullptr);

    plugin->bond_state_channel = fl_event_channel_new(
        messenger, "flutter_classic_bluetooth/bond_state", FL_METHOD_CODEC(codec));
    fl_event_channel_set_stream_handlers(plugin->bond_state_channel,
                                         bond_state_listen, event_cancel_noop,
                                         plugin, nullptr);

    g_object_unref(plugin);
}
