import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/reader_tap_zones.dart';

void main() {
  test('physical left/right follows selected next direction', () {
    int zone(double x, {bool rtl = false, bool vertical = false}) =>
      readerTapDelta(pointX: x, pointY: 100,
        width: 100, height: 200, vertical: vertical, reverse: rtl);
    // "next direction = left" moves to the NEXT work/page at left.
    expect(zone(10), 1);
    expect(zone(90), -1);
    // "next direction = right" reverses the physical navigation.
    expect(zone(10, rtl: true), -1);
    expect(zone(90, rtl: true), 1);
    expect(zone(30), 0);
    expect(zone(50), 0);
    expect(zone(70), 0);
    expect(zone(10, vertical: true), -1);
    expect(zone(90, vertical: true), 1);
    expect(zone(10, rtl: true, vertical: true), -1);
  });
}
