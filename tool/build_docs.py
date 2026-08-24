# -*- coding: utf-8 -*-
import io, os, json, re, hashlib, glob, shutil

def emit_asset(src, name, ext):
    """Copy an asset under a content-hashed name and return its URL.

    The hash is the cache key: a changed file gets a new URL, so the long
    immutable cache in firebase.json can never serve a stale pair of HTML
    and CSS. Stale hashed copies from earlier builds are removed first.
    """
    data = io.open(src, 'rb').read()
    digest = hashlib.sha256(data).hexdigest()[:10]
    for old in glob.glob(os.path.join(OUT, name + '.*.' + ext)):
        os.remove(old)
    out = '%s.%s.%s' % (name, digest, ext)
    io.open(os.path.join(OUT, out), 'wb').write(data)
    return '/' + out


BASE    = "https://flutter-classic-bluetooth.web.app"
OUT     = "site"
VERSION = "0.1.10"
# IndexNow verification key. Must stay in step with the file emitted
# at the site root, or Bing and Yandex reject the submission.
INDEXNOW_KEY = "b41d7e6c92af08553ed1c47bb26f9a10"

# Sidebar groups. Structure mirrors how the task is approached, not file order.
GROUPS = [
    ("Start here", [
        ("index",                    "Introduction"),
        ("bluetooth-permissions",    "Permissions and setup"),
        ("scan-bluetooth-devices",   "Scan for devices"),
        ("connect-bluetooth-device", "Connect to a device"),
    ]),
    ("Moving data", [
        ("send-receive-data", "Send and receive"),
        ("rfcomm-server",     "Run a server"),
    ]),
    ("Talking to hardware", [
        ("esp32-bluetooth",           "ESP32"),
        ("hc-05-arduino",             "HC-05 and Arduino"),
        ("bluetooth-thermal-printer", "Thermal printers"),
    ]),
    ("Going further", [
        ("pair-devices",     "Pair and unpair"),
        ("desktop-bluetooth", "Windows, macOS, Linux"),
        ("troubleshooting",  "Troubleshooting"),
    ]),
]
NAV = [(s, t) for _, items in GROUPS for s, t in items]

ICON_GITHUB = ('<svg viewBox="0 0 16 16" aria-hidden="true" width="16" height="16" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>')

ICON_MENU = ('<svg viewBox="0 0 24 24" aria-hidden="true" width="20" height="20" fill="none" stroke="currentColor" '
             'stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>')
ICON_CLOSE = ('<svg viewBox="0 0 24 24" aria-hidden="true" width="20" height="20" fill="none" stroke="currentColor" '
              'stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>')

def slugify(text):
    t = re.sub(r"<[^>]+>", "", text)
    t = t.replace("&amp;", "and").replace("&lt;", "").replace("&gt;", "")
    t = re.sub(r"[^a-zA-Z0-9\s-]", "", t).strip().lower()
    return re.sub(r"[\s-]+", "-", t)

def add_heading_ids(body):
    """Give every h2 an id and collect them for the on-page contents list."""
    items = []
    def repl(m):
        text = m.group(1)
        sid = slugify(text)
        items.append((sid, re.sub(r"<[^>]+>", "", text)))
        return '<h2 id="%s">%s<a class="anchor" href="#%s" aria-label="Link to this section">#</a></h2>' % (sid, text, sid)
    return re.sub(r"<h2>(.*?)</h2>", repl, body, flags=re.S), items

def sidebar_html(slug):
    out = []
    for group, items in GROUPS:
        out.append('<h2>%s</h2><ul>' % group)
        for s, label in items:
            href = "/" if s == "index" else "/" + s
            cur = ' aria-current="page"' if s == slug else ""
            out.append('<li><a href="%s"%s>%s</a></li>' % (href, cur, label))
        out.append('</ul>')
    return "".join(out)


def toc_html(items):
    if len(items) < 2:
        return ""
    lis = "".join('<li><a href="#%s">%s</a></li>' % (sid, text) for sid, text in items)
    return ('<aside class="toc"><nav aria-labelledby="toc-h">'
            '<h2 id="toc-h">On this page</h2><ul>%s</ul></nav></aside>' % lis)


def page(slug, title, desc, h1, lede, body, faq=None):
    canonical = BASE + "/" + ("" if slug == "index" else slug)
    body, headings = add_heading_ids(body)

    # Wrap code blocks and tables so the copy button and overflow behave.
    body = body.replace("<pre><code>", '<div class="codeblock"><pre><code>')
    body = body.replace("</code></pre>", "</code></pre></div>")
    body = body.replace("<table>", '<div class="tablewrap"><table>')
    body = body.replace("</table>", "</table></div>")

    ld = {
        "@context": "https://schema.org",
        "@type": "TechArticle",
        "headline": h1,
        "description": desc,
        "url": canonical,
        "author": {"@type": "Person", "name": "Nurullah Al Masum"},
        "about": {"@type": "SoftwareSourceCode",
                  "name": "flutter_classic_bluetooth",
                  "programmingLanguage": "Dart",
                  "codeRepository": "https://github.com/almasumdev/flutter_classic_bluetooth"},
    }
    blocks = ['<script type="application/ld+json">%s</script>' % json.dumps(ld)]
    if faq:
        blocks.append('<script type="application/ld+json">%s</script>' % json.dumps({
            "@context": "https://schema.org", "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": q,
                            "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faq]
        }))

    return """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>%(title)s</title>
<meta name="description" content="%(desc)s">
<link rel="canonical" href="%(canonical)s">
<meta property="og:type" content="article">
<meta property="og:title" content="%(title)s">
<meta property="og:description" content="%(desc)s">
<meta property="og:url" content="%(canonical)s">
<meta name="twitter:card" content="summary">
<link rel="icon" href="/logo.svg" type="image/svg+xml">
<link rel="stylesheet" href="%(css)s">
%(ld)s
</head>
<body>
<a class="skip" href="#content">Skip to content</a>

<header class="topbar">
  <button class="menu" type="button" aria-label="Open navigation" aria-expanded="false" aria-controls="sidebar">%(menu)s</button>
  <a class="brand" href="/"><img src="/logo.svg" alt="" width="24" height="24">flutter_classic_bluetooth</a>
  <span class="ver">v%(version)s</span>
  <div class="grow"></div>
  <a class="ext" href="https://pub.dev/packages/flutter_classic_bluetooth"><span>pub.dev</span></a>
  <a class="ext" href="https://github.com/almasumdev/flutter_classic_bluetooth" aria-label="Source on GitHub">%(gh)s<span>GitHub</span></a>
</header>

<div class="scrim" aria-hidden="true"></div>

<div class="shell">
  <nav class="sidebar" id="sidebar" aria-label="Documentation">%(side)s</nav>

  <main class="content" id="content">
    <article>
      <h1>%(h1)s</h1>
      <p class="lede">%(lede)s</p>
      %(body)s
      <footer class="pagefoot">
        flutter_classic_bluetooth is open source under the MIT licence.
        <a href="https://pub.dev/packages/flutter_classic_bluetooth">pub.dev</a> &middot;
        <a href="https://github.com/almasumdev/flutter_classic_bluetooth">Source</a> &middot;
        <a href="https://pub.dev/documentation/flutter_classic_bluetooth/latest/">API reference</a>
      </footer>
    </article>
  </main>

  %(toc)s
</div>

<script src="%(js)s" defer></script>
</body>
</html>
""" % dict(title=title, desc=desc, canonical=canonical, ld="\n".join(blocks),
           menu=ICON_MENU, gh=ICON_GITHUB, version=VERSION,
           side=sidebar_html(slug), h1=h1, lede=lede, body=body,
           css=CSS_URL, js=JS_URL,
           toc=toc_html(headings))


INSTALL = """<h2>Install</h2>
<pre><code>flutter pub add flutter_classic_bluetooth</code></pre>
<pre><code>import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';</code></pre>"""


def nxt(pairs):
    return ('<nav class="next" aria-label="Related guides">'
            + "".join('<a href="/%s">%s</a>' % (s, t) for s, t in pairs)
            + "</nav>")


os.makedirs(OUT, exist_ok=True)
CSS_URL = emit_asset('tool/docs_assets/style.css', 'style', 'css')
JS_URL = emit_asset('tool/docs_assets/docs.js', 'docs', 'js')
print('  assets: %s  %s' % (CSS_URL, JS_URL))
def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def pre(code):
    return "<pre><code>%s</code></pre>" % esc(code.strip("\n"))

PAGES = []

# ---------------------------------------------------------------- index
PAGES.append(dict(
    slug="index",
    title="flutter_classic_bluetooth - Bluetooth Classic RFCOMM/SPP Plugin for Flutter",
    desc="Open source Flutter plugin for Bluetooth Classic serial communication over RFCOMM and SPP. Discover, pair and connect to ESP32, Arduino, HC-05 and thermal printers on Android, Windows, macOS, Linux and iOS.",
    h1="Bluetooth Classic for Flutter",
    lede="Discover, pair and exchange data with Bluetooth Classic devices over RFCOMM, the Serial Port Profile, from one Dart API.",
    body=INSTALL + """
<h2>Bluetooth Classic, not Bluetooth Low Energy</h2>
<p>This plugin speaks <strong>RFCOMM/SPP</strong>: the classic Bluetooth serial transport that ESP32 boards, HC-05 modules, barcode scanners, thermal printers and OBD-II adapters use. It is not a BLE plugin. If your device advertises GATT services and characteristics, you want a Bluetooth Low Energy package instead.</p>
<p>A connection is a plain byte stream. Reading and writing feels like any other Dart <code>Stream</code> and <code>Sink</code>.</p>

<h2>Connect and talk to a device</h2>
""" + pre("""
final bluetooth = FlutterClassicBluetooth();

final connection = await bluetooth.connect(
  address: 'AA:BB:CC:DD:EE:FF',
  uuid: BtcUuid.spp,
);

connection.input.listen((bytes) => print('RX ${bytes.length} bytes'));
await connection.output.writeString('AT');

await connection.finish();
""") + """
<h2>Find a device first</h2>
""" + pre("""
final devices = await bluetooth.scan(timeout: const Duration(seconds: 10));

for (final device in devices) {
  print('${device.displayName}  ${device.address}  ${device.rssi} dBm');
}
""") + """
<p><code>scan</code> collects discovery results, deduplicates them by address and sorts by signal strength. For a live list that fills in as devices appear, listen to <a href="/scan-bluetooth-devices">the discovery stream</a> instead.</p>

<h2>What it can do</h2>
<ul>
<li>Discover nearby devices and list the ones already paired.</li>
<li>Connect over RFCOMM by MAC address and service UUID, then read and write bytes.</li>
<li>Run an RFCOMM <a href="/rfcomm-server">server</a> that accepts incoming connections.</li>
<li>Pair and unpair, toggle the adapter, and make the device discoverable, where the platform allows it.</li>
<li>Reconnect automatically with a backoff policy when a link drops.</li>
<li>Ask at runtime which of those the current platform actually supports.</li>
</ul>

<h2>Where it runs</h2>
<div class="tablewrap"><table>
<thead><tr><th>Platform</th><th>Backend</th><th>Notes</th></tr></thead>
<tbody>
<tr><td>Android</td><td><code>BluetoothSocket</code></td><td>Everything, including server mode</td></tr>
<tr><td>Windows</td><td>Winsock2 <code>AF_BTH</code></td><td>No unpair</td></tr>
<tr><td>macOS</td><td>IOBluetooth</td><td>Unpair via System Settings only</td></tr>
<tr><td>Linux</td><td>BlueZ RFCOMM</td><td>Pairing needs a system agent</td></tr>
<tr><td>iOS</td><td>ExternalAccessory</td><td>MFi accessories only, no discovery</td></tr>
</tbody></table></div>
<p>Rather than guessing, ask:</p>
""" + pre("""
final caps = await bluetooth.getPlatformCapabilities();

if (caps.canDiscoverDevices) {
  // show the scan button
}
""") + """
<p>See <a href="/desktop-bluetooth">the desktop guide</a> for what differs on Windows, macOS and Linux.</p>

<h2>Start here</h2>
<p>Set up <a href="/bluetooth-permissions">permissions</a> first, since nothing works without them on Android. Then <a href="/scan-bluetooth-devices">scan</a>, <a href="/connect-bluetooth-device">connect</a>, and <a href="/send-receive-data">move some bytes</a>. If you are wiring up a specific board, jump straight to <a href="/esp32-bluetooth">ESP32</a>, <a href="/hc-05-arduino">HC-05</a>, or a <a href="/bluetooth-thermal-printer">thermal printer</a>.</p>
""" + nxt([("bluetooth-permissions", "Permissions"), ("connect-bluetooth-device", "Connect")]),
    faq=[("Does flutter_classic_bluetooth support Bluetooth Low Energy?",
          "No. It implements Bluetooth Classic RFCOMM and the Serial Port Profile. BLE devices use GATT and need a Bluetooth Low Energy package instead."),
         ("Which platforms support Bluetooth Classic in Flutter?",
          "Android, Windows, macOS and Linux support discovery and RFCOMM fully. iOS only reaches MFi certified accessories through the ExternalAccessory framework and cannot discover devices."),
         ("Can I connect to an ESP32 or HC-05 from Flutter?",
          "Yes. Both expose a standard SPP serial port, so you connect by MAC address using the SPP UUID and read and write bytes.")],
))
print("defined index")

# ---------------------------------------------------------------- permissions
PAGES.append(dict(
    slug="bluetooth-permissions",
    title="Bluetooth Permissions Setup in Flutter (Android, iOS, macOS, Linux)",
    desc="The manifest entries, plist keys, entitlements and Linux packages a Flutter app needs before it can scan for or connect to a Bluetooth Classic device.",
    h1="Permissions and setup",
    lede="Bluetooth fails silently without the right declarations. Do this before anything else.",
    body=INSTALL + """
<h2>Android</h2>
<p>Android split its Bluetooth permissions at API 31, so a manifest that covers both old and new devices needs both sets. Add these to <code>android/app/src/main/AndroidManifest.xml</code>, inside <code>&lt;manifest&gt;</code> and above <code>&lt;application&gt;</code>.</p>
""" + pre("""
<!-- Android 11 (API 30) and below -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />

<!-- Android 12 (API 31) and above -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
""") + """
<p>Two things trip people up here. On Android 11 and below, <strong>scanning requires location permission</strong>, because a nearby-device list can be used to infer where someone is. And on Android 12 and above, <code>BLUETOOTH_SCAN</code> and <code>BLUETOOTH_CONNECT</code> are runtime permissions, so declaring them is not enough. The plugin prompts for them when you call a method that needs one.</p>
<p><code>neverForLocation</code> tells Android you are not using scan results to derive location, which keeps the permission prompt narrower. Drop that flag if you genuinely do.</p>

<h2>iOS</h2>
<p>iOS only reaches <strong>MFi certified accessories</strong>, and only ones whose protocol string you declare up front. Add to <code>ios/Runner/Info.plist</code>:</p>
""" + pre("""
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.example.spp</string>
</array>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app communicates with Bluetooth accessories.</string>
""") + """
<p>Replace <code>com.example.spp</code> with the protocol string your accessory vendor gave you. An accessory whose string is not listed is invisible to your app, and there is no way around that from Dart. A generic HC-05 or ESP32 will not work on iOS at all, because neither is MFi certified.</p>

<h2>macOS</h2>
<p>Add the entitlement to both <code>macos/Runner/DebugProfile.entitlements</code> and <code>Release.entitlements</code>:</p>
""" + pre("""
<key>com.apple.security.device.bluetooth</key>
<true/>
""") + """
<p>Sandboxed builds silently see no devices without it.</p>

<h2>Linux</h2>
<p>The native plugin compiles against GTK and BlueZ. Missing headers show up as a CMake error mentioning <code>gtk+-3.0</code> or <code>bluetooth/bluetooth.h</code>, not as a runtime failure.</p>
""" + pre("""
sudo apt-get install -y libgtk-3-dev libbluetooth-dev ninja-build cmake pkg-config clang
""") + """
<p>On Fedora: <code>gtk3-devel bluez-libs-devel ninja-build cmake clang</code>. On Arch: <code>gtk3 bluez-libs ninja cmake clang</code>.</p>

<h2>Windows</h2>
<p>Nothing to declare. The plugin uses Winsock2 <code>AF_BTH</code> sockets, which need no manifest entry or capability.</p>

<h2>Check before you call</h2>
<p>Once setup is done, confirm the adapter is actually usable rather than assuming it.</p>
""" + pre("""
final bluetooth = FlutterClassicBluetooth();

if (!await bluetooth.isSupported()) {
  // No Bluetooth Classic radio, or an unsupported platform.
  return;
}

if (!await bluetooth.isEnabled()) {
  final caps = await bluetooth.getPlatformCapabilities();
  if (caps.canEnableBluetooth) {
    await bluetooth.enableBluetooth();   // Android and Linux
  } else {
    // Ask the user to turn it on in system settings.
  }
}
""") + nxt([("scan-bluetooth-devices", "Scan for devices"), ("troubleshooting", "Troubleshooting")]),
    faq=[("Why does Bluetooth scanning need location permission on Android?",
          "On Android 11 and below the list of nearby Bluetooth devices can reveal where a user is, so the system gates scanning behind ACCESS_FINE_LOCATION. Android 12 replaced it with BLUETOOTH_SCAN, which you can declare with neverForLocation."),
         ("Why can my Flutter app not see a Bluetooth device on iOS?",
          "iOS only exposes MFi certified accessories, and only those whose protocol string is listed in UISupportedExternalAccessoryProtocols. Generic modules such as HC-05 and ESP32 are not reachable on iOS."),
         ("Do I need a permission package to request Bluetooth permissions?",
          "No. The plugin requests the Android runtime permissions it needs when you call a method that requires one.")],
))
print("defined permissions")

# ---------------------------------------------------------------- scan
PAGES.append(dict(
    slug="scan-bluetooth-devices",
    title="How to Scan for Bluetooth Devices in Flutter",
    desc="Discover nearby Bluetooth Classic devices from Flutter, list already paired devices, and build a live scan list that fills in as devices are found.",
    h1="Scan for devices",
    lede="Two ways to find a device: collect a scan, or watch results arrive one at a time.",
    body=INSTALL + """
<h2>The simple way</h2>
<p><code>scan</code> runs discovery for a fixed window and hands back a finished list, deduplicated by address and sorted strongest signal first.</p>
""" + pre("""
final bluetooth = FlutterClassicBluetooth();

final devices = await bluetooth.scan(timeout: const Duration(seconds: 10));

for (final device in devices) {
  print('${device.displayName}  ${device.address}  ${device.rssi} dBm');
}
""") + """
<p>Discovery is stopped for you when the window closes, including if something throws partway through.</p>

<h2>A live list</h2>
<p>Ten seconds of a blank screen is a poor experience. Listen to <code>discoveryResults</code> and show each device the moment it appears.</p>
""" + pre("""
final found = <String, BtcDevice>{};

final sub = bluetooth.discoveryResults.listen((device) {
  setState(() => found[device.address] = device);
});

await bluetooth.startDiscovery();
// ... later
await bluetooth.stopDiscovery();
await sub.cancel();
""") + """
<p>Key the map by <code>address</code>. The same device is reported several times during a scan, once per inquiry response, and each report may carry a different RSSI or fill in a name the first one lacked.</p>

<h2>Knowing when it stops</h2>
<p>Discovery ends on its own after the platform's inquiry window, whether or not you call <code>stopDiscovery</code>. <code>discoveryState</code> tells you when that happens so a spinner can stop spinning.</p>
""" + pre("""
bluetooth.discoveryState.listen((scanning) {
  setState(() => isScanning = scanning);
});
""") + """
<h2>Devices you already know</h2>
<p>Most of the time the device is already paired, and a scan is wasted effort. Paired devices are available instantly, with no permission prompt on most platforms and no radio activity.</p>
""" + pre("""
final paired = await bluetooth.getPairedDevices();

final printer = paired.firstWhere(
  (d) => d.name?.contains('Printer') ?? false,
);
""") + """
<p>A good device picker shows paired devices first and offers a scan for anything new.</p>

<h2>What a result carries</h2>
<div class="tablewrap"><table>
<thead><tr><th>Field</th><th>Meaning</th></tr></thead>
<tbody>
<tr><td><code>address</code></td><td>MAC address, the stable identifier</td></tr>
<tr><td><code>name</code></td><td>Advertised name, often null on the first report</td></tr>
<tr><td><code>alias</code></td><td>User-assigned name, where the platform has one</td></tr>
<tr><td><code>displayName</code></td><td><code>alias</code>, else <code>name</code>, else the address</td></tr>
<tr><td><code>rssi</code></td><td>Signal strength in dBm, closer to zero is stronger</td></tr>
<tr><td><code>type</code></td><td>Classic, LE, or dual mode</td></tr>
<tr><td><code>bondState</code></td><td>Whether it is already paired</td></tr>
<tr><td><code>uuids</code></td><td>Advertised service UUIDs, when the platform reports them</td></tr>
</tbody></table></div>
<p>Use <code>displayName</code> in your UI. A device that has not reported a name yet would otherwise render as an empty row.</p>

<h2>Filtering to serial devices</h2>
<p>A scan picks up headphones, keyboards and watches along with the board you care about. Where <code>uuids</code> is populated you can narrow the list to devices offering a serial port.</p>
""" + pre("""
final serial = devices.where(
  (d) => d.uuids.any((u) => u.toUpperCase() == BtcUuid.spp),
);
""") + """
<p>Do not rely on this alone. Several platforms report an empty <code>uuids</code> list during discovery and only fill it in after pairing, so treat a match as a hint and keep the full list reachable.</p>

<h2>Not available on iOS</h2>
<p>iOS has no discovery API for Bluetooth Classic. <code>startDiscovery</code> and <code>scan</code> throw <code>BtcUnsupportedException</code> there, and <code>getPairedDevices</code> returns the MFi accessories your app declared. Check first:</p>
""" + pre("""
final caps = await bluetooth.getPlatformCapabilities();
if (!caps.canDiscoverDevices) {
  // Offer the paired list instead of a scan button.
}
""") + nxt([("connect-bluetooth-device", "Connect to a device"), ("pair-devices", "Pair and unpair")]),
    faq=[("How do I scan for Bluetooth devices in Flutter?",
          "Call scan for a finished list after a fixed window, or listen to discoveryResults and call startDiscovery for a live list that fills in as devices are found."),
         ("Why does the same Bluetooth device appear several times while scanning?",
          "Each inquiry response is reported separately, and later reports often add a name or a fresher RSSI. Deduplicate by the address field."),
         ("Why is the Bluetooth device name null?",
          "The first discovery report often carries only an address. Use displayName, which falls back to the address, and update the entry as later reports arrive.")],
))
print("defined scan")

# ---------------------------------------------------------------- connect
PAGES.append(dict(
    slug="connect-bluetooth-device",
    title="How to Connect to a Bluetooth Classic Device in Flutter",
    desc="Open an RFCOMM connection to a Bluetooth Classic device from Flutter by MAC address and service UUID, handle timeouts, and reconnect automatically when the link drops.",
    h1="Connect to a device",
    lede="A connection needs two things: a MAC address and a service UUID.",
    body=INSTALL + """
<h2>Opening a connection</h2>
""" + pre("""
final bluetooth = FlutterClassicBluetooth();

final connection = await bluetooth.connect(
  address: 'AA:BB:CC:DD:EE:FF',
  uuid: BtcUuid.spp,
);

print(connection.isConnected);   // true
""") + """
<p><code>BtcUuid.spp</code> is <code>00001101-0000-1000-8000-00805F9B34FB</code>, the Serial Port Profile, and it is the default. Nearly every serial device uses it: ESP32, HC-05, Arduino modules, most thermal printers. Pass a different UUID only if the vendor documents one.</p>
<p>An invalid address throws <code>BtcAddressException</code> and a malformed UUID throws <code>BtcUuidException</code>, both before any radio work happens.</p>

<h2>Always set a timeout</h2>
<p>Without one, a connect to a device that is off or out of range can hang for a long time, and how long is up to the platform.</p>
""" + pre("""
try {
  final connection = await bluetooth.connect(
    address: device.address,
    timeout: const Duration(seconds: 8),
  );
} on BtcTimeoutException {
  // Device is off, out of range, or already connected to something else.
} on BtcConnectionException catch (e) {
  // Refused, or the service UUID is not offered.
  print(e.message);
}
""") + """
<p>A native connect cannot be cancelled once it starts. If the attempt succeeds after your deadline has passed, the plugin closes and releases that connection for you, so a late arrival does not leak an open socket and two event channels for the life of the app.</p>

<h2>Secure and insecure</h2>
<p><code>secure</code> defaults to <code>true</code>, which means an authenticated and encrypted RFCOMM channel and a device that must be paired first. Some older modules only accept an insecure channel.</p>
""" + pre("""
final connection = await bluetooth.connect(
  address: device.address,
  secure: false,
);
""") + """
<p>Try secure first. Fall back to insecure only when a device refuses, and be aware the link is then unencrypted.</p>

<h2>Watching the link</h2>
""" + pre("""
connection.stateStream.listen((state) {
  switch (state) {
    case BtcConnectionState.connected:
      // ready
    case BtcConnectionState.disconnected:
      // the device went away
    default:
      break;
  }
});
""") + """
<h2>Closing properly</h2>
<p>There are two ways to end a connection, and the difference matters.</p>
""" + pre("""
await connection.finish();   // flush pending writes, then close
await connection.close();    // close now, drop anything queued
""") + """
<p>Use <code>finish</code> in almost every case. <code>close</code> is for teardown when you no longer care whether the last bytes arrived, such as in <code>dispose</code> after an error.</p>

<h2>Reconnecting on its own</h2>
<p>A serial link over the air drops. If your app should survive that without the user doing anything, use a reconnecting connection instead of managing retries yourself.</p>
""" + pre("""
final link = bluetooth.connectWithReconnect(
  address: 'AA:BB:CC:DD:EE:FF',
  policy: const BtcReconnectPolicy(
    initialBackoff: Duration(seconds: 1),
    maxBackoff: Duration(seconds: 30),
    backoffMultiplier: 2.0,
    connectTimeout: Duration(seconds: 8),
  ),
);

link.input.listen((bytes) => handle(bytes));
link.state.listen((s) => print('link: $s'));

await link.sendLine('PING');
await link.close();
""") + """
<p>The input stream survives a drop, so a listener set up once keeps receiving after the link comes back. Backoff grows from <code>initialBackoff</code> by <code>backoffMultiplier</code> up to <code>maxBackoff</code>, which keeps a device that is simply switched off from being hammered.</p>

<h2>Several devices at once</h2>
<p>Where the platform allows it, connections are independent and you can hold more than one.</p>
""" + pre("""
final caps = await bluetooth.getPlatformCapabilities();
if (caps.supportsMultipleConnections) {
  final scanner = await bluetooth.connect(address: scannerMac);
  final printer = await bluetooth.connect(address: printerMac);
}
""") + nxt([("send-receive-data", "Send and receive"), ("troubleshooting", "Troubleshooting")]),
    faq=[("What UUID do I use to connect to a Bluetooth serial device?",
          "The Serial Port Profile UUID, 00001101-0000-1000-8000-00805F9B34FB, available as BtcUuid.spp and used by default. Almost every serial device including ESP32, HC-05 and most thermal printers uses it."),
         ("Why does connecting to a Bluetooth device hang in Flutter?",
          "A native connect to a device that is off or out of range can block for a long time. Pass a timeout to connect so it fails with BtcTimeoutException instead."),
         ("How do I reconnect automatically when a Bluetooth connection drops?",
          "Use connectWithReconnect with a BtcReconnectPolicy. It retries with exponential backoff and keeps one input stream alive across drops.")],
))
print("defined connect")

# ---------------------------------------------------------------- data
PAGES.append(dict(
    slug="send-receive-data",
    title="Send and Receive Data over Bluetooth Serial in Flutter",
    desc="Read and write bytes on a Bluetooth Classic RFCOMM connection in Flutter, split the input stream into lines or framed packets, and send a command and await its reply.",
    h1="Send and receive",
    lede="A connection is a byte stream in and an ordered sink out. The work is turning bytes into messages.",
    body=INSTALL + """
<h2>Writing</h2>
""" + pre("""
await connection.output.writeString('AT');
await connection.output.writeLine('AT+GMR');
await connection.output.writeBytes([0x01, 0x02, 0x03]);
await connection.output.add(Uint8List.fromList([0xFF]));
""") + """
<p>Writes are queued and delivered in call order, so you do not have to await each one to keep them in sequence. When you do need to know everything has gone out:</p>
""" + pre("""
connection.output.writeString('one');
connection.output.writeString('two');
await connection.output.allSent;
""") + """
<h2>Reading raw bytes</h2>
""" + pre("""
connection.input.listen(
  (bytes) => print('RX ${bytes.length}'),
  onDone: () => print('device disconnected'),
  onError: (e) => print('link error: $e'),
);
""") + """
<p><code>onDone</code> firing is how you learn the other end went away.</p>

<h2>Bytes are not messages</h2>
<p>This is the mistake that costs the most time. RFCOMM is a stream, not a datagram service. One <code>write</code> on the device does not produce one event in Dart. A 40 byte reply can arrive as 40 separate events, or two writes can arrive merged into one. Any code shaped like <code>if (utf8.decode(bytes) == 'OK')</code> works on your desk and fails in the field.</p>
<p>Split the stream on whatever the protocol actually delimits with.</p>

<h2>Line based protocols</h2>
""" + pre("""
connection.input.lines().listen((line) {
  print('device said: $line');
});
""") + r"""
<p><code>lines</code> buffers across events and emits one string per line, handling both <code>\n</code> and <code>\r\n</code>. Pass <code>maxLineLength</code> to cap the buffer so a device stuck without a delimiter cannot grow it without bound.</p>
""" + pre("""
connection.input.lines(maxLineLength: 4096).listen(handleLine);
""") + """
<h2>Binary frames</h2>
<p>For a protocol delimited by a byte sequence rather than a newline:</p>
""" + pre("""
connection.input
    .frames(delimiter: Uint8List.fromList([0x0D, 0x0A]))
    .listen((frame) => decode(frame));
""") + """
<h2>Command and response</h2>
<p>Write a command, wait for the reply, in one call. This is the common shape for AT command devices.</p>
""" + pre("""
final version = await connection.sendAndReceive('AT+GMR');

final ok = await connection.sendAndReceive(
  'AT',
  where: (line) => line == 'OK',
  timeout: const Duration(seconds: 3),
);
""") + """
<p>It subscribes before writing, so a device that answers immediately is never missed. <code>where</code> skips lines you do not care about, which matters on devices that echo the command back before replying. No matching line inside the timeout throws <code>BtcTimeoutException</code>.</p>
<p>One caveat: this is a single outstanding request at a time. Do not fire several in parallel on one connection and expect the answers to pair up.</p>

<h2>Text encodings</h2>
<p>Everything defaults to UTF-8. Devices that speak Latin-1 or a code page need it stated.</p>
""" + pre("""
await connection.output.writeString('café', encoding: latin1);
connection.input.lines(encoding: latin1).listen(handleLine);
""") + """
<h2>Decoding without splitting</h2>
<p>When a device streams text with no framing at all and you just want it on screen:</p>
""" + pre("""
connection.input.decoded().listen((chunk) => append(chunk));
""") + """
<p>Chunk boundaries do not fall on character boundaries, so this decodes across events rather than per event, which keeps multi-byte characters intact.</p>
""" + nxt([("connect-bluetooth-device", "Connect"), ("esp32-bluetooth", "ESP32")]),
    faq=[("Why does my Bluetooth data arrive split into pieces in Flutter?",
          "RFCOMM is a byte stream, not a message service. One write on the device can arrive as several stream events, or several writes can arrive merged. Split the input with lines or frames rather than treating each event as a message."),
         ("How do I read line by line from a Bluetooth serial device?",
          "Call lines on the connection input stream. It buffers across events and emits one string per line, handling both LF and CRLF."),
         ("How do I send an AT command and wait for the response?",
          "Use sendAndReceive. It subscribes before writing so a fast reply is not missed, and takes an optional where predicate to skip echoed lines.")],
))
print("defined data")

# ---------------------------------------------------------------- server
PAGES.append(dict(
    slug="rfcomm-server",
    title="How to Run an RFCOMM Bluetooth Server in Flutter",
    desc="Advertise an SDP service from a Flutter app and accept incoming Bluetooth Classic RFCOMM connections, so a phone or desktop can act as the serial device other machines connect to.",
    h1="Run a server",
    lede="Advertise a service, accept incoming connections, and let other devices connect to you.",
    body=INSTALL + """
<h2>Listening</h2>
""" + pre("""
final server = await bluetooth.startServer(
  serviceName: 'My App Serial',
  uuid: BtcUuid.spp,
);

server.connections.listen((connection) {
  print('client connected');
  connection.input.lines().listen((line) => print('client said: $line'));
});
""") + """
<p><code>serviceName</code> is what appears in the other device's SDP browse, so make it recognisable. Each incoming client arrives as a full <code>BtcConnection</code>, the same type <code>connect</code> returns, so everything on the <a href="/send-receive-data">send and receive</a> page applies unchanged.</p>

<h2>Be discoverable</h2>
<p>Listening is not enough on its own. A client that has never paired with you cannot find you unless the adapter is discoverable.</p>
""" + pre("""
final caps = await bluetooth.getPlatformCapabilities();
if (caps.canSetDiscoverable) {
  await bluetooth.setDiscoverable(300);   // seconds
}
""") + """
<p>On Android this shows a system dialog the user has to accept. Windows and Linux apply it directly, macOS and iOS have no API for it. Already paired clients can connect without this.</p>

<h2>Your own service UUID</h2>
<p>Use SPP when you want generic serial terminals to be able to connect. Use a UUID of your own when the two ends are both your software and you would rather not have unrelated apps attach.</p>
""" + pre("""
final server = await bluetooth.startServer(
  serviceName: 'Fleet Sync',
  uuid: '7f2c9e40-1b3a-4d6e-9f10-2c8b5a7d3e91',
);
""") + """
<p>Both ends must agree. The client passes the same string to <code>connect</code>.</p>

<h2>Several clients</h2>
<p>The connections stream keeps emitting, so a server can hold more than one client where the platform supports it. Track them yourself, since closing the server socket does not close connections it already handed you.</p>
""" + pre("""
final clients = <BtcConnection>[];

server.connections.listen((connection) {
  clients.add(connection);
  connection.stateStream.listen((s) {
    if (s == BtcConnectionState.disconnected) clients.remove(connection);
  });
});

Future<void> broadcast(String line) async {
  for (final c in clients) {
    await c.output.writeLine(line);
  }
}
""") + """
<h2>Shutting down</h2>
""" + pre("""
for (final c in clients) {
  await c.finish();
}
await server.close();
""") + """
<p>Close the connections first, then the listening socket. The other order leaves clients hanging until they notice the link went quiet.</p>

<h2>Where it works</h2>
<div class="tablewrap"><table>
<thead><tr><th>Platform</th><th>Server mode</th></tr></thead>
<tbody>
<tr><td>Android</td><td>Yes</td></tr>
<tr><td>Windows</td><td>Yes</td></tr>
<tr><td>macOS</td><td>Yes</td></tr>
<tr><td>Linux</td><td>Yes</td></tr>
<tr><td>iOS</td><td>No</td></tr>
</tbody></table></div>
<p>iOS cannot act as an RFCOMM server. <code>startServer</code> throws <code>BtcUnsupportedException</code>, so gate the feature on <code>caps.canCreateServer</code> rather than on the platform name.</p>
""" + nxt([("send-receive-data", "Send and receive"), ("desktop-bluetooth", "Desktop platforms")]),
    faq=[("Can a Flutter app act as a Bluetooth server?",
          "Yes on Android, Windows, macOS and Linux. Call startServer with a service name and UUID, then listen to the connections stream. iOS cannot act as an RFCOMM server."),
         ("Why can no one find my Bluetooth server?",
          "Listening does not make the adapter discoverable. Call setDiscoverable so clients that have never paired with you can find the service. Already paired clients can connect without it."),
         ("Can an RFCOMM server accept more than one client?",
          "Yes where the platform supports multiple connections. The connections stream keeps emitting, and each client is an independent connection you close yourself.")],
))
print("defined server")

# ---------------------------------------------------------------- esp32
PAGES.append(dict(
    slug="esp32-bluetooth",
    title="Connect Flutter to an ESP32 over Bluetooth Classic",
    desc="Pair a Flutter app with an ESP32 using Bluetooth Classic SPP, send commands from Dart to the BluetoothSerial sketch, and read the replies back as lines.",
    h1="ESP32",
    lede="An ESP32 running BluetoothSerial is a plain SPP device, so nothing special is needed on the Flutter side.",
    body=INSTALL + """
<h2>The sketch</h2>
<p>On the board, <code>BluetoothSerial</code> from the Arduino ESP32 core exposes a standard serial port. The name you pass to <code>begin</code> is what shows up in a scan.</p>
""" + pre(r"""
#include "BluetoothSerial.h"

BluetoothSerial SerialBT;

void setup() {
  SerialBT.begin("ESP32-Device");
}

void loop() {
  if (SerialBT.available()) {
    String line = SerialBT.readStringUntil('\n');
    SerialBT.println("echo: " + line);
  }
}
""") + """
<p>This needs a classic ESP32 or ESP32-S3. The <strong>ESP32-C3, C6 and S2 have no Bluetooth Classic radio</strong>, only BLE, so <code>BluetoothSerial</code> will not compile for them and no amount of Flutter code will reach them.</p>

<h2>Finding it</h2>
""" + pre("""
final bluetooth = FlutterClassicBluetooth();

final devices = await bluetooth.scan(timeout: const Duration(seconds: 10));
final esp = devices.firstWhere((d) => d.name == 'ESP32-Device');
""") + """
<p>After the first pairing, skip the scan entirely and read it from <code>getPairedDevices</code>, which is instant.</p>

<h2>Connecting and talking</h2>
""" + pre("""
final connection = await bluetooth.connect(
  address: esp.address,
  timeout: const Duration(seconds: 8),
);

connection.input.lines().listen((line) {
  print('ESP32: $line');
});

await connection.output.writeLine('hello');
""") + """
<p><code>writeLine</code> appends the newline the sketch's <code>readStringUntil</code> is waiting for. Without a delimiter the board sits there holding a partial line, which looks exactly like a connection that is not working.</p>

<h2>Command and reply</h2>
<p>When the board answers each command, <code>sendAndReceive</code> is less code than wiring up a listener and a completer.</p>
""" + pre("""
final reply = await connection.sendAndReceive('status');
print(reply);   // echo: status
""") + """
<h2>Streaming sensor data</h2>
<p>A board that pushes readings continuously is the other common shape. Parse each line as it lands.</p>
""" + pre("""
connection.input.lines().listen((line) {
  final parts = line.split(',');
  if (parts.length != 2) return;          // ignore boot noise
  final temp = double.tryParse(parts[0]);
  final humidity = double.tryParse(parts[1]);
  if (temp != null && humidity != null) {
    setState(() => reading = (temp, humidity));
  }
});
""") + """
<p>Guard the parse. An ESP32 prints boot messages over the same port before your sketch takes over, and those will reach you as lines.</p>

<h2>Surviving a reset</h2>
<p>Boards get power cycled and reflashed constantly during development. A reconnecting link saves restarting the app every time.</p>
""" + pre("""
final link = bluetooth.connectWithReconnect(
  address: esp.address,
  policy: const BtcReconnectPolicy(
    initialBackoff: Duration(seconds: 1),
    maxBackoff: Duration(seconds: 15),
  ),
);

link.input.lines().listen((line) => print('ESP32: $line'));
await link.sendLine('hello');
""") + """
<h2>Common problems</h2>
<div class="tablewrap"><table>
<thead><tr><th>Symptom</th><th>Usually</th></tr></thead>
<tbody>
<tr><td>Board never appears in a scan</td><td>An ESP32-C3, C6 or S2, which has no Bluetooth Classic radio</td></tr>
<tr><td>Connects, then drops immediately</td><td>Brownout. USB power is often not enough while the radio transmits</td></tr>
<tr><td>Nothing arrives in Dart</td><td>The sketch is not sending a delimiter, so <code>lines</code> never completes one</td></tr>
<tr><td>First lines are garbage</td><td>Boot log on the same port. Skip lines that do not parse</td></tr>
<tr><td>Connect fails after reflashing</td><td>The old bond is stale. Unpair and pair again</td></tr>
</tbody></table></div>
""" + nxt([("send-receive-data", "Send and receive"), ("hc-05-arduino", "HC-05 and Arduino")]),
    faq=[("How do I connect a Flutter app to an ESP32 over Bluetooth?",
          "Run BluetoothSerial on the board, find it by name with scan or getPairedDevices, then call connect with its address. The ESP32 exposes a standard SPP port, so the default UUID works."),
         ("Why can my Flutter app not find my ESP32 over Bluetooth Classic?",
          "The ESP32-C3, C6 and S2 have no Bluetooth Classic radio, only BLE, so they cannot run BluetoothSerial. Use a classic ESP32 or an ESP32-S3."),
         ("Why does my ESP32 receive nothing from Flutter?",
          "readStringUntil waits for a delimiter. Use writeLine rather than writeString so the newline the sketch expects is actually sent.")],
))
print("defined esp32")

# ---------------------------------------------------------------- hc05
PAGES.append(dict(
    slug="hc-05-arduino",
    title="Connect Flutter to HC-05 and Arduino over Bluetooth",
    desc="Talk to an HC-05 or HC-06 Bluetooth module wired to an Arduino from a Flutter app, send AT commands, and handle the pairing and baud rate problems these modules are known for.",
    h1="HC-05 and Arduino",
    lede="The cheapest way to put an Arduino on Bluetooth, and the one with the most sharp edges.",
    body=INSTALL + """
<h2>Connecting</h2>
<p>An HC-05 in its normal mode is a transparent serial bridge. Bytes you write arrive on the Arduino's RX pin and bytes the Arduino writes come back.</p>
""" + pre("""
final paired = await bluetooth.getPairedDevices();
final hc05 = paired.firstWhere((d) => d.name == 'HC-05');

final connection = await bluetooth.connect(
  address: hc05.address,
  timeout: const Duration(seconds: 8),
);

connection.input.lines().listen((line) => print('Arduino: $line'));
await connection.output.writeLine('LED ON');
""") + """
<p>Pair it in system settings first. The default PIN is <code>1234</code> or <code>0000</code>. These modules do not always pair cleanly from inside an app, and doing it once in settings removes a whole class of confusing failures.</p>

<h2>The sketch</h2>
""" + pre("""
#include <SoftwareSerial.h>

SoftwareSerial bt(10, 11);   // RX, TX

void setup() {
  bt.begin(9600);
}

void loop() {
  if (bt.available()) {
    String cmd = bt.readStringUntil(10);
    if (cmd.startsWith("LED ON")) digitalWrite(13, HIGH);
    bt.println("ok");
  }
}
""") + """
<p>Wire the module's TX to the Arduino's RX and its RX to the Arduino's TX. The HC-05 RX pin is <strong>3.3V</strong>, so it needs a divider from a 5V board. Skipping that is the most common reason a module works for a while and then stops.</p>

<h2>Baud rate</h2>
<p>The module's Bluetooth side and its serial side are configured separately. <code>bt.begin(9600)</code> has to match the module's UART baud, which is 9600 by default but is often changed to 38400 or 115200 and then forgotten.</p>
<p>A mismatch does not fail cleanly. You get a connection, you can write, and what comes back is garbage bytes. If <code>lines</code> is emitting nonsense, suspect the baud rate before anything in Dart.</p>

<h2>AT command mode</h2>
<p>Held in AT mode, an HC-05 answers configuration commands over the same link.</p>
""" + pre("""
final name = await connection.sendAndReceive('AT+NAME?');
final version = await connection.sendAndReceive('AT+VERSION?');

final ok = await connection.sendAndReceive(
  'AT+UART=9600,0,0',
  where: (line) => line == 'OK',
);
""") + r"""
<p>HC-05 firmware expects <code>\r\n</code>, which is what <code>sendAndReceive</code> sends by default. Some clones want a bare <code>\n</code>:</p>
""" + pre(r"""
await connection.sendAndReceive('AT', newline: '\n');
""") + r"""
<p>Entering AT mode is a hardware step: hold the module's KEY or EN pin high while powering it up. There is no way to trigger it from Dart.</p>

<h2>HC-06</h2>
<p>An HC-06 is slave only. It cannot initiate a connection, which is fine here since your app is always the one connecting. Its AT dialect is different: no <code>\r\n</code> terminator, and no <code>?</code> query form. Everything else on this page applies.</p>

<h2>Common problems</h2>
<div class="tablewrap"><table>
<thead><tr><th>Symptom</th><th>Usually</th></tr></thead>
<tbody>
<tr><td>Received text is garbage</td><td>Baud mismatch between the sketch and the module</td></tr>
<tr><td>Connects, then drops after a second</td><td>Powered from a pin that cannot supply the peak current</td></tr>
<tr><td>Module stops responding after weeks</td><td>5V on the 3.3V RX pin. Use a divider</td></tr>
<tr><td>Arduino receives nothing</td><td>TX and RX not crossed, or writeString used with no delimiter</td></tr>
<tr><td>AT commands return nothing</td><td>Not in AT mode. The KEY pin must be high at power up</td></tr>
<tr><td>Pairing fails from the app</td><td>Pair once in system settings with PIN 1234 or 0000</td></tr>
</tbody></table></div>
""" + nxt([("esp32-bluetooth", "ESP32"), ("troubleshooting", "Troubleshooting")]),
    faq=[("How do I connect Flutter to an HC-05 Bluetooth module?",
          "Pair the module in system settings first, using PIN 1234 or 0000, then find it in getPairedDevices and call connect with its address. It presents a standard SPP port."),
         ("Why is the data from my HC-05 garbled in Flutter?",
          "Almost always a baud rate mismatch between the Arduino sketch and the module's UART setting. The link still connects, so the only symptom is nonsense bytes."),
         ("Can I send AT commands to an HC-05 from Flutter?",
          "Yes, once the module is in AT mode, which requires holding the KEY pin high at power up. Use sendAndReceive, which sends CRLF by default.")],
))
print("defined hc05")

# ---------------------------------------------------------------- printer
PAGES.append(dict(
    slug="bluetooth-thermal-printer",
    title="Print to a Bluetooth Thermal Printer from Flutter",
    desc="Send ESC/POS receipts to a Bluetooth Classic thermal printer from a Flutter app, including text, alignment, cutting and the flushing problem that truncates the last line.",
    h1="Thermal printers",
    lede="A receipt printer is an SPP device that happens to interpret ESC/POS bytes.",
    body=INSTALL + """
<h2>Finding the printer</h2>
<p>Receipt printers are nearly always paired once and then used forever, so read the paired list rather than scanning.</p>
""" + pre("""
final paired = await bluetooth.getPairedDevices();
final printer = paired.firstWhere(
  (d) => (d.name ?? '').contains('Printer'),
);

final connection = await bluetooth.connect(address: printer.address);
""") + """
<p>Names vary wildly between vendors: <code>Printer001</code>, <code>BlueTooth Printer</code>, <code>MTP-2</code>, <code>RPP02N</code>. Let the user pick from the paired list rather than hard coding a match.</p>

<h2>ESC/POS is just bytes</h2>
<p>This plugin moves bytes. It does not build receipts. Composing an ESC/POS document is a separate job, and there are packages that do it well.</p>
""" + pre("""
const esc = 0x1B;
const gs = 0x1D;

await connection.output.writeBytes([esc, 0x40]);           // initialise
await connection.output.writeBytes([esc, 0x61, 0x01]);     // centre
await connection.output.writeString('MY SHOP');
await connection.output.writeBytes([0x0A]);                // line feed
await connection.output.writeBytes([esc, 0x61, 0x00]);     // left
await connection.output.writeString('Item        1.00');
await connection.output.writeBytes([0x0A, 0x0A, 0x0A]);
await connection.output.writeBytes([gs, 0x56, 0x00]);      // cut
""") + """
<p>Pair this with an ESC/POS builder package for real receipts, and pass its generated byte list to <code>writeBytes</code>. The <code>flutter_esc_pos_utils</code> family works well for that.</p>

<h2>The truncated last line</h2>
<p>The single most common complaint. You send a receipt, close the connection, and the last few lines never print.</p>
""" + pre("""
// Wrong: closes before the queue has drained.
connection.output.writeBytes(receipt);
await connection.close();

// Right: flush, then close.
await connection.output.writeBytes(receipt);
await connection.output.allSent;
await connection.finish();
""") + """
<p><code>finish</code> flushes pending writes before closing; <code>close</code> does not. Many printers also buffer internally, so give the paper feed at the end of the receipt real line feeds rather than relying on the cut command to push it out.</p>

<h2>Character encoding</h2>
<p>Thermal printers rarely speak UTF-8. Most use a code page, and non-ASCII characters come out as noise unless you match it.</p>
""" + pre("""
await connection.output.writeBytes([0x1B, 0x74, 0x00]);   // select code page
await connection.output.writeString('Café', encoding: latin1);
""") + """
<p>Which code page maps to which number is vendor specific and in the printer's manual. If accented characters are wrong, that pairing is where to look, not the Dart side.</p>

<h2>Images and receipts that stall</h2>
<p>A logo raster is large, and some printers cannot take it in one burst. If printing stalls partway through an image, send it in chunks and let the printer keep up.</p>
""" + pre("""
const chunk = 256;
for (var i = 0; i < raster.length; i += chunk) {
  await connection.output.writeBytes(
    raster.sublist(i, (i + chunk).clamp(0, raster.length)),
  );
  await Future<void>.delayed(const Duration(milliseconds: 20));
}
await connection.output.allSent;
""") + """
<h2>Common problems</h2>
<div class="tablewrap"><table>
<thead><tr><th>Symptom</th><th>Usually</th></tr></thead>
<tbody>
<tr><td>Last lines missing</td><td><code>close</code> instead of <code>finish</code>, or no <code>allSent</code></td></tr>
<tr><td>Accented characters wrong</td><td>Code page not selected, or the wrong encoding on <code>writeString</code></td></tr>
<tr><td>Prints nothing at all</td><td>Missing the <code>ESC @</code> initialise sequence</td></tr>
<tr><td>Image stalls halfway</td><td>Raster sent faster than the printer can absorb it</td></tr>
<tr><td>Connect fails while idle</td><td>Printer went to sleep. Power cycle and reconnect</td></tr>
</tbody></table></div>
""" + nxt([("send-receive-data", "Send and receive"), ("connect-bluetooth-device", "Connect")]),
    faq=[("How do I print to a Bluetooth thermal printer from Flutter?",
          "Connect to the printer over RFCOMM, then write ESC/POS bytes to the connection output. Use an ESC/POS builder package to compose the receipt and send the result with writeBytes."),
         ("Why does my Bluetooth printer cut off the last line?",
          "The connection was closed before the write queue drained. Await allSent and use finish rather than close, which discards anything still queued."),
         ("Why do accented characters print incorrectly on a thermal printer?",
          "Thermal printers use code pages rather than UTF-8. Select the printer's code page with an ESC t command and pass a matching encoding such as latin1 to writeString.")],
))
print("defined printer")

# ---------------------------------------------------------------- pairing
PAGES.append(dict(
    slug="pair-devices",
    title="How to Pair and Unpair Bluetooth Devices in Flutter",
    desc="Bond and unbond Bluetooth Classic devices from a Flutter app, watch bond state as pairing progresses, and understand what each platform actually lets you do.",
    h1="Pair and unpair",
    lede="Pairing is the one area where the platforms differ most, so check before you offer the button.",
    body=INSTALL + """
<h2>Pairing</h2>
""" + pre("""
final ok = await bluetooth.bondDevice('AA:BB:CC:DD:EE:FF');
""") + """
<p><code>true</code> means the request was accepted, not that pairing finished. The exchange is asynchronous and usually involves the user confirming a code. Watch the bond state to know how it ended.</p>
""" + pre("""
final sub = bluetooth.bondState(device.address).listen((state) {
  switch (state) {
    case BtcBondState.bonding:
      showProgress();
    case BtcBondState.bonded:
      connectNow();
    case BtcBondState.none:
      showFailed();
  }
});
""") + """
<p>A user who dismisses the system dialog produces <code>none</code>, not an error. Treat it as a cancellation rather than a failure worth an alert.</p>

<h2>Unpairing</h2>
""" + pre("""
await bluetooth.unbondDevice(device.address);
""") + """
<p>Android and Linux do this properly. Windows and macOS do not expose an API for it, so the call throws <code>BtcUnsupportedException</code> and the user has to remove the device in system settings. Say that in your UI rather than showing a button that fails.</p>

<h2>Check first</h2>
""" + pre("""
final caps = await bluetooth.getPlatformCapabilities();

if (caps.canBondDevices) {
  // show a Pair button
}
if (caps.canUnbondDevices) {
  // show a Forget button
}
""") + """
<h2>What each platform allows</h2>
<div class="tablewrap"><table>
<thead><tr><th>Platform</th><th>Pair</th><th>Unpair</th><th>Note</th></tr></thead>
<tbody>
<tr><td>Android</td><td>Yes</td><td>Yes</td><td>System dialog for the PIN</td></tr>
<tr><td>Windows</td><td>Yes</td><td>No</td><td>Remove in Settings</td></tr>
<tr><td>macOS</td><td>Yes</td><td>No</td><td>May show a system prompt; remove in System Settings</td></tr>
<tr><td>Linux</td><td>No</td><td>No</td><td>BlueZ needs a system pairing agent</td></tr>
<tr><td>iOS</td><td>No</td><td>No</td><td>Handled entirely by the system</td></tr>
</tbody></table></div>

<h2>Do you need to pair at all?</h2>
<p>Often not. A secure connection requires a bond, but the platform will usually create one for you when you connect, showing the same dialog the explicit call would. Calling <code>connect</code> directly and handling the failure is frequently a better flow than making the user press Pair and then Connect.</p>
<p>Where you do need it explicitly: when you want to pair well ahead of use, when the device needs a PIN entered outside your app, or when your UI shows a paired-device manager.</p>

<h2>Reading the current state</h2>
<p>Every device from a scan or from the paired list carries its bond state, so you can label a list without asking separately.</p>
""" + pre("""
for (final device in devices) {
  final label = switch (device.bondState) {
    BtcBondState.bonded => 'Paired',
    BtcBondState.bonding => 'Pairing...',
    BtcBondState.none => 'Not paired',
  };
  print('${device.displayName}: $label');
}
""") + nxt([("connect-bluetooth-device", "Connect"), ("desktop-bluetooth", "Desktop platforms")]),
    faq=[("How do I pair a Bluetooth device programmatically in Flutter?",
          "Call bondDevice with the address on Android, Windows or macOS, then watch bondState to see whether it reached bonded. Linux and iOS do not support programmatic pairing."),
         ("Why can I not unpair a Bluetooth device on Windows or macOS?",
          "Neither exposes a public API to remove a pairing. The call throws BtcUnsupportedException and the device has to be removed in system settings."),
         ("Do I have to pair before connecting over Bluetooth Classic?",
          "Usually not explicitly. A secure connection needs a bond, and the platform generally creates one during connect, showing the same dialog an explicit pair would.")],
))
print("defined pairing")

# ---------------------------------------------------------------- desktop
PAGES.append(dict(
    slug="desktop-bluetooth",
    title="Bluetooth Classic on Windows, macOS and Linux in Flutter",
    desc="What Bluetooth Classic support looks like on Flutter desktop: the Winsock2, IOBluetooth and BlueZ backends, what each one cannot do, and how to write one UI that adapts.",
    h1="Windows, macOS and Linux",
    lede="Desktop Bluetooth Classic works, with a different gap on each platform.",
    body=INSTALL + """
<h2>The backends</h2>
<div class="tablewrap"><table>
<thead><tr><th>Platform</th><th>Native API</th></tr></thead>
<tbody>
<tr><td>Windows</td><td>Winsock2 <code>AF_BTH</code> sockets</td></tr>
<tr><td>macOS</td><td>IOBluetooth</td></tr>
<tr><td>Linux</td><td>BlueZ RFCOMM sockets over D-Bus</td></tr>
</tbody></table></div>
<p>The Dart API is identical across all three. Anything unavailable throws <code>BtcUnsupportedException</code> rather than failing quietly or returning an empty result.</p>

<h2>What differs</h2>
<div class="tablewrap"><table>
<thead><tr><th>Feature</th><th>Windows</th><th>macOS</th><th>Linux</th></tr></thead>
<tbody>
<tr><td>Discovery</td><td>Yes</td><td>Yes</td><td>Yes</td></tr>
<tr><td>Paired devices</td><td>Yes</td><td>Yes</td><td>Yes</td></tr>
<tr><td>RFCOMM connect</td><td>Yes</td><td>Yes</td><td>Yes</td></tr>
<tr><td>RFCOMM server</td><td>Yes</td><td>Yes</td><td>Yes</td></tr>
<tr><td>Pair</td><td>Yes</td><td>Yes</td><td>No</td></tr>
<tr><td>Unpair</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>Enable / disable adapter</td><td>No</td><td>No</td><td>Yes</td></tr>
<tr><td>Set discoverable</td><td>Yes</td><td>No</td><td>Yes</td></tr>
<tr><td>Connection RSSI</td><td>No</td><td>Yes</td><td>No</td></tr>
</tbody></table></div>

<h2>Windows</h2>
<p>Nothing to configure. No manifest entry, no capability declaration, no extra dependency. Pairing works and shows the Windows pairing flow; removing a pairing has no public API, so that has to happen in Settings.</p>

<h2>macOS</h2>
<p>Add the Bluetooth entitlement to both <code>DebugProfile.entitlements</code> and <code>Release.entitlements</code>, or a sandboxed build sees nothing:</p>
""" + pre("""
<key>com.apple.security.device.bluetooth</key>
<true/>
""") + """
<p>macOS is the only platform that reports live signal strength on an open connection.</p>
""" + pre("""
final caps = await bluetooth.getPlatformCapabilities();
if (caps.canReadConnectionRssi) {
  final rssi = await connection.readRssi();
  print('$rssi dBm');
}
""") + """
<p>Everywhere else <code>readRssi</code> throws, because no public Bluetooth Classic API exposes it. Discovery-time RSSI on <code>BtcDevice.rssi</code> is separate and available everywhere.</p>

<h2>Linux</h2>
<p>The native plugin links against GTK and BlueZ, so the development packages have to be present or the build fails at CMake:</p>
""" + pre("""
sudo apt-get install -y libgtk-3-dev libbluetooth-dev ninja-build cmake pkg-config clang
""") + """
<p>Linux is the only desktop that can turn the adapter on and off. It cannot pair, because BlueZ delegates PIN and passkey handling to a system pairing agent that a Flutter app does not provide. Pair with <code>bluetoothctl</code> or the desktop's Bluetooth settings, then connect normally.</p>

<h2>One UI, every platform</h2>
<p>Reading capabilities rather than checking <code>Platform.isWindows</code> keeps the code honest, and keeps working when a gap gets filled in a later release.</p>
""" + pre("""
final caps = await bluetooth.getPlatformCapabilities();

setState(() {
  showScanButton    = caps.canDiscoverDevices;
  showPairButton    = caps.canBondDevices;
  showForgetButton  = caps.canUnbondDevices;
  showAdapterToggle = caps.canEnableBluetooth;
  showServerTab     = caps.canCreateServer;
});
""") + """
<p>Wrap anything you cannot gate in a <code>try</code> for <code>BtcUnsupportedException</code>, so an unexpected platform degrades instead of crashing.</p>
""" + nxt([("bluetooth-permissions", "Permissions"), ("rfcomm-server", "Run a server")]),
    faq=[("Does Bluetooth Classic work on Flutter desktop?",
          "Yes. Windows uses Winsock2 AF_BTH, macOS uses IOBluetooth and Linux uses BlueZ. Discovery, paired devices, RFCOMM connections and server mode work on all three."),
         ("Why can I not pair a Bluetooth device on Linux from Flutter?",
          "BlueZ delegates PIN and passkey handling to a system pairing agent that a Flutter app does not register. Pair with bluetoothctl or the desktop Bluetooth settings, then connect."),
         ("How do I read Bluetooth signal strength on an open connection?",
          "Call readRssi, which is supported on macOS only. Check canReadConnectionRssi first. Discovery-time RSSI is on BtcDevice.rssi and is available on every platform.")],
))
print("defined desktop")

# ---------------------------------------------------------------- errors
PAGES.append(dict(
    slug="troubleshooting",
    title="Bluetooth Classic Errors in Flutter and How to Fix Them",
    desc="The typed exceptions flutter_classic_bluetooth throws, what each one actually means, and the recurring causes behind connections that hang, drop or deliver nothing.",
    h1="Troubleshooting",
    lede="Every failure is a typed exception, so you can handle the ones you can recover from and let the rest surface.",
    body=INSTALL + """
<h2>The exceptions</h2>
<div class="tablewrap"><table>
<thead><tr><th>Exception</th><th>Means</th></tr></thead>
<tbody>
<tr><td><code>BtcUnsupportedException</code></td><td>The platform has no API for this</td></tr>
<tr><td><code>BtcPermissionException</code></td><td>The user denied a permission, or it is missing from the manifest</td></tr>
<tr><td><code>BtcDisabledException</code></td><td>The adapter is off</td></tr>
<tr><td><code>BtcConnectionException</code></td><td>The connection was refused or lost</td></tr>
<tr><td><code>BtcWriteException</code></td><td>A write failed, usually because the link is gone</td></tr>
<tr><td><code>BtcDiscoveryException</code></td><td>Discovery could not start</td></tr>
<tr><td><code>BtcTimeoutException</code></td><td>The deadline passed first</td></tr>
<tr><td><code>BtcAddressException</code></td><td>The MAC address is malformed</td></tr>
<tr><td><code>BtcUuidException</code></td><td>The UUID is malformed</td></tr>
</tbody></table></div>
<p>All of them extend <code>BtcException</code>, so a single catch covers everything while you narrow the cases you can act on.</p>
""" + pre("""
try {
  final connection = await bluetooth.connect(
    address: device.address,
    timeout: const Duration(seconds: 8),
  );
} on BtcPermissionException {
  showSettingsPrompt();
} on BtcDisabledException {
  askUserToEnableBluetooth();
} on BtcTimeoutException {
  showRetry('Device did not respond. Is it powered on?');
} on BtcException catch (e) {
  report(e.message);
}
""") + """
<h2>Nothing happens when I scan</h2>
<p>In order of how often it turns out to be the cause: the manifest is missing the permissions, the user denied the runtime prompt, the adapter is off, or you are on iOS, which has no discovery API at all. Work through it rather than guessing:</p>
""" + pre("""
final caps = await bluetooth.getPlatformCapabilities();
print('can discover: ${caps.canDiscoverDevices}');
print('supported:    ${await bluetooth.isSupported()}');
print('enabled:      ${await bluetooth.isEnabled()}');
""") + """
<p>On Android 11 and below, remember that scanning needs location permission, and a device with location services switched off at the system level returns an empty scan with no error.</p>

<h2>Connect hangs forever</h2>
<p>Pass a <code>timeout</code>. Without one the native call decides how long to block, and for a device that is off or out of range that can be a very long time. A native connect cannot be cancelled, so an attempt that lands after your deadline is closed and released for you rather than leaking a socket.</p>

<h2>Connects, then drops right away</h2>
<p>Usually power on the device side rather than anything in software. Modules driven from a pin that cannot supply the peak current during transmit brown out the moment the radio comes up. If the device is already connected to something else, most modules accept exactly one link and refuse the second.</p>

<h2>Data arrives split or merged</h2>
<p>Expected. RFCOMM is a byte stream, and event boundaries mean nothing. Use <code>lines</code> or <code>frames</code> rather than treating each event as a message. This is covered in full on the <a href="/send-receive-data">send and receive</a> page.</p>

<h2>Received text is garbage</h2>
<p>On an HC-05 or similar module, a baud mismatch between the sketch and the module. On a thermal printer, a code page mismatch. Both produce a working connection that delivers the wrong bytes, which is why they are easy to mistake for a plugin problem.</p>

<h2>The last thing I sent never arrived</h2>
""" + pre("""
await connection.output.writeBytes(payload);
await connection.output.allSent;
await connection.finish();
""") + """
<p><code>close</code> drops whatever is still queued. <code>finish</code> flushes first. Use <code>finish</code> unless you are tearing down after an error and no longer care.</p>

<h2>It worked, then stopped after reflashing</h2>
<p>The bond went stale. Unpair the device in system settings and pair again. This is common with ESP32 boards, where reflashing can change what the device advertises.</p>

<h2>Works on Android, not on iOS</h2>
<p>iOS only reaches MFi certified accessories whose protocol string is declared in <code>Info.plist</code>, and it cannot discover devices at all. A generic HC-05 or ESP32 is unreachable on iOS. This is an Apple restriction, not something a plugin can work around.</p>

<h2>Reporting something</h2>
<p>If none of this fits, the <a href="https://github.com/almasumdev/flutter_classic_bluetooth/issues">issue tracker</a> is the place. Include the platform and version, the device you are talking to, the exception type and message, and the smallest snippet that reproduces it.</p>
""" + nxt([("bluetooth-permissions", "Permissions"), ("connect-bluetooth-device", "Connect")]),
    faq=[("Why does my Flutter Bluetooth scan return no devices?",
          "Check the manifest permissions, whether the runtime prompt was denied, whether the adapter is on, and on Android 11 and below whether system location services are enabled. iOS has no Bluetooth Classic discovery API at all."),
         ("Why does connect hang forever in Flutter Bluetooth?",
          "Because no timeout was passed. The native call blocks for a platform-decided period when the device is off or out of range. Pass a timeout so it throws BtcTimeoutException instead."),
         ("Why did the last data I sent over Bluetooth never arrive?",
          "close discards queued writes. Await allSent and call finish, which flushes pending writes before closing the connection.")],
))
print("defined troubleshooting")

print("all %d pages defined" % len(PAGES))


# ---------------------------------------------------------------- emit

slugs = []
for p in PAGES:
    html = page(p["slug"], p["title"], p["desc"], p["h1"], p["lede"], p["body"], p.get("faq"))
    io.open(os.path.join(OUT, p["slug"] + ".html"), "w", encoding="utf-8", newline="\n").write(html)
    slugs.append(p["slug"])
    print("  %-24s %6d bytes" % (p["slug"] + ".html", len(html)))

urls = "".join(
    "  <url><loc>%s</loc><changefreq>monthly</changefreq><priority>%s</priority></url>\n"
    % (BASE + "/" + ("" if s == "index" else s), "1.0" if s == "index" else "0.8")
    for s in slugs
)
io.open(os.path.join(OUT, "sitemap.xml"), "w", encoding="utf-8", newline="\n").write(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n%s</urlset>\n' % urls)

io.open(os.path.join(OUT, "robots.txt"), "w", encoding="utf-8", newline="\n").write(
    "User-agent: *\nAllow: /\n\nSitemap: %s/sitemap.xml\n" % BASE)

shutil.copyfile("images/logo.svg", os.path.join(OUT, "logo.svg"))

# Search Console ownership proof. Copied verbatim; Google matches the exact
# bytes at the exact path, so this must not be templated or minified.
for proof in glob.glob("tool/docs_assets/google*.html"):
    shutil.copyfile(proof, os.path.join(OUT, os.path.basename(proof)))

# IndexNow ownership proof: the file name is the key and so are its contents.
io.open(os.path.join(OUT, INDEXNOW_KEY + ".txt"), "w", encoding="utf-8",
        newline="\n").write(INDEXNOW_KEY + "\n")

print("wrote sitemap.xml (%d urls), robots.txt, logo.svg" % len(slugs))
