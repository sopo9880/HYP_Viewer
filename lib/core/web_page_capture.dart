import 'dart:convert';

import 'online_gallery.dart';

/// A single image observed in the currently rendered, user-opened page.
/// No hidden API endpoints or credentials are requested.
class WebPageImage {
  final Uri url;
  final int order;
  final int width;
  final int height;
  final bool noReferrer;

  const WebPageImage({
    required this.url,
    required this.order,
    required this.width,
    required this.height,
    this.noReferrer = false,
  });
}

/// An opt-in snapshot of visible/public DOM metadata and image references.
class WebPageCapture {
  final Uri sourceUrl;
  final String title;
  final String author;
  final String publishedAt;
  final List<WebPageImage> images;
  final int expectedImages;

  const WebPageCapture({
    required this.sourceUrl,
    required this.title,
    required this.author,
    required this.publishedAt,
    required this.images,
    this.expectedImages = 0,
  });

  static String _text(Object? value, [int limit = 240]) {
    if (value is! String) return '';
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.length > limit ? cleaned.substring(0, limit) : cleaned;
  }

  /// Some WebViews return a JSON-encoded String wrapped in another String.
  static WebPageCapture? parse(Object? raw) {
    try {
      Object? data = raw;
      for (var i = 0; i < 2 && data is String; i++) {
        data = jsonDecode(data);
      }
      if (data is! Map) return null;
      final origin = Uri.tryParse(_text(data['url'], 2048));
      if (origin == null || !OnlineSourcePolicy.isHttpsPublic(origin)) {
        return null;
      }
      final entries = data['images'];
      if (entries is! List) return null;
      final found = <WebPageImage>[];
      final seen = <String>{};
      int number(Object? raw, int fallback) =>
          raw is num ? raw.toInt() : int.tryParse('$raw') ?? fallback;
      for (final item in entries.take(1500)) {
        if (item is! Map) continue;
        final value = item['url'];
        if (value is! String || value.length > 4096) continue;
        final target = origin.resolve(value);
        if (!OnlineSourcePolicy.isHttpsPublic(target)) continue;
        if (!seen.add(target.toString())) continue;
        final order = number(item['order'], found.length + 1);
        if (order < 1 || order > 1500) continue;
        found.add(WebPageImage(
          url: target,
          order: order,
          width: number(item['width'], 0).clamp(0, 100000).toInt(),
          height: number(item['height'], 0).clamp(0, 100000).toInt(),
          noReferrer: item['noReferrer'] == true,
        ));
      }
      found.sort((a, b) => a.order.compareTo(b.order));
      return WebPageCapture(
        sourceUrl: origin,
        title: _text(data['title']).isEmpty
            ? origin.host : _text(data['title']),
        author: _text(data['author']),
        publishedAt: _text(data['publishedAt'], 80),
        images: List.unmodifiable(found),
        expectedImages: number(data['expectedImages'], found.length)
            .clamp(found.length, 1500).toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Read the current DOM only after the user presses "Find images".
  /// Kone pages have image-1 .. image-N wrappers, often all already in DOM
  /// even while the browser defers image network loads (loading="lazy").
  /// Generic sites fall back to their main/article content region.
  static const String captureJavaScript = r'''(function () {
    function meta(name) {
      var el = document.querySelector('meta[property="' + name + '"]') ||
               document.querySelector('meta[name="' + name + '"]');
      return el ? (el.content || '') : '';
    }
    var canonical = document.querySelector('link[rel="canonical"]');
    var current = location.href;
    if (canonical && canonical.href) {
      try {
        var proposed = new URL(canonical.href, location.href);
        if (proposed.origin === location.origin && proposed.protocol === 'https:') {
          current = proposed.href;
        }
      } catch (_) {}
    }
    // A webtoon page may contain dozens of unrelated banner images.
    // Prefer actual reading slots, never the whole body, when present.
    var themeViewer = document.querySelector('[data-theme-viewer-images]');
    var slots = themeViewer
      ? themeViewer.querySelectorAll('.theme-viewer-image[data-theme-page]')
      : [];
    var article = document.querySelector('#post-article');
    var root = (article && article.querySelector('.article-prose')) ||
      article || document.querySelector('article') ||
      document.querySelector('[role="main"]') ||
      document.querySelector('main') || document.body;
    var known = root.querySelectorAll('.image-view-wrapper img');
    var imgs = slots.length
      ? themeViewer.querySelectorAll('.theme-viewer-image[data-theme-page] img')
      : (known.length ? known : root.querySelectorAll('img'));
    var found = [], seen = {};
    for (var i = 0; i < imgs.length && found.length < 1500; i++) {
      var node = imgs[i];
      var themeSlot = slots.length
        ? node.closest('.theme-viewer-image[data-theme-page]') : null;
      // On dynamic viewers the HTML may start with decoy .woff/.js URLs.
      // Select only URLs of images the browser actually rendered.
      // Delayed/lazy pages can be detected again after being scrolled into view.
      if (themeSlot && (!node.complete ||
          node.naturalWidth <= 0 || node.naturalHeight <= 0)) continue;
      var raw = node.currentSrc || node.getAttribute('src') ||
        node.getAttribute('data-src') ||
        node.getAttribute('data-original') || '';
      if (!raw || raw.startsWith('data:') || raw.startsWith('blob:')) continue;
      try {
        var url = new URL(raw, document.baseURI);
        if (url.protocol !== 'https:' || url.username || url.password ||
            seen[url.href]) continue;
        var width = Number(node.getAttribute('width')) || node.naturalWidth || 0;
        var height = Number(node.getAttribute('height')) || node.naturalHeight || 0;
        if (!known.length && width && height &&
            width < 300 && height < 300) continue;
        seen[url.href] = true;
        var container = node.closest('[id^="image-"]');
        var themeOrder = themeSlot
          ? Number(themeSlot.getAttribute('data-theme-page')) : 0;
        var order = themeOrder > 0 ? themeOrder :
          container && /^image-\d+$/.test(container.id)
          ? Number(container.id.substring(6)) : (i + 1);
        if (order < 1 || order > 1500) order = i + 1;
        found.push({
          url: url.href, order: order, width: width, height: height,
          noReferrer: node.referrerPolicy === 'no-referrer' ||
            node.getAttribute('referrerpolicy') === 'no-referrer'
        });
      } catch (_) {}
    }
    var heading = (slots.length && document.querySelector('.theme-viewer-title')) ||
      (article && article.querySelector('header h1')) ||
      root.querySelector('h1') || document.querySelector('h1');
    var title = (heading && heading.textContent || '').trim() ||
      meta('og:title') || document.title;
    return JSON.stringify({
      url: current,
      title: title.slice(0, 240),
      author: meta('article:author').slice(0, 240),
      publishedAt: meta('article:published_time').slice(0, 80),
      expectedImages: slots.length ? slots.length : found.length,
      images: found
    });
  })();''';
}
