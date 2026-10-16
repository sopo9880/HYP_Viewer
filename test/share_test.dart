import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/shares.dart';
import 'package:hyp_viewer/core/youtube.dart';

void main() {
  test('receives decoded Instagram caption without any URL', () {
    final shared = SharedShorts.normalizeIncoming(
        '만화방 on Instagram: "&#xb9cc;&#xd654;"');
    expect(shared, '만화방 on Instagram: "만화"');
  });

  test('share receiver rejects blank and excessively long text', () {
    expect(SharedShorts.normalizeIncoming('   '), isNull);
    expect(SharedShorts.normalizeIncoming(List.filled(262145, 'x').join()),
        isNull);
  });

  test('recognizes standard Shorts link', () {
    expect(ShortsLink.videoId('https://www.youtube.com/shorts/-MK_XG2aflo'), '-MK_XG2aflo');
  });
  test('parses URL embedded in Android share payload', () {
    expect(SharedShorts.findVideoUrl('제목\nhttps://youtube.com/shorts/LJxTpjO7IE4?feature=share\n친구에게 전송'),
      'https://www.youtube.com/shorts/LJxTpjO7IE4');
  });
  test('HTTP YouTube community share is safely upgraded', () {
    expect(SharedShorts.findSourceUrl(
        '게시물 http://youtube.com/post/Ugkxlt1Ces0kwMJyLR-sN8iBws3CSAVjbgmv?si=x'),
        'https://youtube.com/post/Ugkxlt1Ces0kwMJyLR-sN8iBws3CSAVjbgmv?si=x');
  });
  test('shared reels and community posts retain their source', () {
    expect(SharedShorts.findSourceUrl('공유 https://www.instagram.com/reel/ABC12345/'),
        'https://www.instagram.com/reel/ABC12345/');
    expect(SharedShorts.findSourceUrl('https://www.youtube.com/post/Ugkx1234567890'),
        'https://www.youtube.com/post/Ugkx1234567890');
  });
  test('rejects spoofed domains', () {
    expect(SharedShorts.findVideoUrl('https://youtube.com.attacker.tld/shorts/-MK_XG2aflo'), isNull);
  });
  test('rejects invalid text and video IDs', () {
    expect(SharedShorts.findVideoUrl('안녕 유튜브'), isNull);
    expect(ShortsLink.videoId('https://www.youtube.com/shorts/tooShort'), isNull);
  });
}
