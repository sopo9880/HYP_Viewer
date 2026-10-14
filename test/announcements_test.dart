import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/announcements.dart';

void main() {
  test('fixed GitHub feed parses announcements without any auth token',
      () async {
    final client = MockClient((req) async {
      expect(req.url, AnnouncementService.feedUrl);
      expect(req.url.host, 'raw.githubusercontent.com');
      expect(req.headers.containsKey('Authorization'), false);
      return http.Response(jsonEncode({
        'schemaVersion': 1,
        'announcements': [
          {
            'id': 'note_20261014',
            'title': '새 기능 안내',
            'message': '오프라인 다운로드 지원',
            'publishedAt': '2026-10-14T03:00:00Z',
          },
        ],
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final feed = await AnnouncementService(client).load();
    expect(feed.single.id, 'note_20261014');
    expect(feed.single.title, '새 기능 안내');
    client.close();
  });

  test('rejects oversized or duplicated untrusted notices', () async {
    final duplicated = {
      'schemaVersion': 1, 'announcements': [
        for (var i = 0; i < 2; i++)
          {'id': 'same_notice', 'title': 'A', 'message': 'B',
            'publishedAt': '2026-10-14T03:00:00Z'},
      ],
    };
    final client = MockClient((req) async =>
      http.Response(jsonEncode(duplicated), 200));
    await expectLater(AnnouncementService(client).load(), throwsFormatException);
    client.close();
  });
}
