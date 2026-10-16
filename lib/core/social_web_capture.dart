import 'dart:convert';

import 'social_share_text.dart';

/// A user-opened page snapshot of what is already in the rendered DOM.
/// "comments" means visible/loaded comments, never the full discussion.
class SocialWebCapture {
  final String url, title, description;
  final List<String> comments, imageUrls;
  final bool limited;

  const SocialWebCapture({
    required this.url, required this.title, required this.description,
    required this.comments, required this.imageUrls, this.limited = true,
  });

  String get combinedText => [
    title, description, ...comments,
  ].where((value) => value.trim().isNotEmpty).toSet().join('\n\n');

  static SocialWebCapture? parse(dynamic raw) {
    try {
      dynamic decoded = raw;
      for (var i = 0; i < 2 && decoded is String; i++) {
        decoded = jsonDecode(decoded);
      }
      if (decoded is! Map) return null;
      String read(String name) => SocialShareText.normalize(
          decoded[name] is String ? decoded[name] as String : '');
      List<String> readList(String name) {
        final source = decoded[name];
        if (source is! List) return [];
        return source.whereType<String>().take(80).map(
            SocialShareText.normalize).where((text) =>
            text.isNotEmpty && text.length <= 2000).toSet().toList();
      }
      final imageUrls = readList('images').where((value) =>
          value.startsWith('https://')).take(24).toList();
      final comments = readList('comments').take(60).toList();
      return SocialWebCapture(url: read('url'), title: read('title'),
        description: read('description'), comments: comments,
        imageUrls: imageUrls);
    } catch (_) {
      return null;
    }
  }

  /// Read-only inspection of visible public DOM data. Never use document
  /// cookies, intercept private APIs, auto-expand comments, or run logins.
  /// The result is deliberately bounded to prevent huge page extractions.
  static const String javascript = r'''(function () {
    function visible(el) {
      if (!el || !el.getBoundingClientRect) return false;
      var box = el.getBoundingClientRect();
      var style = window.getComputedStyle(el);
      return box.width > 0 && box.height > 0 &&
          style.display !== 'none' && style.visibility !== 'hidden';
    }
    function text(el) {
      if (!el || !visible(el)) return '';
      return String(el.innerText || el.textContent || '').trim().slice(0, 2000);
    }
    function meta(key) {
      var el = document.querySelector('meta[property="' + key + '"]') ||
               document.querySelector('meta[name="' + key + '"]');
      return (el && el.content ? el.content : '').slice(0, 4000);
    }
    function collect(selectors, count) {
      var result = [], seen = {};
      selectors.forEach(function (selector) {
        document.querySelectorAll(selector).forEach(function (el) {
          if (result.length >= count) return;
          var value = text(el);
          if (value.length >= 2 && !seen[value]) {
            seen[value] = true; result.push(value);
          }
        });
      });
      return result;
    }
    var host = location.hostname.toLowerCase();
    var instagram = host.indexOf('instagram.com') >= 0;
    var youtube = host.indexOf('youtube.com') >= 0;
    var comments = collect(instagram ? [
       'article ul li', 'article [role="listitem"]',
       '[data-testid="comment"]', 'ul[role="list"] li'
    ] : youtube ? [
       'ytd-comment-thread-renderer #content-text',
       'ytd-comment-view-model #content-text',
       'yt-comment-thread-renderer #content-text',
       'ytd-backstage-post-thread-renderer #content-text'
    ] : [], 60);
    var body = collect(instagram ? [
       'article h1', 'article [data-testid="post-comment-root"]',
       'article header + div'
    ] : youtube ? [
       '#description-inline-expander', '#description',
       'ytd-backstage-post-renderer #content-text'
    ] : [], 6);
    var images = [], imageSeen = {};
    document.querySelectorAll('article img, ytd-backstage-post-renderer img, #content img, video[poster], img').forEach(function (node) {
      if (images.length >= 24 || !visible(node)) return;
      var url = node.currentSrc || node.src || node.poster || '';
      var width = node.naturalWidth || node.clientWidth || 0;
      if (width < 160 || url.slice(0, 8) !== 'https://' || imageSeen[url]) return;
      imageSeen[url] = true; images.push(url.slice(0, 4000));
    });
    return JSON.stringify({
      url: location.href.slice(0, 2000),
      title: meta('og:title') || document.title.slice(0, 4000),
      description: [meta('og:description') || meta('description') || '',
                    body.join('\n')].filter(Boolean).join('\n').slice(0, 8000),
      comments: comments,
      images: images
    });
  })();''';
}
