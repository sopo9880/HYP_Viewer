import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/hitomi_web_search.dart';

void main() {
  test('search URL encodes the unkeyed Hitomi site query', () {
    expect(HitomiWebSearch.searchUri('artist:pochi').toString(),
        'https://hitomi.la/search.html?artist%3Apochi');
    expect(HitomiWebSearch.searchUri('hello world').toString(),
        'https://hitomi.la/search.html?hello%20world');
    expect(() => HitomiWebSearch.searchUri(''), throwsFormatException);
  });

  test('parses only trusted gallery links and removes duplicate work IDs', () {
    final payload = jsonEncode({
      'url': 'https://hitomi.la/search.html?artist%3Apochi',
      'items': [
        {'url': 'https://hitomi.la/doujinshi/a-title-1234567.html',
         'title': ' A Title '},
        {'url': '/galleries/1234567.html', 'title': 'duplicate'},
        {'url': '/reader/7654321.html', 'title': 'Another'},
        {'url': 'https://evil.test/galleries/2222222.html',
         'title': 'attacker'},
        {'url': 'https://hitomi.la/tag/general-japanese-1.html',
         'title': 'a tag'},
        {'url': 'https://hitomi.la/galleries/9999999.html',
         'title': ''},
      ],
    });
    final items = HitomiWebSearch.parseCapture(payload);
    expect(items.map((w) => w.workId).toList(),
        ['1234567', '7654321', '9999999']);
    expect(items.first.title, 'A Title');
    expect(items.last.title, '작품 9999999');
  });

  test('does not trust forged origins, credentials or non-default ports', () {
    final items = [
      {'url': 'https://hitomi.la/galleries/1234567.html',
        'title': 'Hidden'},
    ];
    expect(HitomiWebSearch.parseCapture({
      'url': 'https://evil.test/search.html', 'items': items,
    }), isEmpty);
    expect(HitomiWebSearch.galleryId(
      Uri.parse('https://hitomi.la.evil.test/galleries/1234567.html')), isNull);
    expect(HitomiWebSearch.galleryId(
      Uri.parse('https://user@hitomi.la/galleries/1234567.html')), isNull);
    expect(HitomiWebSearch.galleryId(
      Uri.parse('http://hitomi.la/galleries/1234567.html')), isNull);
    // Dart Uri canonicalizes an explicit default HTTPS port (443) into
    // the normal same-origin URL. A non-default port must still be rejected.
    expect(HitomiWebSearch.galleryId(
      Uri.parse('https://hitomi.la:443/galleries/1234567.html')),
      '1234567');
    expect(HitomiWebSearch.galleryId(
      Uri.parse('https://hitomi.la:444/galleries/1234567.html')), isNull);
  });

  test('rejects numeric noise and malformed snapshots', () {
    expect(HitomiWebSearch.galleryId(
      Uri.parse('https://hitomi.la/tag/cat-all-1234567.html')), isNull);
    expect(HitomiWebSearch.galleryId(
      Uri.parse('https://hitomi.la/artist/pochi-all-1234567.html')), isNull);
    expect(HitomiWebSearch.galleryId(
      Uri.parse('https://hitomi.la/manga/a-gallery-1234567.html')),
      '1234567');
    expect(HitomiWebSearch.parseCapture('{bad JSON'), isEmpty);
    expect(HitomiWebSearch.parseCapture({'url': 'https://hitomi.la'}), isEmpty);
    expect(HitomiWebSearch.parseCapture({
      'url': 'https://hitomi.la/search.html?',
      'items': [{'url': 'https://hitomi.la/galleries/123456.html',
          'title': 'Valid'}],
    }), hasLength(1));
  });
}
