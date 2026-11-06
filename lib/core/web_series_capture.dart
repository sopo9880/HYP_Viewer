import 'dart:convert';

import 'online_gallery.dart';

/// One episode link found on a user-opened series detail page.
class WebSeriesEpisodeCandidate {
  final Uri url;
  final String title;
  final String publishedAt;
  final int siteOrder;
  final int? episodeNumber;

  const WebSeriesEpisodeCandidate({
    required this.url,
    required this.title,
    required this.publishedAt,
    required this.siteOrder,
    required this.episodeNumber,
  });

  Map<String, dynamic> toJson() => {
    'url': url.toString(),
    'title': title,
    'date': publishedAt,
    'order': siteOrder,
    'episodeNumber': episodeNumber,
  };
}

class WebSeriesCapture {
  final Uri url;
  final String title;
  final String author;
  final Uri? coverUrl;
  final List<WebSeriesEpisodeCandidate> episodes;

  const WebSeriesCapture({
    required this.url, required this.title, required this.author,
    required this.coverUrl, required this.episodes,
  });

  static String _plain(Object? value, [int max = 250]) {
    if (value is! String) return '';
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > max ? text.substring(0, max) : text;
  }

  /// Only links explicitly listed in the current, already loaded DOM
  /// are considered. No hidden APIs, pagination probing or auth bypass.
  static WebSeriesCapture? parse(Object? raw) {
    try {
      Object? data = raw;
      for (var i = 0; i < 2 && data is String; i++) {
        data = jsonDecode(data);
      }
      if (data is! Map) return null;
      final source = Uri.tryParse(_plain(data['url'], 2048));
      if (source == null || !OnlineSourcePolicy.isHttpsPublic(source)) {
        return null;
      }
      final rawEpisodes = data['episodes'];
      if (rawEpisodes is! List) return null;
      final unique = <String>{};
      final episodes = <WebSeriesEpisodeCandidate>[];
      for (final item in rawEpisodes.take(1200)) {
        if (item is! Map) continue;
        try {
          final rawUrl = _plain(item['url'], 2048);
          if (rawUrl.isEmpty) continue;
          final uri = source.resolve(rawUrl);
          if (!OnlineSourcePolicy.isHttpsPublic(uri) ||
              uri.host != source.host || uri.path == source.path) continue;
          // Links with credentials or session-bearing query parameters
          // should not be persisted as a reusable episode bookmark.
          if (uri.queryParameters.keys.any((key) =>
              RegExp(r'token|auth|session|signature|password|'
                  r'credential|nonce|api_key|jwt',
                  caseSensitive: false).hasMatch(key))) continue;
          if (!unique.add(uri.toString())) continue;
          final rawOrder = item['order'];
          final order = rawOrder is num ? rawOrder.toInt()
              : int.tryParse('$rawOrder') ?? (episodes.length + 1);
          if (order < 1 || order > 10000000) continue;
          final title = _plain(item['title']);
          final numberMatch = RegExp(r'(\d{1,5})\s*화').allMatches(title);
          final episodeNumber = numberMatch.isEmpty ? null
              : int.tryParse(numberMatch.last.group(1) ?? '');
          episodes.add(WebSeriesEpisodeCandidate(
            url: uri, title: title.isEmpty ? 'Episode $order' : title,
            publishedAt: _plain(item['date'], 60), siteOrder: order,
            episodeNumber: episodeNumber,
          ));
        } catch (_) {
          // One malformed row must not invalidate all available episodes.
          continue;
        }
      }
      if (episodes.isEmpty) return null;
      episodes.sort((a, b) => b.siteOrder.compareTo(a.siteOrder));
      Uri? cover;
      final rawCover = _plain(data['cover'], 2048);
      if (rawCover.isNotEmpty) {
        final candidate = source.resolve(rawCover);
        if (OnlineSourcePolicy.isHttpsPublic(candidate)) cover = candidate;
      }
      final title = _plain(data['title']);
      return WebSeriesCapture(
        url: source, title: title.isEmpty ? source.host : title,
        author: _plain(data['author']), coverUrl: cover,
        episodes: List.unmodifiable(episodes),
      );
    } catch (_) {
      return null;
    }
  }

  static const String captureJavaScript = r'''(function () {
    var list = document.querySelector('.serial-list .list-body');
    if (!list) return null;
    var canonical = document.querySelector('link[rel="canonical"]');
    var base = location.href;
    try {
      if (canonical && canonical.href) {
        var c = new URL(canonical.href, location.href);
        if (c.origin === location.origin && c.protocol === 'https:') {
          base = c.href;
        }
      }
    } catch (_) {}
    var rows = list.querySelectorAll('li.list-item');
    var episodes = [];
    for (var i = 0; i < rows.length && episodes.length < 1200; i++) {
      var row = rows[i], link = row.querySelector('a.item-subject[href]');
      if (!link) continue;
      try {
        var target = new URL(link.getAttribute('href'), location.href);
        if (target.protocol !== 'https:' || target.origin !== location.origin ||
            target.username || target.password) continue;
        var number = row.getAttribute('data-index');
        var order = Number(number);
        if (!Number.isInteger(order) || order < 1) order = i + 1;
        var date = row.querySelector('.wr-date');
        var title = (link.textContent || '').replace(/\s+/g, ' ').trim();
        episodes.push({
          url: target.href, title: title.slice(0, 250),
          order: order,
          date: (date && date.textContent || '').trim().slice(0, 60)
        });
      } catch (_) {}
    }
    var heading = document.querySelector('.theme-detail-title-line') ||
      document.querySelector('.page-title h2') ||
      document.querySelector('meta[property="og:title"]');
    var title = heading && (
      heading.content || heading.textContent || '') || document.title;
    var author = '';
    var fields = document.querySelectorAll('.theme-detail-info-row');
    for (var j = 0; j < fields.length; j++) {
      var label = fields[j].querySelector('.theme-detail-info-label');
      var value = fields[j].querySelector('.theme-detail-info-value');
      if (label && value && /작가|author/i.test(label.textContent || '')) {
        author = (value.textContent || '').trim(); break;
      }
    }
    var cover = document.querySelector('.view-img img');
    return JSON.stringify({
      url: base, title: String(title).replace(/\s+/g, ' ').trim().slice(0, 250),
      author: author.slice(0, 250),
      cover: cover && cover.src || '',
      episodes: episodes
    });
  })();''';
}
