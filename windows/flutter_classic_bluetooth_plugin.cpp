#include "flutter_classic_bluetooth_plugin.h"

#include <winsock2.h>
#include <windows.h>
#include <ws2bth.h>
#include <BluetoothAPIs.h>

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <chrono>
#include <cstdio>
#include <memory>
#include <sstream>
#include <thread>
#include <vector>

#include "bluetooth_helper.h"
#include "bluetooth_connection.h"
#include "bluetooth_server.h"

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "Bthprops.lib")

namespace flutter_classic_bluetooth {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {
// Safely extract an int id from an EncodableValue, tolerating the codec
// delivering it as either int32_t or int64_t. Avoids throwing std::get.
bool ExtractInt(const EncodableValue& value, int* out) {
  if (const auto* p = std::get_if<int32_t>(&value)) {
    *out = *p;
    return true;
  }
  if (const auto* p = std::get_if<int64_t>(&value)) {
    *out = static_cast<int>(*p);
    return true;
  }
  return false;
}

// Emits the current adapter power state once when a listener subscribes.
// Windows offers no simple change-notification here, so this is a snapshot.
class AdapterStateStreamHandler
    : public flutter::StreamHandler<EncodableValue> {
 protected:
  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnListenInternal(
      const EncodableValue*,
      std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) override {
    HANDLE radio = nullptr;
    BLUETOOTH_FIND_RADIO_PARAMS params = {sizeof(BLUETOOTH_FIND_RADIO_PARAMS)};
    HBLUETOOTH_RADIO_FIND find = BluetoothFindFirstRadio(&params, &radio);
    std::string state = "unsupported";
    if (find) {
      state = (BluetoothIsConnectable(radio) != FALSE) ? "on" : "off";
      BluetoothFindRadioClose(find);
      CloseHandle(radio);
    }
    events->Success(EncodableValue(state));
    sink_ = std::move(events);
    return nullptr;
  }
  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnCancelInternal(
      const EncodableValue*) override {
    sink_.reset();
    return nullptr;
  }

 private:
  std::unique_ptr<flutter::EventSink<EncodableValue>> sink_;
};

// Emits the current bond state of the {address} argument once on subscribe.
class BondStateStreamHandler : public flutter::StreamHandler<EncodableValue> {
 protected:
  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnListenInternal(
      const EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) override {
    std::string address;
    if (const auto* m = std::get_if<EncodableMap>(arguments)) {
      auto it = m->find(EncodableValue("address"));
      if (it != m->end()) {
        if (const auto* s = std::get_if<std::string>(&it->second)) address = *s;
      }
    }
    std::string state = "none";
    if (!address.empty()) {
      BLUETOOTH_DEVICE_INFO info = {};
      info.dwSize = sizeof(BLUETOOTH_DEVICE_INFO);
      info.Address.ullLong = StringToAddress(address);
      if (BluetoothGetDeviceInfo(nullptr, &info) == ERROR_SUCCESS) {
        state = info.fAuthenticated ? "bonded" : "none";
      }
    }
    events->Success(EncodableValue(state));
    sink_ = std::move(events);
    return nullptr;
  }
  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> OnCancelInternal(
      const EncodableValue*) override {
    sink_.reset();
    return nullptr;
  }

 private:
  std::unique_ptr<flutter::EventSink<EncodableValue>> sink_;
};
}  // namespace

// static
void FlutterClassicBluetoothPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), "flutter_classic_bluetooth/methods",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterClassicBluetoothPlugin>(registrar->messenger());

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  // Register event channels
  plugin->adapter_state_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "flutter_classic_bluetooth/adapter_state",
      &flutter::StandardMethodCodec::GetInstance());
  plugin->discovery_state_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "flutter_classic_bluetooth/discovery_state",
      &flutter::StandardMethodCodec::GetInstance());
  plugin->discovery_results_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "flutter_classic_bluetooth/discovery_results",
      &flutter::StandardMethodCodec::GetInstance());
  plugin->bond_state_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "flutter_classic_bluetooth/bond_state",
      &flutter::StandardMethodCodec::GetInstance());

  // Adapter state: emit the current state when a listener subscribes.
  plugin->adapter_state_channel_->SetStreamHandler(
      std::make_unique<AdapterStateStreamHandler>());
  // Bond state: emit the current bond state of the requested address on listen.
  plugin->bond_state_channel_->SetStreamHandler(
      std::make_unique<BondStateStreamHandler>());

  auto disc_state_handler = std::make_unique<PluginStreamHandler>();
  plugin->discovery_state_handler_ = disc_state_handler.get();
  plugin->discovery_state_channel_->SetStreamHandler(std::move(disc_state_handler));

  auto disc_results_handler = std::make_unique<PluginStreamHandler>();
  plugin->discovery_results_handler_ = disc_results_handler.get();
  plugin->discovery_results_channel_->SetStreamHandler(std::move(disc_results_handler));

  registrar->AddPlugin(std::move(plugin));
}

FlutterClassicBluetoothPlugin::FlutterClassicBluetoothPlugin(
    flutter::BinaryMessenger* messenger)
    : messenger_(messenger) {
  InitWinsock();
  // Created on the platform thread so its message-only window pumps on it.
  dispatcher_ = std::make_shared<UiThreadDispatcher>();
}

FlutterClassicBluetoothPlugin::~FlutterClassicBluetoothPlugin() {
  discovering_.store(false);
  // Clean up connections and servers
  {
    std::lock_guard<std::mutex> lock(connections_mutex_);
    for (auto& [id, conn] : connections_) {
      conn->Close();
    }
    connections_.clear();
    connection_channels_.clear();
  }
  {
    std::lock_guard<std::mutex> lock(servers_mutex_);
    for (auto& [id, server] : servers_) {
      server->Stop();
    }
    servers_.clear();
    server_channels_.clear();
  }
  // Destroyed last, on the platform thread. Read threads only hold a weak_ptr,
  // so this is the sole owner and DestroyWindow runs on the creating thread.
  dispatcher_.reset();
  CleanupWinsock();
}

void FlutterClassicBluetoothPlugin::InitWinsock() {
  WSADATA wsa_data;
  int err = WSAStartup(MAKEWORD(2, 2), &wsa_data);
  if (err == 0) {
    wsa_initialized_ = true;
  } else {
    // Without Winsock, every socket operation will fail. Surface it in the
    // debug log so the cause is diagnosable rather than silently swallowed;
    // connect()/startServer() also report it to Dart as connectionFailed.
    char msg[96];
    std::snprintf(msg, sizeof(msg),
                  "flutter_classic_bluetooth: WSAStartup failed (error %d)\n", err);
    OutputDebugStringA(msg);
  }
}

void FlutterClassicBluetoothPlugin::CleanupWinsock() {
  if (wsa_initialized_) {
    WSACleanup();
    wsa_initialized_ = false;
  }
}

void FlutterClassicBluetoothPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {

  const auto& method = method_call.method_name();

  // Winsock2 AF_BTH sockets need no manifest capability and raise no runtime
  // prompt, so there is no permission for the caller to hold or request.
  if (method == "checkPermissions" || method == "requestPermissions") {
    result->Success(EncodableValue("notRequired"));
  } else if (method == "openAppSettings") {
    result->Success(EncodableValue(false));
  } else if (method == "isSupported") {
    HandleIsSupported(std::move(result));
  } else if (method == "isEnabled") {
    HandleIsEnabled(std::move(result));
  } else if (method == "enableBluetooth" || method == "disableBluetooth") {
    result->Error("unsupported", "Cannot programmatically enable/disable Bluetooth on Windows",
                  EncodableValue(EncodableMap{
                      {EncodableValue("feature"), EncodableValue(method)},
                      {EncodableValue("platform"), EncodableValue("Windows")}}));
  } else if (method == "getAdapterName") {
    HandleGetAdapterName(std::move(result));
  } else if (method == "getAdapterAddress") {
    HandleGetAdapterAddress(std::move(result));
  } else if (method == "startDiscovery") {
    HandleStartDiscovery(std::move(result));
  } else if (method == "stopDiscovery") {
    HandleStopDiscovery(std::move(result));
  } else if (method == "isDiscovering") {
    result->Success(EncodableValue(discovering_.load()));
  } else if (method == "getPairedDevices") {
    HandleGetPairedDevices(std::move(result));
  } else if (method == "bondDevice") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) HandleBondDevice(*args, std::move(result));
    else result->Error("invalidArguments", "Arguments required", EncodableValue());
  } else if (method == "unbondDevice") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) HandleUnbondDevice(*args, std::move(result));
    else result->Error("invalidArguments", "Arguments required", EncodableValue());
  } else if (method == "connect") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) HandleConnect(*args, std::move(result));
    else result->Error("invalidArguments", "Arguments required", EncodableValue());
  } else if (method == "disconnect") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) HandleDisconnect(*args, std::move(result));
    else result->Error("invalidArguments", "Arguments required", EncodableValue());
  } else if (method == "write") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) HandleWrite(*args, std::move(result));
    else result->Error("invalidArguments", "Arguments required", EncodableValue());
  } else if (method == "startServer") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) HandleStartServer(*args, std::move(result));
    else result->Error("invalidArguments", "Arguments required", EncodableValue());
  } else if (method == "stopServer") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args) HandleStopServer(*args, std::move(result));
    else result->Error("invalidArguments", "Arguments required", EncodableValue());
  } else if (method == "setDiscoverable") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    HandleSetDiscoverable(args, std::move(result));
  } else if (method == "getPlatformCapabilities") {
    HandleGetPlatformCapabilities(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void FlutterClassicBluetoothPlugin::HandleIsSupported(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  HANDLE radio = nullptr;
  BLUETOOTH_FIND_RADIO_PARAMS params = {sizeof(BLUETOOTH_FIND_RADIO_PARAMS)};
  HBLUETOOTH_RADIO_FIND find = BluetoothFindFirstRadio(&params, &radio);
  bool supported = (find != nullptr);
  if (find) {
    BluetoothFindRadioClose(find);
    CloseHandle(radio);
  }
  result->Success(EncodableValue(supported));
}

void FlutterClassicBluetoothPlugin::HandleIsEnabled(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  HANDLE radio = nullptr;
  BLUETOOTH_FIND_RADIO_PARAMS params = {sizeof(BLUETOOTH_FIND_RADIO_PARAMS)};
  HBLUETOOTH_RADIO_FIND find = BluetoothFindFirstRadio(&params, &radio);
  bool enabled = false;
  if (find) {
    enabled = BluetoothIsConnectable(radio) != FALSE;
    BluetoothFindRadioClose(find);
    CloseHandle(radio);
  }
  result->Success(EncodableValue(enabled));
}

void FlutterClassicBluetoothPlugin::HandleGetAdapterName(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  HANDLE radio = nullptr;
  BLUETOOTH_FIND_RADIO_PARAMS params = {sizeof(BLUETOOTH_FIND_RADIO_PARAMS)};
  HBLUETOOTH_RADIO_FIND find = BluetoothFindFirstRadio(&params, &radio);
  if (find) {
    BLUETOOTH_RADIO_INFO info = {sizeof(BLUETOOTH_RADIO_INFO)};
    if (BluetoothGetRadioInfo(radio, &info) == ERROR_SUCCESS) {
      result->Success(EncodableValue(WideToUtf8(info.szName)));
    } else {
      result->Success(EncodableValue());
    }
    BluetoothFindRadioClose(find);
    CloseHandle(radio);
  } else {
    result->Success(EncodableValue());
  }
}

void FlutterClassicBluetoothPlugin::HandleGetAdapterAddress(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  HANDLE radio = nullptr;
  BLUETOOTH_FIND_RADIO_PARAMS params = {sizeof(BLUETOOTH_FIND_RADIO_PARAMS)};
  HBLUETOOTH_RADIO_FIND find = BluetoothFindFirstRadio(&params, &radio);
  if (find) {
    BLUETOOTH_RADIO_INFO info = {sizeof(BLUETOOTH_RADIO_INFO)};
    if (BluetoothGetRadioInfo(radio, &info) == ERROR_SUCCESS) {
      result->Success(EncodableValue(AddressToString(info.address)));
    } else {
      result->Success(EncodableValue());
    }
    BluetoothFindRadioClose(find);
    CloseHandle(radio);
  } else {
    result->Success(EncodableValue());
  }
}

void FlutterClassicBluetoothPlugin::HandleStartDiscovery(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (discovering_.load()) {
    result->Success(EncodableValue());
    return;
  }

  discovering_.store(true);

  // Notify Dart that discovery has started
  if (discovery_state_handler_ && discovery_state_handler_->sink()) {
    discovery_state_handler_->sink()->Success(EncodableValue(true));
  }

  // Discovery runs in a background thread, but channel messages must be sent on
  // the platform thread, so results and the final state are routed through the
  // dispatcher instead of touching the sinks directly.
  std::weak_ptr<UiThreadDispatcher> weak_dispatcher = dispatcher_;
  discovery_thread_ = std::thread([this, weak_dispatcher]() {
    BLUETOOTH_DEVICE_SEARCH_PARAMS search_params = {};
    search_params.dwSize = sizeof(BLUETOOTH_DEVICE_SEARCH_PARAMS);
    search_params.fReturnAuthenticated = TRUE;
    search_params.fReturnRemembered = TRUE;
    search_params.fReturnUnknown = TRUE;
    search_params.fReturnConnected = TRUE;
    search_params.fIssueInquiry = TRUE;
    search_params.cTimeoutMultiplier = 8; // ~10 seconds

    BLUETOOTH_DEVICE_INFO device_info = {};
    device_info.dwSize = sizeof(BLUETOOTH_DEVICE_INFO);

    HBLUETOOTH_DEVICE_FIND find = BluetoothFindFirstDevice(&search_params, &device_info);
    if (find) {
      do {
        if (!discovering_.load()) break;
        auto device_map = DeviceToMap(device_info);
        if (auto d = weak_dispatcher.lock()) {
          d->Post([this, device_map]() {
            if (discovery_results_handler_ && discovery_results_handler_->sink()) {
              discovery_results_handler_->sink()->Success(EncodableValue(device_map));
            }
          });
        }
      } while (BluetoothFindNextDevice(find, &device_info));
      BluetoothFindDeviceClose(find);
    }
    discovering_.store(false);
    if (auto d = weak_dispatcher.lock()) {
      d->Post([this]() {
        if (discovery_state_handler_ && discovery_state_handler_->sink()) {
          discovery_state_handler_->sink()->Success(EncodableValue(false));
        }
      });
    }
  });
  discovery_thread_.detach();

  result->Success(EncodableValue());
}

void FlutterClassicBluetoothPlugin::HandleStopDiscovery(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  discovering_.store(false);
  result->Success(EncodableValue());
}

void FlutterClassicBluetoothPlugin::HandleGetPairedDevices(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  BLUETOOTH_DEVICE_SEARCH_PARAMS search_params = {};
  search_params.dwSize = sizeof(BLUETOOTH_DEVICE_SEARCH_PARAMS);
  search_params.fReturnAuthenticated = TRUE;
  search_params.fReturnRemembered = TRUE;
  search_params.fReturnUnknown = FALSE;
  search_params.fReturnConnected = TRUE;
  search_params.fIssueInquiry = FALSE;

  BLUETOOTH_DEVICE_INFO device_info = {};
  device_info.dwSize = sizeof(BLUETOOTH_DEVICE_INFO);

  EncodableList devices;
  HBLUETOOTH_DEVICE_FIND find = BluetoothFindFirstDevice(&search_params, &device_info);
  if (find) {
    do {
      if (device_info.fAuthenticated || device_info.fRemembered) {
        devices.push_back(EncodableValue(DeviceToMap(device_info)));
      }
    } while (BluetoothFindNextDevice(find, &device_info));
    BluetoothFindDeviceClose(find);
  }
  result->Success(EncodableValue(devices));
}

void FlutterClassicBluetoothPlugin::HandleBondDevice(
    const EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  auto it = args.find(EncodableValue("address"));
  if (it == args.end()) {
    result->Error("invalidAddress", "Address is required", EncodableValue());
    return;
  }
  std::string address = std::get<std::string>(it->second);
  BTH_ADDR bth_addr = StringToAddress(address);

  BLUETOOTH_DEVICE_INFO device_info = {};
  device_info.dwSize = sizeof(BLUETOOTH_DEVICE_INFO);
  device_info.Address.ullLong = bth_addr;

  DWORD auth_result = BluetoothAuthenticateDeviceEx(
      nullptr, nullptr, &device_info, nullptr, MITMProtectionNotRequired);

  result->Success(EncodableValue(auth_result == ERROR_SUCCESS));
}

void FlutterClassicBluetoothPlugin::HandleUnbondDevice(
    const EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  auto it = args.find(EncodableValue("address"));
  if (it == args.end()) {
    result->Error("invalidAddress", "Address is required", EncodableValue());
    return;
  }
  std::string address = std::get<std::string>(it->second);
  BTH_ADDR bth_addr = StringToAddress(address);

  BLUETOOTH_ADDRESS bt_addr;
  bt_addr.ullLong = bth_addr;
  DWORD remove_result = BluetoothRemoveDevice(&bt_addr);
  result->Success(EncodableValue(remove_result == ERROR_SUCCESS));
}

void FlutterClassicBluetoothPlugin::HandleConnect(
    const EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (!wsa_initialized_) {
    result->Error("connectionFailed",
                  "Winsock is not initialized; Bluetooth sockets are unavailable",
                  EncodableValue());
    return;
  }

  auto addr_it = args.find(EncodableValue("address"));
  auto uuid_it = args.find(EncodableValue("uuid"));
  auto secure_it = args.find(EncodableValue("secure"));

  if (addr_it == args.end()) {
    result->Error("connectionFailed", "Address is required", EncodableValue());
    return;
  }

  std::string address = std::get<std::string>(addr_it->second);
  std::string uuid = "00001101-0000-1000-8000-00805F9B34FB";
  if (uuid_it != args.end()) {
    uuid = std::get<std::string>(uuid_it->second);
  }
  bool secure = true;
  if (secure_it != args.end()) {
    if (const auto* b = std::get_if<bool>(&secure_it->second)) secure = *b;
  }

  BTH_ADDR bth_addr = StringToAddress(address);

  // Connect on a background thread (connect() blocks), then marshal the result
  // and channel registration back to the platform thread via the dispatcher.
  auto result_ptr = std::shared_ptr<flutter::MethodResult<EncodableValue>>(std::move(result));
  std::weak_ptr<UiThreadDispatcher> weak_dispatcher = dispatcher_;
  std::thread([this, bth_addr, uuid, address, secure, result_ptr, weak_dispatcher]() {
    SOCKET sock = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
    if (sock == INVALID_SOCKET) {
      auto d = weak_dispatcher.lock();
      if (d) d->Post([result_ptr, address]() {
        result_ptr->Error("connectionFailed", "Failed to create socket",
                          EncodableValue(EncodableMap{
                              {EncodableValue("address"), EncodableValue(address)}}));
      });
      return;
    }

    // Honor the secure flag: request an authenticated (and thus encrypted)
    // RFCOMM link before connecting. Best-effort, ignored if unsupported.
    if (secure) {
      ULONG auth = TRUE;
      setsockopt(sock, SOL_RFCOMM, SO_BTH_AUTHENTICATE,
                 reinterpret_cast<const char*>(&auth), sizeof(auth));
    }

    SOCKADDR_BTH addr = {};
    addr.addressFamily = AF_BTH;
    addr.btAddr = bth_addr;
    addr.serviceClassId = StringToGuid(uuid);
    addr.port = 0;

    if (connect(sock, (SOCKADDR*)&addr, sizeof(addr)) == SOCKET_ERROR) {
      closesocket(sock);
      auto d = weak_dispatcher.lock();
      if (d) d->Post([result_ptr, address]() {
        result_ptr->Error("connectionFailed", "Failed to connect",
                          EncodableValue(EncodableMap{
                              {EncodableValue("address"), EncodableValue(address)}}));
      });
      return;
    }

    auto d = weak_dispatcher.lock();
    if (!d) {
      // Plugin is shutting down; don't leak the socket.
      closesocket(sock);
      return;
    }
    d->Post([this, sock, address, result_ptr]() {
      int conn_id;
      {
        std::lock_guard<std::mutex> lock(connections_mutex_);
        conn_id = next_connection_id_++;
        auto connection = std::make_unique<BluetoothConnection>(conn_id, sock, address);
        SetupConnectionStreams(conn_id, connection.get());
        connections_[conn_id] = std::move(connection);
      }
      EncodableMap response;
      response[EncodableValue("id")] = EncodableValue(conn_id);
      response[EncodableValue("address")] = EncodableValue(address);
      result_ptr->Success(EncodableValue(response));
    });
  }).detach();
}

void FlutterClassicBluetoothPlugin::SetupConnectionStreams(
    int conn_id, BluetoothConnection* connection) {
  // Caller holds connections_mutex_ and runs on the platform thread.
  auto channels = std::make_shared<ConnectionChannels>();

  std::string data_name = "flutter_classic_bluetooth/connection/" + std::to_string(conn_id);
  std::string state_name =
      "flutter_classic_bluetooth/connection_state/" + std::to_string(conn_id);

  channels->data_channel = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger_, data_name, &flutter::StandardMethodCodec::GetInstance());
  channels->data_channel->SetStreamHandler(
      std::make_unique<SharedStreamHandler>(channels->data_sink));

  channels->state_channel = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger_, state_name, &flutter::StandardMethodCodec::GetInstance());
  channels->state_channel->SetStreamHandler(
      std::make_unique<SharedStreamHandler>(channels->state_sink));

  connection_channels_[conn_id] = channels;

  // Capture sinks + a weak dispatcher; the read thread is detached and must not
  // touch the sink directly (Flutter requires platform-thread delivery).
  auto data_sink = channels->data_sink;
  auto state_sink = channels->state_sink;
  std::weak_ptr<UiThreadDispatcher> weak_dispatcher = dispatcher_;

  connection->StartReading(
      [data_sink, weak_dispatcher](const std::vector<uint8_t>& data) {
        auto d = weak_dispatcher.lock();
        if (!d) return;
        d->Post([data_sink, data]() {
          data_sink->Success(EncodableValue(data));
        });
      },
      [state_sink, weak_dispatcher]() {
        auto d = weak_dispatcher.lock();
        if (!d) return;
        d->Post([state_sink]() {
          state_sink->Success(EncodableValue(std::string("disconnected")));
          state_sink->EndOfStream();
        });
      });

  // Emit the initial "connected" state (best-effort; delivered if/when listened).
  if (auto d = dispatcher_) {
    d->Post([state_sink]() {
      state_sink->Success(EncodableValue(std::string("connected")));
    });
  }
}

void FlutterClassicBluetoothPlugin::HandleDisconnect(
    const EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  auto it = args.find(EncodableValue("id"));
  int id;
  if (it == args.end() || !ExtractInt(it->second, &id)) {
    result->Error("connectionFailed", "Connection ID is required", EncodableValue());
    return;
  }

  std::lock_guard<std::mutex> lock(connections_mutex_);
  auto conn_it = connections_.find(id);
  if (conn_it != connections_.end()) {
    conn_it->second->Close();
    connections_.erase(conn_it);
  }
  // Destroying the EventChannels unregisters them. Any in-flight dispatcher
  // tasks still hold a shared_ptr to the SinkHolders, so this is leak-free.
  connection_channels_.erase(id);
  result->Success(EncodableValue());
}

void FlutterClassicBluetoothPlugin::HandleWrite(
    const EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  auto id_it = args.find(EncodableValue("id"));
  auto data_it = args.find(EncodableValue("data"));

  int id;
  if (id_it == args.end() || data_it == args.end() ||
      !ExtractInt(id_it->second, &id)) {
    result->Error("writeFailed", "Connection ID and data are required", EncodableValue());
    return;
  }

  const auto* data_ptr = std::get_if<std::vector<uint8_t>>(&data_it->second);
  if (!data_ptr) {
    result->Error("writeFailed", "data must be a byte list", EncodableValue());
    return;
  }
  const auto& data = *data_ptr;

  std::lock_guard<std::mutex> lock(connections_mutex_);
  auto conn_it = connections_.find(id);
  if (conn_it == connections_.end()) {
    result->Error("connectionFailed", "Connection not found", EncodableValue());
    return;
  }

  if (conn_it->second->Write(data)) {
    result->Success(EncodableValue());
  } else {
    result->Error("writeFailed", "Failed to write data", EncodableValue());
  }
}

void FlutterClassicBluetoothPlugin::HandleStartServer(
    const EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (!wsa_initialized_) {
    result->Error("connectionFailed",
                  "Winsock is not initialized; Bluetooth sockets are unavailable",
                  EncodableValue());
    return;
  }

  std::string uuid = "00001101-0000-1000-8000-00805F9B34FB";
  std::string service_name = "FlutterBluetooth";
  bool secure = true;

  auto uuid_it = args.find(EncodableValue("uuid"));
  if (uuid_it != args.end()) uuid = std::get<std::string>(uuid_it->second);

  auto name_it = args.find(EncodableValue("serviceName"));
  if (name_it != args.end()) service_name = std::get<std::string>(name_it->second);

  auto secure_it = args.find(EncodableValue("secure"));
  if (secure_it != args.end()) secure = std::get<bool>(secure_it->second);

  int server_id;
  {
    std::lock_guard<std::mutex> lock(servers_mutex_);
    server_id = next_server_id_++;

    // Register the server/{id} event channel that BtcServerSocket.connections
    // listens on; each accepted client is delivered here as {id, address}.
    auto server_channel = std::make_shared<ServerChannel>();
    std::string ch_name =
        "flutter_classic_bluetooth/server/" + std::to_string(server_id);
    server_channel->channel = std::make_unique<flutter::EventChannel<EncodableValue>>(
        messenger_, ch_name, &flutter::StandardMethodCodec::GetInstance());
    server_channel->channel->SetStreamHandler(
        std::make_unique<SharedStreamHandler>(server_channel->sink));
    server_channels_[server_id] = server_channel;
    auto server_sink = server_channel->sink;

    auto server = std::make_unique<BluetoothServer>(server_id, uuid, service_name, secure);

    std::weak_ptr<UiThreadDispatcher> weak_dispatcher = dispatcher_;
    bool started = server->Start(
        [this, weak_dispatcher, server_sink](SOCKET client_socket,
                                             const std::string& address) {
          // The accept loop runs on a background thread; register the client's
          // connection streams on the platform thread.
          auto d = weak_dispatcher.lock();
          if (!d) {
            closesocket(client_socket);
            return;
          }
          d->Post([this, client_socket, address, server_sink]() {
            int conn_id;
            {
              std::lock_guard<std::mutex> lock(connections_mutex_);
              conn_id = next_connection_id_++;
              auto connection =
                  std::make_unique<BluetoothConnection>(conn_id, client_socket, address);
              SetupConnectionStreams(conn_id, connection.get());
              connections_[conn_id] = std::move(connection);
            }
            // Notify Dart of the accepted client (after its channels exist).
            server_sink->Success(EncodableValue(EncodableMap{
                {EncodableValue("id"), EncodableValue(conn_id)},
                {EncodableValue("address"), EncodableValue(address)}}));
          });
        });

    if (!started) {
      server_channels_.erase(server_id);
      result->Error("connectionFailed", "Failed to start server", EncodableValue());
      return;
    }

    servers_[server_id] = std::move(server);
  }

  EncodableMap response;
  response[EncodableValue("id")] = EncodableValue(server_id);
  result->Success(EncodableValue(response));
}

void FlutterClassicBluetoothPlugin::HandleStopServer(
    const EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  auto it = args.find(EncodableValue("id"));
  int id;
  if (it == args.end() || !ExtractInt(it->second, &id)) {
    result->Error("connectionFailed", "Server ID is required", EncodableValue());
    return;
  }

  std::lock_guard<std::mutex> lock(servers_mutex_);
  auto server_it = servers_.find(id);
  if (server_it != servers_.end()) {
    server_it->second->Stop();
    servers_.erase(server_it);
  }
  server_channels_.erase(id);
  result->Success(EncodableValue());
}

void FlutterClassicBluetoothPlugin::HandleSetDiscoverable(
    const EncodableMap* args,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  int duration = 120;
  if (args) {
    auto it = args->find(EncodableValue("duration"));
    if (it != args->end()) {
      int d;
      if (ExtractInt(it->second, &d)) duration = d;
    }
  }

  bool ok = false;
  HANDLE radio = nullptr;
  BLUETOOTH_FIND_RADIO_PARAMS params = {sizeof(BLUETOOTH_FIND_RADIO_PARAMS)};
  HBLUETOOTH_RADIO_FIND find = BluetoothFindFirstRadio(&params, &radio);
  if (find) {
    // Make the radio connectable + discoverable (inquiry scan).
    BluetoothEnableIncomingConnections(radio, TRUE);
    ok = BluetoothEnableDiscovery(radio, TRUE) != FALSE;
    BluetoothFindRadioClose(find);
    CloseHandle(radio);
  }

  // Windows has no built-in discoverability timeout; honor the requested
  // duration by turning discovery back off afterwards.
  if (ok && duration > 0) {
    std::thread([duration]() {
      std::this_thread::sleep_for(std::chrono::seconds(duration));
      BluetoothEnableDiscovery(nullptr, FALSE);
    }).detach();
  }

  result->Success(EncodableValue(ok));
}

void FlutterClassicBluetoothPlugin::HandleGetPlatformCapabilities(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  EncodableMap caps;
  caps[EncodableValue("canEnableBluetooth")] = EncodableValue(false);
  caps[EncodableValue("canDisableBluetooth")] = EncodableValue(false);
  caps[EncodableValue("canDiscoverDevices")] = EncodableValue(true);
  caps[EncodableValue("canGetPairedDevices")] = EncodableValue(true);
  caps[EncodableValue("canBondDevices")] = EncodableValue(true);
  caps[EncodableValue("canUnbondDevices")] = EncodableValue(true);
  caps[EncodableValue("canCreateServer")] = EncodableValue(true);
  caps[EncodableValue("canSetDiscoverable")] = EncodableValue(true);
  caps[EncodableValue("supportsMultipleConnections")] = EncodableValue(true);
  caps[EncodableValue("supportsSecureConnection")] = EncodableValue(true);
  caps[EncodableValue("supportsInsecureConnection")] = EncodableValue(true);
  caps[EncodableValue("requiresMfiCertification")] = EncodableValue(false);
  caps[EncodableValue("platformNote")] = EncodableValue(
      std::string("Windows: Bluetooth Classic via Winsock2 AF_BTH. Cannot programmatically enable/disable Bluetooth."));
  result->Success(EncodableValue(caps));
}

}  // namespace flutter_classic_bluetooth
