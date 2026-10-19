import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/android_dpi.dart';

void main() {
  test('Android DPI opt-in defaults preserve all existing app traffic', () {
    const pref = AndroidDpiPreferences();
    expect(pref.enabled, isFalse);
    expect(pref.autoStart, isFalse);
    expect(pref.preset, 'standard');
    expect(AndroidDpiHttpOverrides.enabled, isFalse);
    expect(AndroidDpiHttpOverrides.port, isNull);
  });

  test('persisted presets are strictly allowlisted', () {
    final safe = AndroidDpiPreferences.fromJson({
      'enabled': true, 'autoStart': true, 'preset': 'strong',
    });
    expect(safe.enabled, isTrue);
    expect(safe.autoStart, isTrue);
    expect(safe.preset, 'strong');
    expect(AndroidDpiPreferences.options['strong'], '-s 1 -q 1');
    final invalid = AndroidDpiPreferences.fromJson({
      'enabled': false, 'preset': '../exec --daemon',
    });
    expect(invalid.preset, 'standard');
    expect(AndroidDpiPreferences.presets, containsAll(['standard', 'sni']));
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
    expect(native, contains('http://127.0.0.1'));
    expect(activity, contains('ProxyController.getInstance().setProxyOverride'));
    expect(activity, contains('ProxyController.getInstance().clearProxyOverride'));
    expect(activity, contains('"hyp_viewer/android_dpi"'));
    expect(cmake, contains('add_library(hyp_byedpi SHARED'));
    expect(workflow, contains('scripts/prepare_android_byedpi.py'));
    expect(workflow, contains('scripts/configure_android_dpi.py'));
  });
}
