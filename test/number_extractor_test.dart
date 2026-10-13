import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/number_extractor.dart';

void main() {
  test('date-like code is concatenated', () {
    final c = NumberExtractor.extract('3684년 6월 22일에 세이코 씨를 만났다네요');
    expect(c.first.code, '3684622');
  });

  test('ten-thousands line yields digits without AI', () {
    final c = NumberExtractor.extract('제목: Urahara\n작가: Liyoosa\n수영 시간: 271만 1759시간');
    expect(c.first.code, '2711759');
  });

  test('title digits do not contaminate a separate date line', () {
    final c = NumberExtractor.extract(
      '제목: 6월의 그라데이션\n작가: Tsukako\n교제 날짜: 29510년 7월 2일',
    );
    expect(c.any((e) => e.code == '2951072'), true);
    expect(c.any((e) => e.code == '62951072'), false);
  });

  test('unrelated long digit strings are not blindly joined', () {
    final c = NumberExtractor.extract('2025년 24호, 사용자: 15843119');
    expect(c.any((e) => e.code == '20252415843119'), false);
    expect(c.any((e) => e.code == '15843119'), true);
  });

  test('no digits yields no candidate', () {
    expect(NumberExtractor.extract('작품명과 작가만 있습니다'), isEmpty);
  });

  test('pads a short remainder following 만', () {
    final c = NumberExtractor.extract('271만 59시간');
    expect(c.any((e) => e.code == '2710059'), true);
  });
}
