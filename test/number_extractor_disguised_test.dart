import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/number_extractor.dart';

void main() {
  test('disguised multi-part IDs exclude episode digits and background line', () {
    const comment = '''
#만화 #일본만화
izure - 멋대로 눌러앉은 아싸 유령의 몸을 막 쓰는 이야기 3
시대적 배경은 3419년 1월 20일 입니다.
1편 - 2900년 7월 56일
2편 - 317시간 28분 01초
3편 - 341/912/0
1편부터 감상하는거 추천
''';
    final results = NumberExtractor.extract(comment);
    expect(results.map((e) => e.code).toSet(),
        {'2900756', '3172801', '3419120'});
    expect(results.map((e) => e.episode).toSet(),
        {'1편', '2편', '3편'});
    expect(results.any((e) => e.code == '12900756'), false);
    expect(results.any((e) => e.code == '23172801'), false);
    expect(results.any((e) => e.code == '33419120'), false);
  });

  test('multiple episodes in one line split before composing candidates', () {
    final candidates = NumberExtractor.extract(
        '1편 271만 1759시간, 2편 295만 1072시간');
    expect(candidates.map((e) => e.code).toSet(),
        {'2711759', '2951072'});
    expect(candidates.first.episode, '1편');
  });

  test('unrelated URLs and background numbers are not rejoined', () {
    final codes = NumberExtractor.extract(
      '시대적 배경은 3419년 1월 20일입니다.\n'
      '영상주소 https://youtube.com/shorts/abcdef12345\n'
      '3편 - https://hitomi.la/reader/3419120.html',
    );
    expect(codes.map((e) => e.code), ['3419120']);
  });
}
