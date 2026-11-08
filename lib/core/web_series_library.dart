import 'web_series_capture.dart';

/// Persistent metadata only. No cookies, temporary tokens or signed
/// image URLs are saved in the on-disk WEB series library.
class WebSeriesEpisodeRecord {
  final String url;
  String title;
  String date;
  int order;
  int? number;
  String state;
  String? workId;
  String? error;

  WebSeriesEpisodeRecord({
    required this.url, required this.title, required this.date,
    required this.order, required this.number, this.state = 'available',
    this.workId, this.error,
  });

  factory WebSeriesEpisodeRecord.fromCandidate(
      WebSeriesEpisodeCandidate candidate) => WebSeriesEpisodeRecord(
    url: candidate.url.toString(), title: candidate.title,
    date: candidate.publishedAt, order: candidate.siteOrder,
    number: candidate.episodeNumber,
  );

  factory WebSeriesEpisodeRecord.fromJson(Map<String, dynamic> data) {
    final raw = (data['state'] ?? 'available').toString();
    final state = const {
      'available', 'queued', 'saved', 'failed', 'needs_browser'
    }.contains(raw) ? raw : 'queued';
    return WebSeriesEpisodeRecord(
      url: (data['url'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      date: (data['date'] ?? '').toString(),
      order: (data['order'] is num ? (data['order'] as num).toInt() : 0),
      number: data['number'] is num ? (data['number'] as num).toInt() : null,
      state: state,
      workId: data['workId'] is String ? data['workId'] as String : null,
      error: data['error'] is String ? data['error'] as String : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url, 'title': title, 'date': date, 'order': order,
    'number': number, 'state': state, 'workId': workId, 'error': error,
  };
}

class WebSeriesRecord {
  final String url;
  String title;
  String author;
  String coverUrl;
  DateTime checkedAt;
  bool titleCustomized;
  final List<WebSeriesEpisodeRecord> episodes;

  WebSeriesRecord({
    required this.url, required this.title, required this.author,
    required this.coverUrl, required this.checkedAt, required this.episodes,
    this.titleCustomized = false,
  });

  factory WebSeriesRecord.fromCapture(WebSeriesCapture captured) =>
      WebSeriesRecord(
        url: captured.url.toString(), title: captured.title,
        author: captured.author, coverUrl: captured.coverUrl?.toString() ?? '',
        checkedAt: DateTime.now(),
        episodes: captured.episodes
            .map(WebSeriesEpisodeRecord.fromCandidate).toList(),
      );

  factory WebSeriesRecord.fromJson(Map<String, dynamic> data) {
    final records = (data['episodes'] as List? ?? [])
        .whereType<Map>()
        .map((e) => WebSeriesEpisodeRecord.fromJson(
            Map<String, dynamic>.from(e)))
        .take(1200).toList();
    records.sort((a, b) => b.order.compareTo(a.order));
    return WebSeriesRecord(
      url: (data['url'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      author: (data['author'] ?? '').toString(),
      coverUrl: (data['coverUrl'] ?? '').toString(),
      checkedAt: DateTime.tryParse((data['checkedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      titleCustomized: data['titleCustomized'] == true,
      episodes: records,
    );
  }

  /// Refresh live listing without dropping saved works or missing older
  /// rows due to partial lists/pagination.
  int merge(WebSeriesCapture captured) {
    if (!titleCustomized) title = captured.title;
    author = captured.author;
    coverUrl = captured.coverUrl?.toString() ?? coverUrl;
    checkedAt = DateTime.now();
    final known = {for (final item in episodes) item.url: item};
    var added = 0;
    for (final candidate in captured.episodes) {
      final url = candidate.url.toString();
      final existing = known[url];
      if (existing == null) {
        final record = WebSeriesEpisodeRecord.fromCandidate(candidate);
        episodes.add(record);
        known[url] = record;
        added++;
      } else {
        existing.title = candidate.title;
        existing.date = candidate.publishedAt;
        existing.order = candidate.siteOrder;
        existing.number = candidate.episodeNumber;
      }
    }
    episodes.sort((a, b) => b.order.compareTo(a.order));
    return added;
  }

  WebSeriesEpisodeRecord? episode(String url) {
    for (final item in episodes) {
      if (item.url == url) return item;
    }
    return null;
  }

  int get completed => episodes.where((e) => e.state == 'saved').length;
  int get queued => episodes.where((e) => e.state == 'queued').length;
  int get failures => episodes.where((e) =>
      e.state == 'failed' || e.state == 'needs_browser').length;

  WebSeriesEpisodeRecord? get nextQueued {
    for (final item in episodes.reversed) {
      if (item.state == 'queued') return item;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'url': url, 'title': title, 'author': author, 'coverUrl': coverUrl,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'titleCustomized': titleCustomized,
    'episodes': episodes.map((e) => e.toJson()).toList(),
  };
}
