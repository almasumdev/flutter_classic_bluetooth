# Contributing

Thanks for taking the time to help. Bug reports, fixes and platform testing are
all welcome, and reports from real hardware are especially useful because this
package talks to physical devices.

## Reporting a bug

Open an [issue](https://github.com/almasumdev/flutter_classic_bluetooth/issues)
and include:

- The platform and OS version (Android 14, Windows 11, Ubuntu 24.04, and so on).
- The device you are talking to (ESP32, HC-05, a specific printer model).
- Output of `flutter doctor -v` and the package version you are on.
- A small snippet that reproduces it, and the error or stack trace.

Bluetooth Classic behaves differently on every stack, so knowing the exact
platform and peripheral usually saves a round trip.

## Asking a question

If you are not sure whether something is a bug, start a
[discussion](https://github.com/almasumdev/flutter_classic_bluetooth/discussions)
instead. Questions about wiring up a particular device fit better there and stay
searchable for the next person.

## Working on the code

```bash
git clone https://github.com/almasumdev/flutter_classic_bluetooth.git
cd flutter_classic_bluetooth
flutter pub get
```

The example app under `example/` is the quickest way to exercise a change
against real hardware.

Before you open a pull request, run the same checks CI runs:

```bash
dart format .
flutter analyze          # must report no issues
flutter test             # all tests must pass
```

## Layout

```
lib/src/            Dart API, platform interface and method channel
android/            Kotlin, BluetoothSocket
ios/                Swift, ExternalAccessory (MFi accessories only)
macos/              Swift, IOBluetooth
windows/            C++, Winsock2 AF_BTH
linux/              C++, BlueZ over D-Bus with RFCOMM sockets
test/               One file per area, sharing the mock platform in mocks.dart
```

The Dart layer stays platform agnostic. Every platform check belongs in native
code, and anything a platform cannot do should throw a typed exception from the
`BtcException` family rather than failing quietly.

## Pull requests

- Keep the change focused on one thing.
- Add or update tests for any public API change.
- Update `CHANGELOG.md` under a new version heading.
- If you change what a platform can do, update the capability flags, the README
  support matrix and the method's dartdoc table together. Those three are
  expected to agree.

Native changes are hard to verify without the hardware, so please say in the
pull request which platform and which device you tested on.

## License

Contributions are accepted under the [MIT License](LICENSE) that covers this
project.
