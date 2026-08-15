# Security Policy

## Supported versions

Fixes land on the latest published version. Please reproduce on the newest
release before reporting.

| Version | Supported |
| ------- | --------- |
| Latest release | Yes |
| Anything older | No, please upgrade first |

## Reporting a vulnerability

Do not open a public issue for a security problem.

Use GitHub's private reporting on the
[Security tab](https://github.com/almasumdev/flutter_classic_bluetooth/security/advisories/new),
or email dev.almasum@gmail.com. Include the platform, a description of the
issue, and steps to reproduce it if you have them.

You can expect an acknowledgement within a few days. If the report is confirmed,
a fix will be published and the advisory credited to you unless you would rather
stay anonymous.

## Scope

This package is a transport. It opens RFCOMM (Serial Port Profile) links and
moves bytes between your app and a peripheral. It does not encrypt payloads
itself.

Worth knowing when you assess risk in your own app:

- `secure: true` (the default) asks the platform for an authenticated and
  encrypted RFCOMM link. `secure: false` skips that and should only be used with
  devices that cannot pair.
- Link level protection comes from Bluetooth pairing. Anything sensitive in your
  protocol should be protected at the application layer as well.
- Discovery, pairing and connecting are gated by platform permissions. The
  plugin requests them where the platform allows, but your app declares them.

Issues in the peripheral's own firmware, or in the Bluetooth stack shipped by
the operating system, are outside what this package can fix. Report those to the
relevant vendor.
