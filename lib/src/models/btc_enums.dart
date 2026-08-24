/// State of the Bluetooth adapter.
///
/// | State | Description |
/// |-------|-------------|
/// | unknown | Adapter state cannot be determined |
/// | turningOn | Adapter is transitioning to the on state |
/// | on | Adapter is powered on and ready |
/// | turningOff | Adapter is transitioning to the off state |
/// | off | Adapter is powered off |
/// | unauthorized | App lacks permission to access Bluetooth |
/// | unsupported | Device does not have Bluetooth hardware |
///
/// {@category Enums}
enum BtcAdapterState {
  /// Adapter state cannot be determined.
  unknown,

  /// Adapter is transitioning to the on state.
  turningOn,

  /// Adapter is powered on and ready.
  on,

  /// Adapter is transitioning to the off state.
  turningOff,

  /// Adapter is powered off.
  off,

  /// App lacks permission to access Bluetooth.
  unauthorized,

  /// Device does not have Bluetooth hardware.
  unsupported,
}

/// Bond/pairing state of a remote Bluetooth device.
///
/// | State | Description |
/// |-------|-------------|
/// | none | Not bonded with this device |
/// | bonding | Pairing is in progress |
/// | bonded | Device is bonded/paired |
///
/// {@category Enums}
enum BtcBondState {
  /// Not bonded with this device.
  none,

  /// Pairing is in progress.
  bonding,

  /// Device is bonded/paired.
  bonded,
}

/// Type classification of a Bluetooth device.
///
/// | Type | Description |
/// |------|-------------|
/// | classic | Bluetooth Classic (BR/EDR) device |
/// | dual | Dual-mode device supporting both Classic and LE |
/// | le | Bluetooth Low Energy only device |
/// | unknown | Device type could not be determined |
///
/// {@category Enums}
enum BtcDeviceType {
  /// Bluetooth Classic (BR/EDR) device.
  classic,

  /// Dual-mode device supporting both Classic and LE.
  dual,

  /// Bluetooth Low Energy only device.
  le,

  /// Device type could not be determined.
  unknown,
}

/// High-level state of a [BtcReconnectingConnection].
///
/// | State | Description |
/// |-------|-------------|
/// | connecting | Establishing the first connection |
/// | connected | Connected and ready for I/O |
/// | reconnecting | Link dropped; backing off before the next attempt |
/// | closed | Stopped by the caller; no further reconnects |
/// | failed | Gave up after exhausting `maxAttempts` |
///
/// {@category Enums}
enum BtcReconnectState {
  /// Establishing the first connection.
  connecting,

  /// Connected and ready for I/O.
  connected,

  /// The link dropped; waiting/backing off before the next attempt.
  reconnecting,

  /// Stopped by the caller. No further reconnects.
  closed,

  /// Gave up after exhausting `maxAttempts`.
  failed,
}

/// Connection state of an active RFCOMM connection.
///
/// | State | Description |
/// |-------|-------------|
/// | disconnected | No active connection |
/// | connecting | Connection attempt in progress |
/// | connected | Connection is active and ready |
/// | disconnecting | Graceful disconnect in progress |
///
/// {@category Enums}
enum BtcConnectionState {
  /// No active connection.
  disconnected,

  /// Connection attempt in progress.
  ///
  /// Represents the phase while `connect()` is awaiting, before a
  /// [BtcConnection] object exists. A connection is only returned once it
  /// reaches [connected], so this value is observed via the pending future
  /// rather than a connection's `stateStream`.
  connecting,

  /// Connection is active and ready for I/O.
  connected,

  /// Graceful disconnect in progress.
  ///
  /// Emitted on a connection's `stateStream` when `finish()` or `close()`
  /// begins, before the final [disconnected].
  disconnecting,
}

/// Whether the app holds the Bluetooth permissions the platform requires.
///
/// | Status | Description |
/// |--------|-------------|
/// | granted | Every required permission is held |
/// | denied | Not held, but the system will still show a prompt |
/// | permanentlyDenied | Refused for good; only app settings can change it |
/// | notRequired | The platform has no runtime Bluetooth permission |
///
/// Only Android and iOS gate Bluetooth behind a runtime prompt. Windows, macOS
/// and Linux report [notRequired], since their access is decided at build time
/// by a manifest entry or an entitlement rather than by the user at runtime.
///
/// {@category Enums}
enum BtcPermissionStatus {
  /// Every permission the platform requires is held. Bluetooth calls will not
  /// throw `BtcPermissionException`.
  granted,

  /// Not held yet, and the system will still show a prompt when asked.
  ///
  /// This covers both "never asked" and "asked once and dismissed". Calling
  /// `requestPermissions` from this state shows the system dialog.
  denied,

  /// Refused in a way the system will not prompt for again.
  ///
  /// On Android this is a second refusal, or one with "don't ask again"
  /// selected; on iOS, any refusal. `requestPermissions` cannot recover from
  /// here and returns this same status without showing anything, so send the
  /// user to `openAppSettings` instead.
  permanentlyDenied,

  /// The platform has no runtime Bluetooth permission to hold.
  ///
  /// Reported by Windows, macOS and Linux. Treat it exactly like [granted]:
  /// there is nothing to request and nothing for the user to fix.
  notRequired,
}
