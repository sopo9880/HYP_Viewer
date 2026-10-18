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
    expect(result.fieldTotals['artist'], 1);
    expect(result.warnings, isEmpty);
    client.close();
  });

  test('advanced query only searches its specified field', () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      seen.add((jsonDecode(request.body)['query'] as List).first as String);
      return http.Response(jsonEncode({
        'results': [{'id': 111, 'title': 'Pochi',
                     'artists': ['Pochi']}], 'count': 1,
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

  test('multiple long verified aliases are separately validated', () {
    final first = List.filled(80, 'A').join();
    final second = List.filled(80, 'B').join();
    final plan = OnlineWorkSearch.planQueries(first + ' | ' + second);
    expect(plan.take(2).map((e) => e.$2), [first, second]);
    expect(plan.every((e) => e.$2.length <= 150), true);
  });

  test('empty first mirror retries a second independent index', () async {
    final hosts = <String>[];
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      return http.Response(jsonEncode({
        'results': request.url.host == 'inst.psec.dev'
            ? [] : [{'id': 991122, 'title': 'Second index result'}],
        'count': request.url.host == 'inst.psec.dev' ? 0 : 1,
      }), 200);
    });
    final found = await OnlineWorkSearch(client).search('Second index');
    expect(found.works.single.workId, '991122');
    expect(hosts, ['inst.psec.dev', 'heliotrope.saebasol.org']);
    client.close();
  });

  test('rich title results skip unrelated metadata queries', () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      final query = (jsonDecode(request.body)['query'] as List).first as String;
      seen.add(query);
      return http.Response(jsonEncode({
        'results': List.generate(9, (i) => {
          'id': 100001 + i, 'title': 'Direct story'
        }),
        'count': 9,
      }), 200);
    });
    await OnlineWorkSearch(client).searchUnified('Direct story');
    expect(seen, ['Direct story']);
    client.close();
  });

  test('plain gallery number avoids metadata field expansion', () {
    expect(OnlineWorkSearch.planQueries('1234567'),
        [('general', '1234567')]);
  });

  test('pochi artist metadata appears as an artist facet even when the '
      'broad title round skips artist queries', () async {
    final queried = <String>[];
    final client = MockClient((request) async {
      final query = (jsonDecode(request.body)['query'] as List).first as String;
      queried.add(query);
      return http.Response(jsonEncode({
        'results': [
          {'id': 1012074, 'title': 'Ane Naru Mono 4',
           'artists': ['pochi'], 'language': 'korean'},
          for (var i = 0; i < 8; i++)
            {'id': 1002000 + i, 'title': 'Pochi book ' + i.toString()},
        ],
        // Provider count may include overlaps and must not be the facet count.
        'count': 39,
      }), 200);
    });
    final found = await OnlineWorkSearch(client)
        .searchUnified('pochi', language: 'korean');
    expect(queried, ['pochi']);
    expect(found.total, 9);
    expect(found.fieldTotals['artist'], 1);
    expect(found.fieldTotals['general'], 8);
    expect(found.matchedFields['1012074'], contains('artist'));
    expect(found.matchedFields['1012074'], isNot(contains('general')));
    expect(OnlineWorkSearch.facetCounts(found.works, found.matchedFields),
        found.fieldTotals);
    client.close();
  });

  test('one gallery returned by multiple fields counts only once per facet',
      () async {
    final client = MockClient((request) async {
      final query = (jsonDecode(request.body)['query'] as List).first as String;
      return http.Response(jsonEncode({
        'results': [
          {'id': 808808, 'title': 'Unrelated',
           'artists': ['pochi'], 'tags': ['female:pochi']},
        ],
        'count': query == 'pochi' ? 100 : 200,
      }), 200);
    });
    final found = await OnlineWorkSearch(client).searchUnified('pochi');
    expect(found.total, 1);
    expect(found.fieldTotals['artist'], 1);
    expect(found.fieldTotals['female'], 1);
    expect(found.fieldTotals['tag'], 1);
    expect(found.matchedFields['808808'], contains('artist'));
    client.close();
  });

  test('community mirror object metadata yields creator and gender facets', () {
    final work = OnlineSearchWork.fromJson({
      'id': 876543,
      'title': 'An unrelated title',
      'artists': [{'artist': 'pochi'}],
      'groups': [{'group': 'Circle'}],
      'tags': [
        {'tag': 'pochi', 'female': true},
        {'tag': 'other', 'male': true},
      ],
    });
    expect(work.artists, ['pochi']);
    expect(work.groups, ['Circle']);
    expect(work.tags, contains('female:pochi'));
    expect(OnlineWorkSearch.metadataFields(work, 'pochi'),
        containsAll(['artist', 'tag', 'female']));
    expect(OnlineWorkSearch.metadataFields(work, 'pochi'),
        isNot(contains('male')));
  });

  test('direct field lookup keeps source evidence if mirror omits artist',
      () {
    const remote = OnlineSearchWork(workId: '1012074',
        title: 'Ane Naru Mono 4');
    expect(OnlineWorkSearch.metadataFields(remote, 'pochi'), isEmpty);
    final combined = OnlineWorkSearch.combineWorks(remote,
        const OnlineSearchWork(workId: '1012074',
            title: 'Ane Naru Mono 4', artists: ['pochi']));
    expect(OnlineWorkSearch.metadataFields(combined, 'pochi'),
        contains('artist'));
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
