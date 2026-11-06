import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/web_series_capture.dart';
import 'package:hyp_viewer/core/web_series_library.dart';
import 'package:hyp_viewer/core/web_viewer_store.dart';

WebSeriesCapture syntheticSeries({int count = 81}) {
  final entries = List.generate(count, (i) => {
    'url': '/webtoon/6549/chapter-' + (149 - i).toString(),
    'title': 'Sample series ' + (77 - i).toString() + '화',
    'order': 149 - i,
    'date': '2026.11.06',
  });
  return WebSeriesCapture.parse(jsonEncode({
    'url': 'https://series.example.org/webtoon/6549',
    'title': 'Sample series',
    'author': 'Author',
    'cover': 'https://cdn.example.org/cover.jpg',
    'episodes': entries,
  }))!;
}

void main() {
  test('series snapshot keeps 81 unique links and distinct displayed '
      'episode labels versus site data-index', () {
    final source = syntheticSeries();
    expect(source.episodes, hasLength(81));
    expect(source.episodes.first.siteOrder, 149);
    expect(source.episodes.first.episodeNumber, 77);
    expect(source.episodes.first.title, contains('77화'));
    expect(source.episodes.last.siteOrder, 69);
    expect(source.title, 'Sample series');
    expect(source.author, 'Author');
    expect(source.coverUrl?.host, 'cdn.example.org');
  });

  test('only already-present, same-site public HTTPS episode links '
      'are allowed, deduplicated by URL', () {
    final result = WebSeriesCapture.parse(jsonEncode({
      'url': 'https://series.example.org/webtoon/6549',
      'title': 'Test',
      'episodes': [
        {'url': '/webtoon/6549/chapter-1', 'title': '1화', 'order': 1},
        {'url': '/webtoon/6549/chapter-1', 'title': '1화 mirror', 'order': 2},
        {'url': 'https://other.example.org/chapter', 'title': 'wrong site', 'order': 3},
        {'url': 'http://series.example.org/untrusted', 'title': 'HTTP', 'order': 4},
        {'url': 'https://127.0.0.1/', 'title': 'local', 'order': 5},
        {'url': 'https://series.example.org/webtoon/6549', 'title': 'detail', 'order': 6},
      ],
    }));
    expect(result, isNotNull);
    expect(result!.episodes, hasLength(1));
    expect(result.episodes.single.episodeNumber, 1);
  });

  test('refresh merges new chapters without losing saved progress '
      'or already queued chapters', () {
    final record = WebSeriesRecord.fromCapture(syntheticSeries(count: 2));
    final saved = record.episodes[0]..state = 'saved'..workId = '123';
    final queued = record.episodes[1]..state = 'queued';
    final updated = WebSeriesCapture.parse(jsonEncode({
      'url': record.url, 'title': 'Updated Series', 'author': 'New Author',
      'episodes': [
        {'url': saved.url, 'title': '77화', 'order': 149},
        {'url': queued.url, 'title': '76화', 'order': 148},
        {'url': '/webtoon/6549/chapter-150', 'title': '78화', 'order': 150},
      ],
    }))!;
    expect(record.merge(updated), 1);
    expect(record.episodes, hasLength(3));
    expect(record.episodes.first.number, 78);
    expect(record.episode(saved.url)?.workId, '123');
    expect(record.episode(saved.url)?.state, 'saved');
    expect(record.episode(queued.url)?.state, 'queued');
    expect(record.nextQueued?.url, queued.url);
  });

  test('WEB series and selected episode queue survive process recreation '
      'without affecting HYP gallery', () async {
    final temp = await Directory.systemTemp.createTemp('web-series-');
    try {
      final store = WebViewerStore(baseDirectory: temp);
      final source = syntheticSeries(count: 4);
      expect(await store.saveSeries(source), 4);
      expect(await store.queueSeriesEpisodes(source.url.toString(), [
        source.episodes[0].url.toString(),
        source.episodes[2].url.toString(),
      ]), 2);
      expect(store.getSeries(source.url.toString())?.queued, 2);
      store.dispose();
      final restored = WebViewerStore(baseDirectory: temp);
      await restored.load();
      final group = restored.getSeries(source.url.toString());
      expect(group?.queued, 2);
      expect(group?.episodes.length, 4);
      expect(restored.works, isEmpty);
      final root = await restored.root;
      expect(root.path, contains('web_viewer'));
      restored.dispose();
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('interrupted chapter resets to queued metadata for browser rescan',
      () {
    final record = WebSeriesEpisodeRecord.fromJson({
      'url': 'https://series.example.org/chapter-3',
      'title': '3화', 'order': 3,
      'state': 'downloading',
    });
    expect(record.state, 'queued');
  });

  test('grouping a previously saved WEB work preserves reading progress',
      () {
    final work = WebSavedWork('123', 'Chapter 1', 'Author',
      'https://series.example.org/chapter-1', '', 12, 8,
      DateTime.utc(2026, 11, 6));
    final grouped = work.grouped('https://series.example.org/series-1',
      'https://series.example.org/chapter-1');
    expect(grouped.currentPage, 8);
    expect(grouped.seriesUrl, contains('series-1'));
    expect(grouped.episodeUrl, contains('chapter-1'));
    expect(grouped.withPage(9).seriesUrl, grouped.seriesUrl);
  });

  test('series DOM adapter targets detail rows, not banner images', () {
    final source = WebSeriesCapture.captureJavaScript;
    expect(source, contains(".serial-list .list-body"));
    expect(source, contains("li.list-item"));
    expect(source, contains("a.item-subject[href]"));
    expect(source, contains("data-index"));
    expect(source, contains(".theme-detail-title-line"));
    expect(source, contains("target.origin !== location.origin"));
  });
}
