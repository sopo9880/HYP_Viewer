import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/reader_settings.dart';

void main() {
  test('reader settings round-trip with clamped invalid input', () {
    final prefs = const ReaderSettings(
      nextDirection: 'right',
      twoPageSpread: true,
      preloadPages: 3,
    );
    final output = ReaderSettings.fromJson(prefs.toJson());
    expect(output.reverse, true);
    expect(output.twoPageSpread, true);
    expect(output.preloadPages, 3);

    final bad = ReaderSettings.fromJson({
      'nextDirection': 'nonsense',
      'preloadPages': 100,
      'twoPageSpread': 1,
    });
    expect(bad.nextDirection, 'left');
    expect(bad.twoPageSpread, false);
    expect(bad.preloadPages, 3);
  });

  test('persists reading preferences independently of the library', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-reader-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = ReaderSettingsStorage(baseDirectory: dir);
    expect((await settings.load()).preloadPages, 2);
    await settings.save(const ReaderSettings(
        nextDirection: 'right', twoPageSpread: true, preloadPages: 1));
    final restored = await ReaderSettingsStorage(baseDirectory: dir).load();
    expect(restored.reverse, true);
    expect(restored.twoPageSpread, true);
    expect(restored.preloadPages, 1);
  });
}
