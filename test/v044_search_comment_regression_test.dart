import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/online_search.dart';
import 'package:hyp_viewer/core/title_alias_index.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/core/work_editions.dart';
import 'package:hyp_viewer/core/youtube.dart';

void main() {
  test('literal English/Korean words in a work title are never stripped', () {
    expect(WorkEditions.originalTitle('The English Teacher'),
        contains('english'));
    expect(WorkEditions.originalTitle('Korean Love'), contains('korean'));
    expect(WorkEditions.originalTitle('A Title [Korean]'),
        WorkEditions.originalTitle('A Title'));
    final preferred = [
      WorkEntry.create(workId: '111111').copyWith(sourceLanguage: 'ja'),
      WorkEntry.create(workId: '222222').copyWith(sourceLanguage: 'ko'),
    ];
    expect(WorkEditions.preferred(preferred, 'korean').workId, '222222');
  });

  test('edition query budget keeps artist, circle and series evidence', () {
    final work = WorkEntry.create(
      workId: '111111', title: 'Main Title', author: 'Maker',
      titleAliases: List.generate(35, (index) => 'Alias $index'),
    ).copyWith(sourceGroup: 'Studio', sourceSeries: 'Franchise');
    final lookup = TitleAliasIndex.fromLibrary([work]);
    final queries = lookup.queriesFor(work, entered: 'Main Title', limit: 12);
    expect(queries.length, lessThanOrEqualTo(12));
    expect(queries, contains('artist:Maker'));
    expect(queries, contains('group:Studio'));
    expect(queries, contains('series:Franchise'));
  });

  test('translated alternatives get their own scoped metadata queries', () {
    final planned = OnlineWorkSearch.planQueries('Original | 한국어판');
    expect(planned.map((entry) => entry.$2), contains('artist:Original'));
    expect(planned.map((entry) => entry.$2), contains('artist:한국어판'));
    expect(planned.map((entry) => entry.$2), contains('series:한국어판'));
    expect(planned.length, lessThanOrEqualTo(16));
  });

  test('search merges richer metadata for repeated IDs and ranks title',
      () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      final query = (jsonDecode(request.body)['query'] as List).first as String;
      seen.add(query);
      if (query == 'Pochi') {
        return http.Response(jsonEncode({'results': [
          {'id': 111, 'title': 'Unrelated Work'},
          {'id': 222, 'title': 'Pochi'},
        ], 'count': 2}), 200);
      }
      if (query == 'artist:Pochi') {
        return http.Response(jsonEncode({'results': [
          {'id': 111, 'title': 'Unrelated Work',
           'artists': ['Pochi'], 'aliases': ['Another Name'],
           'language': 'japanese'},
        ], 'count': 1}), 200);
      }
      return http.Response(jsonEncode({'results': [], 'count': 0}), 200);
    });
    final result = await OnlineWorkSearch(client).searchUnified('Pochi');
    expect(seen, contains('artist:Pochi'));
    expect(result.works.length, 2);
    expect(result.works.first.workId, '222');
    final duplicate = result.works.firstWhere((w) => w.workId == '111');
    expect(duplicate.artists, ['Pochi']);
    expect(duplicate.titleAliases, contains('Another Name'));
    expect(duplicate.language, 'japanese');
    client.close();
  });

  Map<String, Object?> apiComment(String text) => {
    'snippet': {
      'topLevelComment': {'snippet': {'textDisplay': text}}
    }
  };

  test('optional YouTube API key fetches subsequent public comment pages',
      () async {
    final pages = <String?>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/videos')) {
        return http.Response(jsonEncode({'items': [
          {'snippet': {'title': 'Video', 'description': 'Source ID 2711759'}}
        ]}), 200);
      }
      pages.add(request.url.queryParameters['pageToken']);
      if (pages.length == 1) {
        return http.Response(jsonEncode({
          'items': [apiComment('Number 2711759')],
          'nextPageToken': 'p2',
        }), 200);
      }
      return http.Response(jsonEncode({
        'items': [apiComment('Number 2711759'), apiComment('Other 333333')],
      }), 200);
    });
    final result = await YoutubeClient(client).fetch('abcD123xyZ0', 'key');
    expect(pages, [null, 'p2']);
    expect(result.comments, ['Number 2711759', 'Other 333333']);
    expect(result.mayBeIncomplete, false);
    client.close();
  });

  test('API comment cap is reported as partial and not silently complete',
      () async {
    var pages = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/videos')) {
        return http.Response(jsonEncode({'items': [
          {'snippet': {'title': 'Video', 'description': 'Source ID'}}
        ]}), 200);
      }
      pages++;
      return http.Response(jsonEncode({
        'items': [apiComment('Comment $pages')],
        'nextPageToken': 'token-$pages',
      }), 200);
    });
    final result = await YoutubeClient(client).fetch('abcD123xyZ0', 'key');
    expect(pages, 5);
    expect(result.comments.length, 5);
    expect(result.mayBeIncomplete, true);
    client.close();
  });
}
