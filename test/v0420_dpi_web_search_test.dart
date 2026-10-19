import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/android_dpi.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/windows_dpi.dart';
import 'package:hyp_viewer/ui/auto_hitomi_web_search.dart';

void main() {
  test('Windows and Android advertise five matching user presets', () {
    const expected = [
      'russia_blacklist', 'russia_blacklist_dnsredir', 'all',
      'all_dnsredir', 'all_dnsredir_hardcore',
    ];
    expect(AndroidDpiPreferences.presets, expected);
    for (final name in expected) {
      expect(WindowsDpiPreferences.presets, contains(name));
      expect(AndroidDpiPreferences.options, contains(name));
    }
    expect(const WindowsDpiPreferences().preset, 'all_dnsredir');
    expect(const AndroidDpiPreferences().preset, 'all_dnsredir');
    expect(const WindowsDpiPreferences().enabled, isFalse);
    expect(const AndroidDpiPreferences().enabled, isFalse);
  });

  test('VPN mode is opt-in and excluded packages persist independently', () {
    const prefs = AndroidDpiPreferences(
      scope: 'device', preset: 'russia_blacklist_dnsredir',
      excludedApps: ['com.example.browser'], autoStart: false,
    );
    final restored = AndroidDpiPreferences.fromJson(prefs.toJson());
    expect(restored.scope, 'device');
    expect(restored.preset, 'russia_blacklist_dnsredir');
    expect(restored.excludedApps, ['com.example.browser']);
    expect(restored.autoStart, isFalse);
    expect(AndroidDpiPreferences.fromJson({
      'excludedApps': ['../../../invalid', 'com.example.safe'],
      'scope': 'untrusted',
    }).excludedApps, ['com.example.safe']);
    expect(AndroidDpiPreferences.fromJson({'scope': 'untrusted'}).scope, 'app');
  });

  test('Automatic public website search defaults ON and respects opt-out', () {
    final initial = ReaderSettings.fromJson({});
    expect(initial.autoWebSearch, isTrue);
    final off = initial.copyWith(autoWebSearch: false);
    expect(ReaderSettings.fromJson(off.toJson()).autoWebSearch, isFalse);
    expect(AutoWebSearchPolicy.shouldSearch(
      enabled: false, query: 'example', scope: 'all'), isFalse);
    expect(AutoWebSearchPolicy.shouldSearch(
      enabled: true, query: 'example', scope: 'local'), isFalse);
    expect(AutoWebSearchPolicy.shouldSearch(
      enabled: true, query: '', scope: 'online'), isFalse);
    expect(AutoWebSearchPolicy.shouldSearch(
      enabled: true, query: 'a'.padRight(151, 'a'), scope: 'online'), isFalse);
    expect(AutoWebSearchPolicy.cacheTtl, const Duration(minutes: 10));
    expect(AutoWebSearchPolicy.debounce.inMilliseconds, greaterThan(450));
  });

  test('VPN routes to pinned local SOCKS5 and excludes the HYP package',
      () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    final vpn = await File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/AndroidDpiVpnService.kt',
    ).readAsString();
    final activity = await File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/MainActivity.kt',
    ).readAsString();
    final presets = await File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/AndroidDpiPresets.kt',
    ).readAsString();
    final workflow = await File('.github/workflows/verify.yml').readAsString();
    expect(manifest, contains('android.permission.BIND_VPN_SERVICE'));
    expect(manifest, contains('android:name=".AndroidDpiVpnService"'));
    expect(manifest, contains('android:name=".AndroidDpiSocksService"'));
    expect(vpn, contains('builder.addDisallowedApplication(packageName)'));
    expect(vpn, contains('TProxyService.TProxyStartService'));
    expect(vpn, contains('TProxyService.TProxyStopService'));
    expect(vpn, contains('77.88.8.8'));
    expect(activity, contains('VpnService.prepare(this)'));
    expect(activity, contains('vpnPermissionRequest'));
    expect(activity, contains('AndroidDpiSocksService::class.java'));
    expect(presets, contains('russia_blacklist_dnsredir'));
    expect(presets, contains('"-H"'));
    expect(workflow, contains('scripts/prepare_android_vpn_tunnel.py'));
    expect(workflow, contains('scripts/prepare_android_dpi_blacklist.py'));
  });

  test('Auto website results are search-scoped, bounded and independently merged',
      () async {
    final source = await File('lib/ui/hyp_dashboard.dart').readAsString();
    final widget = await File('lib/ui/auto_hitomi_web_search.dart')
        .readAsString();
    expect(source, contains('AutoHitomiWebSearch('));
    expect(source, contains('AutoWebSearchPolicy.shouldSearch'));
    expect(source, contains('query != _search.text.trim()'));
    expect(source, contains('_autoWebCache'));
    expect(source, contains('autoWebSearch: value'));
    expect(widget, contains('HitomiWebSearch.captureJavaScript'));
    expect(widget, contains('HitomiWebSearch.allowedOrigin'));
    expect(widget, contains('Duration(seconds: 12)'));
    expect(widget, contains('widget.onFinished(widget.query'));
  });

  test('Android DPI lifecycle has no duplicate or truncated declarations',
      () async {
    final dart = await File('lib/core/android_dpi.dart').readAsString();
    for (final signature in <String>[
      'Future<void> setExcludedApps(',
      'Future<void> refresh() async {',
      'Future<bool> checkSite() async {',
      'Future<void> _serialize(',
    ]) {
      expect(signature.allMatches(dart).length, 1,
          reason: 'duplicate/missing Android DPI lifecycle declaration');
    }
    expect(dart, contains("RegExp(r'^[A-Za-z0-9_.]{3,150}\$')"));
    expect(dart, contains("'vpnStatus'"));
  });

  test('Pinned native ByeDPI arguments and NDK build wiring are valid',
      () async {
    final presets = await File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/AndroidDpiPresets.kt',
    ).readAsString();
    final build = await File('scripts/prepare_android_vpn_tunnel.py')
        .readAsString();
    for (final workflow in [
      '.github/workflows/verify.yml',
      '.github/workflows/release.yml',
    ]) {
      final source = await File(workflow).readAsString();
      expect(source, contains('cmdline-tools/latest/bin/sdkmanager'));
    }
    expect(presets, contains('"-M", "h"'));
    expect(presets, isNot(contains('"-M", "hcsmix"')));
    expect(build, contains('APP_CFLAGS=-DANDROID'));
    expect(build, contains('780b396b0fc3d0355fc0614e221e3446933669c4'));
  });

}
