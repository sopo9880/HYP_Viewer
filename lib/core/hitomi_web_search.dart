import 'dart:convert';

/// Works extracted only from public gallery links visible in the user's
/// Hitomi search WebView. No free-form numeric scraping or login bypassing.
class HitomiWebGallery {
  final String workId;
  final String title;

  const HitomiWebGallery({required this.workId, required this.title});
}

class HitomiWebSearch {
  static bool allowedOrigin(Uri? url) =>
      url != null &&
      url.scheme == 'https' &&
      url.userInfo.isEmpty &&
      !url.hasPort &&
      (url.host == 'hitomi.la' || url.host == 'www.hitomi.la');

  static Uri searchUri(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length > 150) {
      throw const FormatException('Search query must contain 1-150 characters');
    }
    // Hitomi uses the entire raw query component, not a q= parameter.
    return Uri.parse('https://hitomi.la/search.html?' +
        Uri.encodeComponent(trimmed));
  }

  static String? galleryId(Uri? uri) {
    if (!allowedOrigin(uri)) return null;
    final path = uri!.path;
    final explicit = RegExp(r'^/(?:galleries|reader)/([0-9]{5,12})\.html$')
        .firstMatch(path);
    // Index/filter pages can also end in numbers. Restrict slug URLs
    // to known gallery categories to avoid importing category-page numbers.
    final slug = RegExp(
      r'^/(?:doujinshi|manga|artistcg|gamecg|imageset|'
      r'western|non-h|anime|cosplay|cg)/[^/]+-([0-9]{5,12})\.html$')
        .firstMatch(path);
    return explicit?.group(1) ?? slug?.group(1);
  }

  static List<HitomiWebGallery> parseCapture(Object? response) {
    Object? parsed = response;
    // WebView returns a JSON string on some platforms and a decoded
    // JSON string on others.
    for (var i = 0; i < 2 && parsed is String; i++) {
      try {
        parsed = jsonDecode(parsed);
      } on FormatException {
        return const [];
      }
    }
    if (parsed is! Map) return const [];
    final currentPage = Uri.tryParse(parsed['url']?.toString() ?? '');
    if (!allowedOrigin(currentPage) || parsed['items'] is! List) {
      return const [];
    }
    final works = <String, HitomiWebGallery>{};
    for (final row in (parsed['items'] as List).take(160)) {
      if (row is! Map) continue;
      final rawLink = row['url'];
      if (rawLink is! String) continue;
      final candidate = Uri.tryParse(rawLink);
      if (candidate == null) continue;
      final url = currentPage!.resolveUri(candidate);
      final id = galleryId(url);
      if (id == null) continue;
      final rawTitle = row['title'];
      final title = rawTitle is String
          ? rawTitle.replaceAll(RegExp(r'\s+'), ' ').trim()
          : '';
      works.putIfAbsent(id, () => HitomiWebGallery(
        workId: id,
        title: title.length >= 2 && title.length <= 220
            ? title : '작품 $id',
      ));
      if (works.length >= 120) break;
    }
    return works.values.toList(growable: false);
  }

  /// Read gallery hyperlinks from rendered DOM, not random page numbers.
  /// The browser remains on the user's chosen public page. This script
  /// never clicks, submits, fetches, or accesses cookies/localStorage.
  static const String captureJavaScript = r'''(function () {
    var results = [];
    var seen = {};
    function goodLink(anchor) {
      if (!anchor || !anchor.href) return null;
      try {
        var link = new URL(anchor.href, document.baseURI);
        if (link.protocol !== 'https:' ||
            !['hitomi.la', 'www.hitomi.la'].includes(link.hostname) ||
            link.username || link.password || link.port) return null;
        var match = link.pathname.match(
          /^\/(?:galleries|reader)\/(\d{5,12})\.html$/);
        if (!match) match = link.pathname.match(
          /^\/(?:doujinshi|manga|artistcg|gamecg|imageset|western|non-h|anime|cosplay|cg)\/[^/]+-(\d{5,12})\.html$/);
        return match ? {id: match[1], url: link.href} : null;
      } catch (_) { return null; }
    }
    Array.prototype.forEach.call(document.querySelectorAll('a[href]'),
      function (anchor) {
        if (results.length >= 120) return;
        var item = goodLink(anchor);
        if (!item || seen[item.id]) return;
        var container = anchor.closest(
          '.gallery-content, .gallery, .gallery-item, article, li');
        var header = container && container.querySelector(
          '.gallery-title, .title, h1, h2, h3');
        var title = String(header && header.textContent ||
          anchor.getAttribute('title') || anchor.textContent || '')
          .replace(/\s+/g, ' ').trim().slice(0, 220);
        seen[item.id] = true;
        results.push({url: item.url, title: title});
      });
    return JSON.stringify({url: location.href, items: results});
  })();''';
}
