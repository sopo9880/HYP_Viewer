import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/hitomi_reader_link.dart';

void main() {
  test('first page uses trailing-dash #1- fragment', () {
    expect(
      HitomiReaderLink.forWork('2711759').toString(),
      'https://hitomi.la/reader/2711759.html#1-',
    );
  });

  test('page two onward uses a page and next-page pair', () {
    expect(
      HitomiReaderLink.forWork('2711759', page: 2).toString(),
      'https://hitomi.la/reader/2711759.html#2-3',
    );
    expect(
      HitomiReaderLink.forWork('12345', page: 42).toString(),
      'https://hitomi.la/reader/12345.html#42-43',
    );
  });

  test('rejects non-numeric work IDs and invalid page numbers', () {
    expect(() => HitomiReaderLink.forWork('27117a9'), throwsFormatException);
    expect(() => HitomiReaderLink.forWork('../2711759'), throwsFormatException);
    expect(() => HitomiReaderLink.forWork(''), throwsFormatException);
    expect(
      () => HitomiReaderLink.forWork('2711759', page: 0),
      throwsFormatException,
    );
    expect(
      () => HitomiReaderLink.forWork('2711759', page: 1000001),
      throwsFormatException,
    );
  });
}
