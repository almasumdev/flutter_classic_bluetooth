package com.flutter_classic_bluetooth.flutter_classic_bluetooth.receivers

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import com.flutter_classic_bluetooth.flutter_classic_bluetooth.BluetoothHelper
import io.flutter.plugin.common.EventChannel

class ScanResultReceiver(private val context: Context) : EventChannel.StreamHandler {
    private var receiver: BroadcastReceiver? = null

    @Suppress("MissingPermission")
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != BluetoothDevice.ACTION_FOUND) return
                val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    ?: return

                // Not every OEM puts EXTRA_RSSI on the broadcast. Reading it
                // with a sentinel default reported that sentinel as a real
                // signal strength, so check the extra is actually present and
                // report null when it is not.
                val rssi = if (intent.hasExtra(BluetoothDevice.EXTRA_RSSI)) {
                    intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
                        .toInt()
                        .takeIf { it != Short.MIN_VALUE.toInt() }
                } else {
                    null
                }

                // device.type needs BLUETOOTH_CONNECT on API 31+, and throws
                // inside onReceive if it was revoked between the scan starting
                // and this result arriving, which takes the whole app down.
                // An unknown type is reported rather than dropped: skipping a
                // reachable device is worse than listing one extra.
                val isBleOnly = runCatching {
                    device.type == BluetoothDevice.DEVICE_TYPE_LE
                }.getOrDefault(false)
                if (isBleOnly) return

                events.success(BluetoothHelper.deviceToMap(device, rssi))
            }
        }
        BluetoothHelper.registerExportedReceiver(
            context, receiver!!, IntentFilter(BluetoothDevice.ACTION_FOUND)
        )
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let {
            // Unregistering a receiver that is already gone throws, and there
            // is nothing useful to do about it here.
            runCatching { context.unregisterReceiver(it) }
        }
        receiver = null
    }
}
