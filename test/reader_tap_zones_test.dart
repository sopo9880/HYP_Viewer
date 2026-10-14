import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/reader_tap_zones.dart';

void main() {
  test('horizontal left/right screen taps follow physical swipe directions', () {
    int delta(double x, bool reverse) => readerTapDelta(
      pointX: x, pointY: 10, width: 100, height: 200,
      vertical: false, reverse: reverse);
    expect(delta(10, false), 1);
    expect(delta(90, false), -1);
    expect(delta(10, true), -1);
    expect(delta(90, true), 1);
  });

  test('vertical taps use top and bottom halves', () {
    int delta(double y, bool reverse) => readerTapDelta(
      pointX: 10, pointY: y, width: 100, height: 200,
      vertical: true, reverse: reverse);
    expect(delta(10, false), -1);
    expect(delta(190, false), 1);
    expect(delta(10, true), 1);
    expect(delta(190, true), -1);
  });
}
