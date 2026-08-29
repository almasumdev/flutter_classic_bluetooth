package com.flutter_classic_bluetooth.flutter_classic_bluetooth

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build

object BluetoothHelper {
    const val NAMESPACE = "flutter_classic_bluetooth"
    const val METHOD_CHANNEL = "$NAMESPACE/methods"
    const val ADAPTER_STATE_CHANNEL = "$NAMESPACE/adapter_state"
    const val DISCOVERY_STATE_CHANNEL = "$NAMESPACE/discovery_state"
    const val DISCOVERY_RESULTS_CHANNEL = "$NAMESPACE/discovery_results"
    const val BOND_STATE_CHANNEL = "$NAMESPACE/bond_state"
    fun connectionChannel(id: Int) = "$NAMESPACE/connection/$id"
    fun connectionStateChannel(id: Int) = "$NAMESPACE/connection_state/$id"
    fun serverChannel(id: Int) = "$NAMESPACE/server/$id"

    const val DEFAULT_UUID = "00001101-0000-1000-8000-00805F9B34FB"

    /**
     * Registers a receiver for system (protected) Bluetooth broadcasts, passing
     * the export flag required since Android 14 (API 34). The Bluetooth adapter,
     * bond and discovery actions are system broadcasts, so [Context.RECEIVER_EXPORTED]
     * is the correct flag.
     */
    fun registerExportedReceiver(
        context: Context,
        receiver: BroadcastReceiver,
        filter: IntentFilter,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
    }

    fun adapterStateToString(state: Int): String = when (state) {
        BluetoothAdapter.STATE_OFF -> "off"
        BluetoothAdapter.STATE_TURNING_ON -> "turningOn"
        BluetoothAdapter.STATE_ON -> "on"
        BluetoothAdapter.STATE_TURNING_OFF -> "turningOff"
        else -> "unknown"
    }

    fun bondStateToString(state: Int): String = when (state) {
        BluetoothDevice.BOND_NONE -> "none"
        BluetoothDevice.BOND_BONDING -> "bonding"
        BluetoothDevice.BOND_BONDED -> "bonded"
        else -> "none"
    }

    @Suppress("MissingPermission")
    fun deviceTypeToString(device: BluetoothDevice): String = when (device.type) {
        BluetoothDevice.DEVICE_TYPE_CLASSIC -> "classic"
        BluetoothDevice.DEVICE_TYPE_DUAL -> "dual"
        BluetoothDevice.DEVICE_TYPE_LE -> "le"
        else -> "unknown"
    }

    @Suppress("MissingPermission")
    fun deviceToMap(device: BluetoothDevice, rssi: Int? = null): Map<String, Any?> {
        // Every property below except the address needs BLUETOOTH_CONNECT on
        // API 31+. This runs on a broadcast receiver during discovery, so a
        // permission revoked mid-scan would otherwise throw where there is no
        // caller to catch it and take the whole app down. A device reported
        // with missing detail beats a crash, and beats dropping it entirely.
        val map = mutableMapOf<String, Any?>(
            "address" to device.address,
            "name" to runCatching { device.name }.getOrNull(),
            "type" to runCatching { deviceTypeToString(device) }.getOrDefault("unknown"),
            "bondState" to runCatching { bondStateToString(device.bondState) }
                .getOrDefault("none"),
            "rssi" to rssi,
            "uuids" to runCatching {
                device.uuids?.map { it.uuid.toString() } ?: emptyList<String>()
            }.getOrDefault(emptyList<String>()),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            map["alias"] = runCatching { device.alias }.getOrNull()
        }
        return map
    }
}
