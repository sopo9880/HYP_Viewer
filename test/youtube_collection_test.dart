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
