import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/social_share_text.dart';

void main() {
  test('decodes Instagram hex entities, emoji and decimal references', () {
    final decoded = SocialShareText.normalize(
        '&#xc624;&#xb298;&#xb3c4; &#xc554;&#xc0b4;&#xc790;&#xb294; '
        '&#xc8fc;&#xc6cc;&#xc628; &#xc18c;&#xb140;&#xb97c; '
        '&#x26cf;&#xfe0f; &#064; yakitomahawk');
    expect(decoded, '오늘도 암살자는 주워온 소녀를 ⛏️ @ yakitomahawk');
  });

  test('double-escaped entities and invalid codepoints are handled safely', () {
    expect(SocialShareText.decode('&amp;#xb9cc;&nbsp;&quot;A&quot;'),
        '만화 "A"');
    expect(SocialShareText.decode('&#x110000;'), '&#x110000;');
    expect(SocialShareText.decode('&#xD800;'), '&#xD800;');
  });

  test('extracts editable title and author hints', () {
    final hints = SocialShareText.hints(
        '순애 광부 on Instagram: "오늘도 암살자는 주워온 소녀를 좀처럼 이기지 못한다\n'
        '작가 : 八木戸マト [X:&#064; yakitomahawk ]"\n'
        '2,329 likes, 51 comments - sogo_3_ on October 6, 2026');
    expect(hints.title, '오늘도 암살자는 주워온 소녀를 좀처럼 이기지 못한다');
    expect(hints.author, '八木戸マト');
    expect(hints.caption, contains('작가 : 八木戸マト'));
  });

  test('a hashtag caption cannot masquerade as a work title', () {
    final hints = SocialShareText.hints(
        '만화방 on Instagram: "#만화방"\n1,537 likes, 40 comments');
    expect(hints.title, isEmpty);
    expect(hints.author, isEmpty);
  });
}
