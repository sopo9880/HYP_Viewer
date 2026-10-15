import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/source_links.dart';
import 'package:hyp_viewer/core/youtube_collection.dart';

void main() {
  test('playlist parser offers individual videos and removes duplicates', () {
    final html = '<script>var ytInitialData = ' + jsonEncode({
      'contents': {'playlistVideoListRenderer': {'contents': [
        {'playlistVideoRenderer': {
          'videoId': 'abcD123xyZ0',
          'title': {'runs': [{'text': '첫 영상'}]}
        }},
        {'playlistVideoRenderer': {
          'videoId': 'abcD123xyZ0',
          'title': {'simpleText': 'duplicate'}
        }},
        {'playlistVideoRenderer': {
          'videoId': 'ZYX987abcD0',
          'title': {'simpleText': 'Second video'}
        }},
      ]}}
    }) + ';</script>';
    final items = YoutubeCollectionReader.extractFromHtml(html, playlist: true);
    expect(items.map((value) => value.videoId), ['abcD123xyZ0', 'ZYX987abcD0']);
    expect(items.first.title, '첫 영상');
  });

  test('explicit Load More uses only public page continuation', () async {
    const key = 'public-page-key';
    const token = 'CONTINUATION_TOKEN_abcdef';
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.host, 'www.youtube.com');
      if (request.method == 'GET') {
        final html = 'ytcfg.set(' + jsonEncode({
          'INNERTUBE_API_KEY': key,
          'INNERTUBE_CONTEXT': {'client': {
            'clientName': 'WEB', 'clientVersion': '2.20261001.00.00'
          }}
        }) + ');var ytInitialData=' + jsonEncode({
          'contents': [
            {'videoRenderer': {
              'videoId': 'abcD123xyZ0',
              'title': {'simpleText': 'First'}
            }},
            {'continuationItemRenderer': {
              'continuationEndpoint': {
                'continuationCommand': {'token': token}
              }
            }},
          ]
        }) + ';';
        return http.Response.bytes(utf8.encode(html), 200);
      }
      expect(request.method, 'POST');
      expect(request.url.path, '/youtubei/v1/browse');
      expect(request.url.queryParameters['key'], key);
      expect(jsonDecode(request.body)['continuation'], token);
      return http.Response(jsonEncode({
        'continuationContents': [
          {'videoRenderer': {
            'videoId': 'ZYX987abcD0',
            'title': {'simpleText': 'Next page'}
          }},
        ]
      }), 200);
    });
    final reader = YoutubeCollectionReader(client);
    final first = await reader.listFirst(
      SourceLink.parse('https://www.youtube.com/@example/videos')!);
    expect(first.hasMore, true);
    expect(first.videos.single.videoId, 'abcD123xyZ0');
    final next = await reader.listNext(first);
    expect(next.videos.single.videoId, 'ZYX987abcD0');
    expect(next.hasMore, false);
    expect(calls, 2);
    client.close();
  });

  test('selector requests only approved public YouTube host', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'www.youtube.com');
      return http.Response.bytes(utf8.encode('<script>ytInitialData=' +
          jsonEncode({'contents': [
            {'videoRenderer': {'videoId': 'abcD123xyZ0',
                'title': {'simpleText': 'Video'}}}
          ]}) + '</script>'), 200);
    });
    final link = SourceLink.parse('https://www.youtube.com/@example/videos')!;
    expect(link.kind, SourceKind.youtubeCollection);
    final results = await YoutubeCollectionReader(client).list(link);
    expect(results.single.url, 'https://www.youtube.com/watch?v=abcD123xyZ0');
    client.close();
  });
}
