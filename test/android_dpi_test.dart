import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/android_dpi.dart';

void main() {
  test('Android DPI opt-in defaults preserve all existing app traffic', () {
    const pref = AndroidDpiPreferences();
    expect(pref.enabled, isFalse);
    expect(pref.autoStart, isFalse);
    expect(pref.preset, 'all_dnsredir');
    expect(pref.scope, 'app');
    expect(AndroidDpiHttpOverrides.enabled, isFalse);
    expect(AndroidDpiHttpOverrides.port, isNull);
  });

  test('persisted presets are strictly allowlisted', () {
    final safe = AndroidDpiPreferences.fromJson({
      'enabled': true, 'autoStart': true, 'preset': 'all_dnsredir',
      'scope': 'device', 'excludedApps': ['com.example.mail'],
    });
    expect(safe.enabled, isTrue);
    expect(safe.autoStart, isTrue);
    expect(safe.preset, 'all_dnsredir');
    expect(safe.scope, 'device');
    expect(safe.excludedApps, ['com.example.mail']);
    expect(AndroidDpiPreferences.options['all'], '-s 1');
    final invalid = AndroidDpiPreferences.fromJson({
      'enabled': false, 'preset': '../exec --daemon',
    });
    expect(invalid.preset, 'all_dnsredir');
    expect(AndroidDpiPreferences.presets, containsAll([
      'russia_blacklist', 'russia_blacklist_dnsredir', 'all',
      'all_dnsredir', 'all_dnsredir_hardcore',
    ]));
    final legacy = AndroidDpiPreferences.fromJson({
      'enabled': true, 'preset': 'strong',
    });
    expect(legacy.enabled, isFalse); // Cannot silently migrate DPI mode.
    expect(legacy.scope, 'app');
  });

  test('Dart local HTTP CONNECT state validates ports and can be disabled', () {
    AndroidDpiHttpOverrides.setLocalPort(32015);
    expect(AndroidDpiHttpOverrides.enabled, true);
    expect(AndroidDpiHttpOverrides.port, 32015);
    expect(() => AndroidDpiHttpOverrides.setLocalPort(0), throwsArgumentError);
    expect(() => AndroidDpiHttpOverrides.setLocalPort(65536),
        throwsArgumentError);
    AndroidDpiHttpOverrides.setLocalPort(null);
    expect(AndroidDpiHttpOverrides.enabled, false);
  });

  test('Android native engine and manifest are wired, not a mock toggle',
      () async {
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    final native = await File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/AndroidDpiService.kt',
    ).readAsString();
    final activity = await File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/MainActivity.kt',
    ).readAsString();
    final cmake = await File('android/app/src/main/cpp/CMakeLists.txt')
        .readAsString();
    final workflow = await File('.github/workflows/verify.yml')
        .readAsString();
    expect(manifest, contains('android:name=".AndroidDpiService"'));
    expect(manifest, contains('android:process=":dpi"'));
    expect(manifest, contains('android:foregroundServiceType="specialUse"'));
    expect(native, contains('native.run(args.toTypedArray())'));
    expect(native, contains('"socks5"'));
    expect(native, contains('AndroidDpiPresets.proxyOptions'));
    expect(activity, contains('ProxyController.getInstance().setProxyOverride'));
    expect(activity, contains('ProxyController.getInstance().clearProxyOverride'));
    expect(activity, contains('"hyp_viewer/android_dpi"'));
    expect(cmake, contains('add_library(hyp_byedpi SHARED'));
    expect(workflow, contains('scripts/prepare_android_byedpi.py'));
    expect(workflow, contains('scripts/configure_android_dpi.py'));
  });
}
