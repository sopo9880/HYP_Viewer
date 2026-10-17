import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/background_download_runtime.dart';

void main() {
  // flutter test on Windows runs without the native tray/window host plugins.
  // Queue lease behavior remains covered by the Linux/Android CI test runner.
  final skipNativeTrayTest = Platform.isWindows
      ? 'Windows system tray requires the running desktop plugin host.'
      : false;
  test('one outer queue lease survives nested per-work leases', () async {
    final runtime = BackgroundDownloadRuntime.instance;
    expect(runtime.hasTransfers, false);
    await runtime.holdQueue(() async {
      expect(runtime.hasTransfers, true);
      await runtime.acquire();
      await runtime.release();
      expect(runtime.hasTransfers, true);
    });
    expect(runtime.hasTransfers, false);
  }, skip: skipNativeTrayTest);

  test('failed batch still releases its outer lease', () async {
    final runtime = BackgroundDownloadRuntime.instance;
    await expectLater(runtime.holdQueue(() async {
      expect(runtime.hasTransfers, true);
      throw StateError('simulated transfer error');
    }), throwsStateError);
    expect(runtime.hasTransfers, false);
  }, skip: skipNativeTrayTest);
}
