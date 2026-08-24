package com.flutter_classic_bluetooth.flutter_classic_bluetooth

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.provider.Settings
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
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

        const val SCAN = "scan"
        const val CONNECT = "connect"
        const val ADVERTISE = "advertise"

        /** What a discover-then-connect app needs, and the channel default. */
        val DEFAULT_SCOPES = listOf(SCAN, CONNECT)
    }

    private var pendingResult: MethodChannel.Result? = null
    /** Whether the outstanding request wants a status string or a boolean. */
    private var pendingWantsStatus = false
    /** The scopes the outstanding request asked for. */
    private var pendingScopes: List<String> = DEFAULT_SCOPES
    private var activity: Activity? = null

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    /**
     * The Android permissions [scopes] map to on this API level.
     *
     * Android 12 (API 31) replaced the single install-time BLUETOOTH grant
     * with three runtime ones, each covering different calls. Below that only
     * discovery is gated, and it is gated by location rather than Bluetooth:
     * API 29 tightened that from coarse to fine. Connecting and advertising
     * need nothing at runtime before API 31, so an empty result there is
     * correct rather than a gap.
     */
    fun permissionsFor(scopes: List<String>): Array<String> {
        val needed = linkedSetOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (scopes.contains(SCAN)) needed.add(Manifest.permission.BLUETOOTH_SCAN)
            if (scopes.contains(CONNECT)) needed.add(Manifest.permission.BLUETOOTH_CONNECT)
            if (scopes.contains(ADVERTISE)) needed.add(Manifest.permission.BLUETOOTH_ADVERTISE)
        } else if (scopes.contains(SCAN)) {
            needed.add(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    Manifest.permission.ACCESS_FINE_LOCATION
                } else {
                    Manifest.permission.ACCESS_COARSE_LOCATION
                }
            )
        }
        return needed.toTypedArray()
    }

    fun hasPermissions(context: Context, scopes: List<String> = DEFAULT_SCOPES): Boolean {
        return permissionsFor(scopes).all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Whether discovery also needs the system location toggle switched on.
     *
     * True through API 30. With the permission held but the toggle off,
     * `startDiscovery` still succeeds and simply never reports a device, which
     * is the least obvious way Bluetooth fails on Android.
     */
    fun isLocationServiceRequired(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S

    fun isLocationServiceEnabled(context: Context): Boolean {
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return false
        return LocationManagerCompat.isLocationEnabled(manager)
    }

    fun openLocationSettings(context: Context): Boolean =
        startSettings(context, Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))

    /**
     * The status of [scopes] as [GRANTED], [DENIED] or [PERMANENTLY_DENIED].
     *
     * `shouldShowRequestPermissionRationale` reads false both before the first
     * ask and after a permanent refusal, so it cannot separate those on its
     * own. A flag persisted per permission records that we have asked, which
     * makes a later false answer mean the system has stopped prompting.
     *
     * A scope that needs nothing on this API level cannot be denied, so an
     * empty permission list reads as [GRANTED].
     */
    fun permissionStatus(context: Context, scopes: List<String> = DEFAULT_SCOPES): String {
        val required = permissionsFor(scopes)
        if (required.isEmpty()) return GRANTED
        if (hasPermissions(context, scopes)) return GRANTED
        val act = activity ?: return DENIED
        val silenced = required.any {
            ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED &&
                hasAsked(context, it) &&
                !ActivityCompat.shouldShowRequestPermissionRationale(act, it)
        }
        return if (silenced) PERMANENTLY_DENIED else DENIED
    }

    /** Requests [scopes] and answers with a [permissionStatus] string. */
    fun requestPermissionsForStatus(
        context: Context,
        scopes: List<String>,
        result: MethodChannel.Result
    ) {
        if (permissionStatus(context, scopes) == GRANTED) {
            result.success(GRANTED)
            return
        }
        // Asking again once the system has stopped prompting shows nothing at
        // all, so report it rather than leaving the caller waiting on a dialog
        // that will never appear.
        if (permissionStatus(context, scopes) == PERMANENTLY_DENIED) {
            result.success(PERMANENTLY_DENIED)
            return
        }
        pendingWantsStatus = true
        requestPermissions(result, scopes)
    }

    /** Opens this app's details page in system settings. */
    fun openAppSettings(context: Context): Boolean = startSettings(
        context,
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null)
        )
    )

    /** Launches [intent], preferring the activity so no new task is created. */
    private fun startSettings(context: Context, intent: Intent): Boolean {
        return try {
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

    private fun hasAsked(context: Context, permission: String): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ASKED + permission, false)

    private fun markAsked(context: Context, permissions: Array<String>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        permissions.forEach { prefs.putBoolean(KEY_ASKED + it, true) }
        prefs.apply()
    }

    fun requestPermissions(
        result: MethodChannel.Result,
        scopes: List<String> = DEFAULT_SCOPES
    ) {
        val wantsStatus = pendingWantsStatus
        val act = activity
        if (act == null) {
            pendingWantsStatus = false
            result.error("permissionDenied", "No activity available to request permissions", null)
            return
        }

        val permissions = permissionsFor(scopes)
        // Nothing to request on this API level, or already held.
        if (permissions.isEmpty() || hasPermissions(act, scopes)) {
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
        pendingScopes = scopes
        markAsked(act, permissions)

        ActivityCompat.requestPermissions(act, permissions, REQUEST_CODE)
    }

    fun ensurePermissions(
        context: Context,
        result: MethodChannel.Result,
        scopes: List<String> = DEFAULT_SCOPES,
        action: () -> Unit
    ) {
        if (hasPermissions(context, scopes)) {
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
            }, scopes)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        // Re-check the scopes that were asked for rather than trusting
        // grantResults, so a partial grant is judged against what the caller
        // actually needs.
        val act = activity
        val scopes = pendingScopes
        val granted = act != null && hasPermissions(act, scopes)
        val wantsStatus = pendingWantsStatus
        pendingWantsStatus = false
        pendingScopes = DEFAULT_SCOPES
        pendingResult?.success(
            when {
                !wantsStatus -> granted
                act == null -> DENIED
                else -> permissionStatus(act, scopes)
            }
        )
        pendingResult = null
        return true
    }
}
