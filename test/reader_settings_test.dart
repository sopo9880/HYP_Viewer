import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/reader_settings.dart';

void main() {
  test('reader settings round-trip with clamped invalid input', () {
    final prefs = const ReaderSettings(
      nextDirection: 'right',
      twoPageSpread: true,
      verticalScrolling: true,
      showDownloadAction: false,
      showOrientationAction: false,
      preloadPages: 3,
      openAfterSave: true,
      languageCode: 'ja',
    );
    final output = ReaderSettings.fromJson(prefs.toJson());
    expect(output.reverse, true);
    expect(output.twoPageSpread, true);
    expect(output.verticalScrolling, true);
    expect(output.showDownloadAction, false);
    expect(output.showOrientationAction, false);
    expect(output.preloadPages, 3);
    expect(output.openAfterSave, true);
    expect(output.languageCode, 'ja');

    final bad = ReaderSettings.fromJson({
      'nextDirection': 'nonsense',
      'preloadPages': 100,
      'twoPageSpread': 1,
      'languageCode': 'invalid',
      'openAfterSave': 'true',
    });
    expect(bad.nextDirection, 'left');
    expect(bad.twoPageSpread, false);
    expect(bad.verticalScrolling, false);
    expect(bad.showDownloadAction, true);
    expect(bad.showOrientationAction, true);
    expect(bad.preloadPages, 3);
    expect(bad.openAfterSave, false);
    expect(bad.languageCode, 'ko');
  });

  test('persists reading preferences independently of the library', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-reader-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = ReaderSettingsStorage(baseDirectory: dir);
    expect((await settings.load()).preloadPages, 2);
    await settings.save(const ReaderSettings(
        nextDirection: 'right', twoPageSpread: true,
        verticalScrolling: true, preloadPages: 1,
        openAfterSave: true, languageCode: 'en'));
    final restored = await ReaderSettingsStorage(baseDirectory: dir).load();
    expect(restored.reverse, true);
    expect(restored.twoPageSpread, true);
    expect(restored.verticalScrolling, true);
    expect(restored.preloadPages, 1);
    expect(restored.openAfterSave, true);
    expect(restored.languageCode, 'en');
  });
}
