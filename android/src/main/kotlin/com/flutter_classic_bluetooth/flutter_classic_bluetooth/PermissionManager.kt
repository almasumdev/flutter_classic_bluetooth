package com.flutter_classic_bluetooth.flutter_classic_bluetooth

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class PermissionManager : PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val REQUEST_CODE = 29571
        private const val PREFS = "flutter_classic_bluetooth"
        private const val KEY_ASKED = "permissionsRequested"

        const val GRANTED = "granted"
        const val DENIED = "denied"
        const val PERMANENTLY_DENIED = "permanentlyDenied"
    }

    private var pendingResult: MethodChannel.Result? = null
    /** Whether the outstanding request wants a status string or a boolean. */
    private var pendingWantsStatus = false
    private var activity: Activity? = null

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    fun hasPermissions(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }

    /** The permissions [hasPermissions] checks, for rationale lookups. */
    private fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    /**
     * The current status as one of [GRANTED], [DENIED] or [PERMANENTLY_DENIED].
     *
     * `shouldShowRequestPermissionRationale` is false both before the first
     * ask and after a permanent refusal, so it cannot tell those apart on its
     * own. A persisted flag records that we have asked at least once, which
     * makes a later false answer mean "the system has stopped prompting".
     */
    fun permissionStatus(context: Context): String {
        if (hasPermissions(context)) return GRANTED
        val act = activity ?: return DENIED
        if (!hasAsked(context)) return DENIED
        val silenced = requiredPermissions().any {
            !ActivityCompat.shouldShowRequestPermissionRationale(act, it)
        }
        return if (silenced) PERMANENTLY_DENIED else DENIED
    }

    /** Requests permissions and answers with a [permissionStatus] string. */
    fun requestPermissionsForStatus(context: Context, result: MethodChannel.Result) {
        if (hasPermissions(context)) {
            result.success(GRANTED)
            return
        }
        // Asking again once the system has stopped prompting shows nothing at
        // all, so report it rather than leaving the caller waiting on a dialog
        // that will never appear.
        if (permissionStatus(context) == PERMANENTLY_DENIED) {
            result.success(PERMANENTLY_DENIED)
            return
        }
        pendingWantsStatus = true
        requestPermissions(result)
    }

    /** Opens this app's details page in system settings. */
    fun openAppSettings(context: Context): Boolean {
        return try {
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null)
            )
            val host = activity
            if (host != null) {
                host.startActivity(intent)
            } else {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun hasAsked(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ASKED, false)

    private fun markAsked(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ASKED, true).apply()
    }

    fun requestPermissions(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            pendingWantsStatus = false
            result.error("permissionDenied", "No activity available to request permissions", null)
            return
        }

        if (hasPermissions(act)) {
            val wantsStatus = pendingWantsStatus
            pendingWantsStatus = false
            result.success(if (wantsStatus) GRANTED else true)
            return
        }

        // Only one OS permission dialog can be outstanding; reject re-entrant
        // requests instead of overwriting (and orphaning) the previous result.
        if (pendingResult != null) {
            pendingWantsStatus = false
            result.error("pendingOperation",
                "A permission request is already in progress", null)
            return
        }
        pendingResult = result
        markAsked(act)

        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE
            )
        } else {
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        }

        ActivityCompat.requestPermissions(act, permissions, REQUEST_CODE)
    }

    fun ensurePermissions(context: Context, result: MethodChannel.Result, action: () -> Unit) {
        if (hasPermissions(context)) {
            action()
        } else {
            requestPermissions(object : MethodChannel.Result {
                override fun success(r: Any?) {
                    if (r == true) action()
                    else result.error("permissionDenied", "Bluetooth permissions denied", null)
                }
                override fun error(code: String, msg: String?, details: Any?) {
                    result.error(code, msg, details)
                }
                override fun notImplemented() {
                    result.notImplemented()
                }
            })
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        // Re-check the permissions we actually require (SCAN+CONNECT, or location
        // pre-S) rather than requiring every requested grant; denying the
        // optional ADVERTISE permission must not fail otherwise-granted calls.
        val act = activity
        val granted = act != null && hasPermissions(act)
        val wantsStatus = pendingWantsStatus
        pendingWantsStatus = false
        pendingResult?.success(
            when {
                !wantsStatus -> granted
                act == null -> DENIED
                else -> permissionStatus(act)
            }
        )
        pendingResult = null
        return true
    }
}
