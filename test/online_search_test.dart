import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/online_search.dart';

void main() {
  test('ignore explicit language conflicts without losing unknown records',
      () async {
    final client = MockClient((request) async =>
        http.Response(jsonEncode({
          'results': [
            {'id': 1001, 'title': 'Korean edition', 'language': 'ko'},
            {'id': 1002, 'title': 'Japanese edition', 'language': 'jpn'},
            {'id': 1003, 'title': 'Unknown language'},
          ],
          'count': 3,
        }), 200));
    final result = await OnlineWorkSearch(client).search(
        'Story', language: 'korean');
    expect(result.works.map((w) => w.workId), ['1001', '1003']);
    client.close();
  });


  test('unified search publishes results before slow categories finish',
      () async {
    final slow = Completer<http.Response>();
    final firstSeen = Completer<void>();
    final snapshots = <OnlineSearchResult>[];
    final client = MockClient((request) async {
      final query = (jsonDecode(request.body)['query'] as List).first as String;
      if (query == 'artist:Story') return slow.future;
      if (query == 'Story') {
        return http.Response(jsonEncode({
          'results': [{'id': 111111, 'title': 'Story'}],
          'count': 1,
        }), 200);
      }
      return http.Response(jsonEncode({'results': [], 'count': 0}), 200);
    });
    final pending = OnlineWorkSearch(client).searchUnified('Story',
      onPartial: (snapshot) {
        snapshots.add(snapshot);
        if (snapshot.works.any((work) => work.workId == '111111') &&
            !firstSeen.isCompleted) firstSeen.complete();
      });
    await firstSeen.future.timeout(const Duration(seconds: 5));
    // The slow creator lookup is still pending, but the title appears.
    expect(slow.isCompleted, false);
    expect(snapshots.last.works.single.workId, '111111');
    final early = snapshots.first;
    slow.complete(http.Response(jsonEncode({
      'results': [{'id': 222222, 'title': 'Creator match'}],
      'count': 1,
    }), 200));
    final completed = await pending;
    expect(completed.works.map((work) => work.workId).toSet(),
        {'111111', '222222'});
    expect(early.works.map((work) => work.workId),
        isNot(contains('222222')));
    client.close();
  });

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
  test('a plain term searches creator and circle and deduplicates overlaps', () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      final query = (jsonDecode(request.body)['query'] as List).first as String;
      seen.add(query);
      final id = query.startsWith('artist:') || query == 'Pochi' ? 100 : 101;
      return http.Response(jsonEncode({
        'results': [{'id': id, 'title': 'Pochi result'}],
        'count': 10,
      }), 200);
    });
    final result = await OnlineWorkSearch(client).searchUnified('Pochi');
    expect(seen, containsAll([
      'Pochi', 'artist:Pochi', 'group:Pochi',
      'series:Pochi', 'tag:Pochi',
      'female:Pochi', 'male:Pochi',
    ]));
    expect(result.works.map((entry) => entry.workId).toSet(),
        {'100', '101'});
    expect(result.total, 2);
    expect(result.fieldTotals['artist'], 10);
    expect(result.warnings, isEmpty);
    client.close();
  });

  test('advanced query only searches its specified field', () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      seen.add((jsonDecode(request.body)['query'] as List).first as String);
      return http.Response(jsonEncode({
        'results': [], 'count': 0,
      }), 200);
    });
    await OnlineWorkSearch(client).searchUnified(
        'artist:Pochi', language: 'japanese');
    expect(seen, ['artist:Pochi']);
    client.close();
  });

  test('query plan covers all supported categories without guessing count', () {
    expect(OnlineWorkSearch.planQueries('Pochi').map((e) => e.$1).toList(),
      ['general','artist','group','series','tag','female','male']);
    expect(OnlineWorkSearch.planQueries('artist:Pochi'),
      [('advanced','artist:Pochi')]);
    expect(OnlineWorkSearch.planQueries('Original | Translated')
      .map((entry) => entry.$2).toList().take(2),
      ['Original','Translated']);
  });

  test('international results prefer all-language provider only', () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      seen.add(request.url.host);
      return http.Response.bytes(utf8.encode(jsonEncode({'results': [
        {'id': 123456, 'title': '日本語', 'language': 'japanese'}
      ], 'count': 1})), 200, headers: {
        'content-type': 'application/json; charset=utf-8',
      });
    });
    final search = OnlineWorkSearch(client);
    final r = await search.search('日本語', language: 'japanese');
    expect(r.works.single.language, 'japanese');
    expect(seen, ['inst.psec.dev']);
    client.close();
  });

  test('international provider failure has explicitly limited fallback', () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      seen.add(request.url.host);
      if (request.url.host == 'inst.psec.dev') {
        return http.Response('temporarily unavailable', 503);
      }
      return http.Response(jsonEncode({
        'results': [{'id': 999, 'title': 'Fallback candidate',
                     'language': 'japanese'}],
        'count': 1,
      }), 200);
    });
    final response = await OnlineWorkSearch(client)
        .searchUnified('Fallback', language: 'japanese');
    expect(response.works.single.workId, '999');
    expect(seen.first, 'inst.psec.dev');
    expect(seen, contains('heliotrope.saebasol.org'));
    expect(response.warnings.join(' '), contains('누락'));
    client.close();
  });

  test('advanced query syntax and language selection', () {
    expect(OnlineWorkSearch.tokens('artist:creator', language: 'korean'),
        ['artist:creator', 'language:korean']);
    expect(OnlineWorkSearch.tokens('original | 한국어'),
        ['original | 한국어']);
  });
}
