import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/hitomi_popularity.dart';

void main() {
  test('parses big-endian ids and preserves first rank', () {
    final ranks = HitomiPopularity.parseNozomi(Uint8List.fromList(
        [0, 0, 0, 42, 0, 0, 1, 0, 0, 0, 0, 42]));
    expect(ranks, {'42': 1, '256': 2});
  });
  test('rejects truncated ranking data', () {
    expect(() => HitomiPopularity.parseNozomi(Uint8List(3)), throwsFormatException);
    expect(() => HitomiPopularity.parseNozomi(Uint8List(0)), throwsFormatException);
  });
}
