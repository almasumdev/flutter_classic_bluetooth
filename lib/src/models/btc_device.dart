import 'btc_enums.dart';

/// Represents a Bluetooth Classic remote device.
///
/// Contains device information obtained from discovery or paired device queries.
///
/// | Property | Android | Windows | macOS | Linux | iOS |
/// |----------|---------|---------|-------|-------|-----|
/// | address | Yes MAC | Yes MAC | Yes MAC | Yes MAC | ⚠️ serial/ID |
/// | name | Yes | Yes | Yes | Yes | Yes |
/// | alias | Yes API 30+ | No | No | No | No |
/// | rssi | Yes | No | Yes | No | No |
/// | type | Yes | No | No | No | No |
/// | bondState | Yes | Yes | Yes | Yes | Yes (always bonded) |
/// | uuids | Yes | Yes | Yes | No | ⚠️ protocol strings |
///
/// {@category Models}
class BtcDevice {
  /// The hardware address of the device.
  ///
  /// On most platforms this is the MAC address (e.g. `"AA:BB:CC:DD:EE:FF"`).
  /// On iOS this is the accessory serial number or connection ID string.
  final String address;

  /// The broadcasted friendly name of the device, or null if unknown.
  final String? name;

  /// The locally set alias name, if available.
  ///
  /// Only available on Android (API 30+) and Linux.
  final String? alias;

  /// Signal strength in dBm, reported during discovery.
  ///
  /// Null if not available or not discovered via scan.
  final int? rssi;

  /// The type of Bluetooth device.
  final BtcDeviceType type;

  /// The current bond/pairing state.
  final BtcBondState bondState;

  /// Service UUIDs advertised by the device.
  ///
  /// On iOS these are MFi protocol strings.
  final List<String> uuids;

  /// Creates a [BtcDevice] for [address] with optional discovery metadata.
  const BtcDevice({
    required this.address,
    this.name,
    this.alias,
    this.rssi,
    this.type = BtcDeviceType.unknown,
    this.bondState = BtcBondState.none,
    this.uuids = const [],
  });

  /// Creates a [BtcDevice] from a platform channel map.
  factory BtcDevice.fromMap(Map<dynamic, dynamic> map) {
    return BtcDevice(
      address: map['address'] as String,
      name: map['name'] as String?,
      alias: map['alias'] as String?,
      rssi: map['rssi'] as int?,
      type: BtcDeviceType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => BtcDeviceType.unknown,
      ),
      bondState: BtcBondState.values.firstWhere(
        (e) => e.name == map['bondState'],
        orElse: () => BtcBondState.none,
      ),
      uuids: List<String>.from(map['uuids'] ?? []),
    );
  }

  /// Converts this device to a map for platform channel communication.
  Map<String, dynamic> toMap() {
    return {
      'address': address,
      'name': name,
      'alias': alias,
      'rssi': rssi,
      'type': type.name,
      'bondState': bondState.name,
      'uuids': uuids,
    };
  }

  /// Returns the best available display name for this device.
  String get displayName => alias ?? name ?? address;

  /// Returns a copy updated with the non-null/known fields of [other].
  ///
  /// Useful when merging repeated discovery sightings of the same device: a
  /// follow-up scan event (e.g. an RSSI refresh) often omits the name, and this
  /// preserves the earlier value instead of blanking it.
  BtcDevice mergedWith(BtcDevice other) => BtcDevice(
    address: other.address,
    name: other.name ?? name,
    alias: other.alias ?? alias,
    rssi: other.rssi ?? rssi,
    type: other.type != BtcDeviceType.unknown ? other.type : type,
    bondState: other.bondState != BtcBondState.none
        ? other.bondState
        : bondState,
    uuids: other.uuids.isNotEmpty ? other.uuids : uuids,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BtcDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() =>
      'BtcDevice(address: $address, name: $name, bondState: $bondState)';
}
