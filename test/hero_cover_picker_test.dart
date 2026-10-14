import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/hero_cover_picker.dart';
import 'package:hyp_viewer/core/reader_settings.dart';

void main() {
  test('saved image picks from available covers, not built-in presets', () {
    expect(pickRandomLibraryCover([]), isNull);
    expect(pickRandomLibraryCover(['a']), 'a');
    final changed = pickRandomLibraryCover(
        ['a', 'b', 'c'], previous: 'a', random: Random(2));
    expect(changed, isNot('a'));
    expect(['b', 'c'], contains(changed));
  });

  test('banner source roundtrip defaults to previous custom artwork', () {
    expect(ReaderSettings.fromJson({}).heroArtworkSource, 'custom');
    expect(ReaderSettings.fromJson({'heroArtworkSource':'invalid'})
        .heroArtworkSource, 'custom');
    for (final mode in ['default', 'custom', 'random']) {
      final value = const ReaderSettings()
          .copyWith(heroArtworkSource: mode);
      expect(ReaderSettings.fromJson(value.toJson()).heroArtworkSource, mode);
    }
  });
}
