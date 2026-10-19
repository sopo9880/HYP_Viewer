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
    if (trimmed.length > 150) {
      throw const FormatException('Search query must be at most 150 characters');
    }
    // An empty manual search opens the Hitomi home page. Automatic
    // background website search remains gated on a nonempty query.
    if (trimmed.isEmpty) return Uri.parse('https://hitomi.la/');
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
      final cleanTitle = title.length >= 2 && title.length <= 220
          ? title : '작품 $id';
      final previous = works[id];
      if (previous == null ||
          (previous.title == '작품 $id' && cleanTitle != '작품 $id')) {
        works[id] = HitomiWebGallery(workId: id, title: cleanTitle);
      }
      if (works.length >= 120) break;
    }
    return works.values.toList(growable: false);
  }

  /// Read gallery hyperlinks from rendered DOM, not random page numbers.
  /// The browser remains on the user's chosen public page. This script
  /// never clicks, submits, fetches, or accesses cookies/localStorage.
  static const String captureJavaScript = r'''(function () {
    var results = [];
    var byId = {};
    function goodLink(anchor) {
      if (!anchor || !anchor.href) return null;
      try {
        var link = new URL(anchor.href, document.baseURI);
        if (link.protocol !== 'https:' ||
            !['hitomi.la', 'www.hitomi.la'].includes(link.hostname) ||
            link.username || link.password || link.port) return null;
        var match = link.pathname.match(/^\/(?:galleries|reader)\/(\d{5,12})\.html$/);
        if (!match) match = link.pathname.match(
          /^\/(?:doujinshi|manga|artistcg|gamecg|imageset|western|non-h|anime|cosplay|cg)\/[^/]+-(\d{5,12})\.html$/);
        return match ? {id: match[1], url: link.href} : null;
      } catch (_) { return null; }
    }
    function clean(value) {
      return String(value || '').replace(/\s+/g, ' ').trim().slice(0, 220);
    }
    function titleFor(anchor, id) {
      var direct = anchor.querySelector('.gallery-title, .title, h3');
      var img = anchor.querySelector('img');
      var title = clean(direct && direct.textContent ||
        anchor.getAttribute('title') || anchor.textContent ||
        (img && img.getAttribute('alt')));
      if (title.length > 1) return title;
      // Do NOT ascend to .gallery-content: it can contain ALL result cards.
      var parent = anchor.parentElement;
      for (var depth = 0; parent && depth < 5; depth++, parent = parent.parentElement) {
        if (parent.classList.contains('gallery-content')) break;
        var links = parent.querySelectorAll('a[href]');
        var unique = {};
        for (var i = 0; i < links.length; i++) {
          var item = goodLink(links[i]);
          if (item) unique[item.id] = true;
          if (Object.keys(unique).length > 1) break;
        }
        if (Object.keys(unique).length !== 1 || !unique[id]) break;
        var heading = parent.querySelector('.gallery-title, .title, h1, h2, h3');
        var candidate = clean(heading && heading.textContent);
        if (candidate.length > 1) return candidate;
      }
      return '';
    }
    Array.prototype.forEach.call(document.querySelectorAll('a[href]'),
      function (anchor) {
        if (results.length >= 120) return;
        var item = goodLink(anchor);
        if (!item) return;
        var title = titleFor(anchor, item.id);
        var index = byId[item.id];
        if (index !== undefined) {
          if (!results[index].title && title) results[index].title = title;
          return;
        }
        byId[item.id] = results.length;
        results.push({url: item.url, title: title});
      });
    return JSON.stringify({url: location.href, items: results});
  })();''';
}
