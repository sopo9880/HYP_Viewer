import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/reader_settings.dart';

void main() {
  test('reader settings round-trip with clamped invalid input', () {
    final prefs = const ReaderSettings(
      nextDirection: 'right',
      twoPageSpread: true,
      confirmCompleteOnNext: false,
      volumeKeyNavigation: true,
      volumeHoldIntervalMs: 700,
      verticalScrolling: true,
      showDownloadAction: false,
      showOrientationAction: false,
      openAfterSave: true,
      languageCode: 'ja',
      heroArtworkSource: 'random',
      tapNavigation: true,
      webtoonMode: true,
      autoDownloadOnSave: true,
      preloadPages: -1,
      dataSaverMode: true,
      librarySort: 'mostRead',
      popularityPeriod: 'year',
      librarySortDescending: true,
      recentCollapsed: true,
      expandedSettings: ['backup', 'viewer'],
    );
    final output = ReaderSettings.fromJson(prefs.toJson());
    expect(output.reverse, true);
    expect(output.twoPageSpread, true);
    expect(output.confirmCompleteOnNext, false);
    expect(output.volumeKeyNavigation, true);
    expect(output.volumeHoldIntervalMs, 700);
    expect(output.verticalScrolling, true);
    expect(output.showDownloadAction, false);
    expect(output.showOrientationAction, false);
    expect(output.openAfterSave, true);
    expect(output.languageCode, 'ja');
    expect(output.heroArtworkSource, 'random');
    expect(output.tapNavigation, true);
    expect(output.webtoonMode, true);
    expect(output.autoDownloadOnSave, true);
    expect(output.preloadPages, -1);
    expect(output.dataSaverMode, true);
    expect(output.librarySort, 'mostRead');
    expect(output.popularityPeriod, 'year');
    expect(output.librarySortDescending, true);
    expect(output.recentCollapsed, true);
    expect(output.expandedSettings, contains('backup'));

    final bad = ReaderSettings.fromJson({
      'nextDirection': 'nonsense',
      'preloadPages': 100,
      'twoPageSpread': 1,
      'languageCode': 'invalid',
      'openAfterSave': 'true',
      'volumeHoldIntervalMs': -500,
    });
    expect(bad.nextDirection, 'left');
    expect(bad.twoPageSpread, false);
    expect(bad.verticalScrolling, false);
    expect(bad.showDownloadAction, true);
    expect(bad.showOrientationAction, true);
    expect(bad.preloadPages, 100);
    expect(bad.openAfterSave, false);
    expect(bad.confirmCompleteOnNext, true);
    expect(bad.volumeHoldIntervalMs, 400);
    expect(ReaderSettings.fromJson({'volumeHoldIntervalMs': 200}).volumeHoldIntervalMs, 200);
    expect(bad.languageCode, 'ko');
    expect(bad.heroArtworkSource, 'custom');
    expect(bad.tapNavigation, true);
    expect(ReaderSettings.fromJson({'tapNavigation': false}).tapNavigation, false);
    expect(bad.webtoonMode, false);
    expect(bad.autoDownloadOnSave, false);
  });

  test('persists reading preferences independently of the library', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-reader-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = ReaderSettingsStorage(baseDirectory: dir);
    expect((await settings.load()).preloadPages, -1);
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
