# HYP Viewer v0.4.20 — Android DPI architecture and limitations

This is the reviewed 0.x implementation plan **as source code in PR**, NOT a
statement that CI or a real Android device has passed validation.

## Presets: same names, independent engines

Five displayed names are shared between Windows and Android:
- russia_blacklist
- russia_blacklist_dnsredir
- all
- all_dnsredir (recommended)
- all_dnsredir_hardcore

Windows uses the official GoodbyeDPI binary with WinDivert and its original
switches. Android uses a pinned MIT-licensed hufrea/ByeDPI local proxy.
ByeDPI's -s, -d, -q, -H and -M flags are *not* identical to GoodbyeDPI's
-1/-9, packet checksum/SEQ tricks or DNS redirection.

Blacklist profiles on Android use the SHA-256-verified official
russia-blacklist.txt, copied to app-private storage. The remaining profiles
apply to all hosts. The most aggressive profile adds out-of-order/OOB and
HTTP Host modification. It is not guaranteed to work on every network.

### DNS accuracy, not name-only parity

Windows dnsredir presets direct UDP DNS to Yandex DNS 77.88.8.8:1253.
Android's VPN Builder permits a DNS **server address** but not a custom
port. In **device VPN mode**, the mapped DNS server is 77.88.8.8 **port 53**
via the local SOCKS5 tunnel. This DOES NOT offer the nonstandard-port
anti-poisoning behavior of Windows DNS mode, and must not be described as
an exact reproduction. Android **app-only** mode does not redirect DNS.
Connection tests on real mobile networks are needed before evaluating
the effectiveness of these choices.

## Scope: two explicit modes

1. **App only (no VPN consent):** AndroidDpiService in :dpi starts a local
   HTTP CONNECT proxy. Flutter HttpClient and Android WebView ProxyController
   are set to the same loopback port. This does not touch other applications.
2. **Device VPN (user-approved):** after an explicit Android VpnService.prepare
   consent, AndroidDpiSocksService in :dpisocks starts a second ByeDPI engine
   in SOCKS5 mode. AndroidDpiVpnService establishes a TUN interface and
   starts pinned MIT hev-socks5-tunnel JNI, forwarding device TCP/UDP to
   the local SOCKS5 engine. This is not a remote VPN and does not provide
   VPN-server encryption or mask the public IP address. HYP Viewer's package
   is always excluded to prevent a routing loop. Users can choose additional
   installed apps to exclude. Only one Android VPN can normally be active.

The user must explicitly toggle DPI ON and approve VPN; upgrading to this
version never silently enables whole-device mode. The legacy Android
standard/strong/sni presets do not silently become a different profile:
saved legacy configurations are reset to OFF with an 'all' fallback, while
the rest of app settings, downloaded CBZs and library remain unchanged.

When stopping, the app asks both the VPN and SOCKS services to stop, checks
the VPN status, clears WebView proxy override and disables Dart HTTP proxy.
A revoked VPN is detected on the next periodic status check; ON must not be
reported when the tunnel is inactive.

## Pinned source and packaging

- hufrea/ByeDPI, MIT
  ba532298de7b28cfe854aea83d061369d13ca290
- heiher/hev-socks5-tunnel, MIT, with recursively pinned submodules
  780b396b0fc3d0355fc0614e221e3446933669c4
- GoodbyeDPI official ZIP and blacklist, pinned checksum
  37f96b32d050dadcc930a639eba68e1ccd57ed5c04a5f77dfca908f01905a4c5
- Android NDK 27.2.12479018, 16-KiB page-size aware native builds

CI fetches exact immutable upstream commits, stages source & license files,
compiles the tun2socks native bridge for arm64-v8a/armeabi-v7a/x86_64,
and packages the resulting .so in the APK. Nothing is downloaded at runtime.
Windows keeps its existing GoodbyeDPI separate.

## Automatic website search

Default enabled in ReaderSettings.autoWebSearch, which persists in the same
reader settings JSON as the rest of the app preferences. After a 950ms
debounce, an offscreen, ephemeral WebView reads only verified gallery links
from the rendered public hitomi.la page, stops within 12s, caches results for
10m, merges by gallery ID and never overwrites original API results.
'My shelf only' and opt-out skip the WebView. The existing manual browser
remains. Any login state is never exported from WebView.

## CI and device acceptance

GitHub Actions must validate Dart analyzer, Flutter tests, Android
native/NDK source and library checks, debug and signed-release APK
builds (including R8 JNI keeps), Windows EXE/installer and localization.
No claim of *successful censorship bypass* may be made solely from CI.

On a physical device: verify app-only HTTP and WebView requests, explicit
VPN consent, whole-device browser traffic, DNS-mode resolver behavior,
selected excluded apps, IPv4/IPv6, Wi-Fi/mobile handovers, revoke/stop
recovery, Android background downloads and conflicts with an existing VPN.
Specifically test whether 77.88.8.8:53 works on the carrier; it is NOT
equivalent to Windows DNS :1253 under poisoning or UDP blocking.
