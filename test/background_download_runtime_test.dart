import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/background_download_runtime.dart';

void main() {
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
  });

  test('failed batch still releases its outer lease', () async {
    final runtime = BackgroundDownloadRuntime.instance;
    await expectLater(runtime.holdQueue(() async {
      expect(runtime.hasTransfers, true);
      throw StateError('simulated transfer error');
    }), throwsStateError);
    expect(runtime.hasTransfers, false);
  });
}
