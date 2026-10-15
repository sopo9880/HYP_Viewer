import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/online_search.dart';

void main() {
  test('public metadata search parses results and caps duplicates', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/hitomi/search');
      expect(request.url.queryParameters['offset'], '1');
      expect(jsonDecode(request.body)['query'], ['Yarasete']);
      return http.Response(jsonEncode({'results': [
        {'id': 100, 'title': 'Yarasete Yarutte Ittenno!',
         'artists': ['creator'], 'tags': ['tag:romance']},
        {'id': 100, 'title': 'duplicate'},
        {'id': 101, 'title': 'Yarasete Yarutte Ittenno! 2'}
      ], 'count': 2}), 200);
    });
    final service = OnlineWorkSearch(client);
    final result = await service.search('Yarasete');
    expect(result.total, 2);
    expect(result.works.map((w) => w.workId), ['100', '101']);
    expect(result.works.first.artists, ['creator']);
    client.close();
  });
  test('advanced query syntax and language selection', () {
    expect(OnlineWorkSearch.tokens('artist:creator', language: 'korean'),
        ['artist:creator', 'language:korean']);
    expect(OnlineWorkSearch.tokens('original | 한국어'),
        ['original']);
  });
}
