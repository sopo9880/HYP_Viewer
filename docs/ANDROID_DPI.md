# Android DPI support — v0.4.19

HYP Viewer runs a pinned, MIT-licensed copy of
[hufrea/ByeDPI](https://github.com/hufrea/byedpi) on-device.

Implementation:
* Separate Android foreground service (\`:dpi\`) runs the C native
  HTTP CONNECT proxy bound to loopback only.
* WebView uses the AndroidX WebKit ProxyController override.
* Dart's HttpClient uses an HttpOverrides proxy for the app's HTTP(S)
  metadata, images and CBZ downloads when enabled.
* The override is applied only after the native proxy is ready.
* Turning OFF restores direct networking; a failed start does not
  claim success. No root, VPN permission, or TLS certificate interception.
* This is **app-scoped**: it does not reroute other apps or every third-party
  native SDK. Android VpnService/tun2socks would be required for
  system-wide support, but was deliberately avoided because the
  user specifically needs HYP Viewer networking.
* Different networks may require different splitting presets. An APK
  passing CI does NOT establish DPI circumvention on a real network.
* The app does not install or start a separate external DPI application.

Source: hufrea/byedpi, commit
ba532298de7b28cfe854aea83d061369d13ca290.
License: MIT. scripts/prepare_android_byedpi.py verifies the exact
revision, stages C sources for CMake, and embeds the upstream license at
assets/licenses/ByeDPI-MIT.txt.

Device acceptance: after activation check Hitomi search WebView, online
metadata, image loading, download and return to direct networking when
disabled. Test again when the app is backgrounded and after relaunch.
