import 'dart:convert';

import 'social_share_text.dart';

/// Snapshot of rendered PUBLIC content of a user-opened social page.
/// Comments are only those already visible in the WebView, never a promise
/// to download the entire thread or bypass a login wall.
class SocialWebCapture {
  final String url, title, description;
  final List<String> comments, imageUrls;
  final bool limited, loginRequired;

  const SocialWebCapture({
    required this.url, required this.title, required this.description,
    required this.comments, required this.imageUrls,
    this.limited = true, this.loginRequired = false,
  });

  String get combinedText => [title, description, ...comments]
      .where((value) => value.trim().isNotEmpty).toSet().join('\n\n');

  static SocialWebCapture? parse(dynamic raw) {
    try {
      dynamic decoded = raw;
      for (var i = 0; i < 2 && decoded is String; i++) {
        decoded = jsonDecode(decoded);
      }
      if (decoded is! Map) return null;
      String read(String key) => SocialShareText.normalize(
          decoded[key] is String ? decoded[key] as String : '');
      List<String> readList(String key) {
        if (decoded[key] is! List) return [];
        return (decoded[key] as List).whereType<String>().take(80)
            .map(SocialShareText.normalize)
            .where((s) => s.isNotEmpty && s.length <= 2000)
            .toSet().toList();
      }
      return SocialWebCapture(
        url: read('url'), title: read('title'),
        description: read('description'),
        comments: readList('comments').take(60).toList(),
        imageUrls: readList('images')
            .where((s) => s.startsWith('https://')).take(24).toList(),
        loginRequired: decoded['loginRequired'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Read only visible DOM and public metadata on the page the user opened.
  /// We do not request private endpoints, inject authentication, click
  /// "load more" programmatically, read cookies or bypass access controls.
  /// Rerunning this script AFTER the user scrolls/expands comments captures
  /// newly rendered comments; the first page load often shows none.
  /// Observe dynamic public comment rendering in the user-opened WebView.
  /// Polling the existing snapshot remains the fallback when DOM events stall.
  static const String observerJavascript = r'''(function() {
    if (window.__hypVisibleObserver || !document.body) return;
    window.__hypVisibleDomRevision = 0;
    window.__hypVisibleObserver = new MutationObserver(function() {
      window.__hypVisibleDomRevision += 1;
    });
    window.__hypVisibleObserver.observe(document.body, {
      childList: true, subtree: true, characterData: true
    });
  })();''';

  static const String javascript = r'''(function () {
    function visible(el) {
      if (!el || !el.getBoundingClientRect) return false;
      var bounds = el.getBoundingClientRect();
      var style = window.getComputedStyle(el);
      return bounds.width > 0 && bounds.height > 0 &&
          style.display !== 'none' && style.visibility !== 'hidden';
    }
    function text(el) {
      if (!visible(el)) return '';
      return String(el.innerText || el.textContent || '').trim().slice(0, 2000);
    }
    function meta(name) {
      var node = document.querySelector('meta[property="' + name + '"]') ||
                 document.querySelector('meta[name="' + name + '"]');
      return (node && node.content ? node.content : '').slice(0, 4000);
    }
    function collect(root, selectors, maximum) {
      var result = [], seen = {};
      if (!root) return result;
      selectors.forEach(function(selector) {
        root.querySelectorAll(selector).forEach(function(node) {
          if (result.length >= maximum) return;
          var value = text(node);
          if (value.length < 2 || seen[value]) return;
          seen[value] = true;
          result.push(value);
        });
      });
      return result;
    }

    var host = location.hostname.toLowerCase();
    var instagram = host === 'instagram.com' ||
                    host.endsWith('.instagram.com');
    var youtube = host === 'youtube.com' ||
                  host.endsWith('.youtube.com');
    // Instagram's post may live in article, main or an opened dialog.
    var post = instagram ? (
      document.querySelector('[role="dialog"] article') ||
      document.querySelector('main article') ||
      document.querySelector('article') ||
      document.querySelector('[role="dialog"]')
    ) : document;
    var comments = instagram ? collect(post, [
      '[aria-label*="Pinned"]', '[aria-label*="고정"]',
      '[aria-label*="固定"]',
      'ul li', 'ul ul', '[role="listitem"]',
      '[data-testid="comment"]', '[data-testid="post-comment-root"]'
    ], 60) : youtube ? collect(document, [
      'ytd-comment-thread-renderer #content-text',
      'ytd-comment-view-model #content-text',
      'yt-comment-thread-renderer #content-text',
      'ytd-backstage-post-thread-renderer #content-text'
    ], 60) : [];
    var captions = instagram ? collect(post, [
      'h1', '[data-testid="post-comment-root"]',
      'header + div', '[role="heading"]'
    ], 6) : youtube ? collect(document, [
      '#description-inline-expander', '#description',
      'ytd-backstage-post-renderer #content-text'
    ], 6) : [];
    var loginInput = document.querySelector(
      'input[name="username"], input[name="password"]');
    var loginForm = document.querySelector('form[action*="/accounts/login"]');
    var loginRequired = !!((loginInput && visible(loginInput)) ||
        (loginForm && visible(loginForm)));
    if (!loginRequired && instagram) {
      var dialog = document.querySelector('[role="dialog"]');
      if (dialog && visible(dialog) && !post?.querySelector('ul li')) {
        var labels = text(dialog).slice(0, 250).toLowerCase();
        loginRequired = /log in|sign in|로그인|ログイン/.test(labels);
      }
    }
    var images = [], seenImages = {};
    var imageRoot = post || document;
    imageRoot.querySelectorAll('img, video[poster]').forEach(function(node) {
      if (images.length >= 24 || !visible(node)) return;
      var url = node.currentSrc || node.src || node.poster || '';
      var width = node.naturalWidth || node.clientWidth || 0;
      if (width < 160 || !url.startsWith('https://') ||
          url.length > 4000 || seenImages[url]) return;
      seenImages[url] = true;
      images.push(url);
    });
    var description = [
      meta('og:description') || meta('description') || '',
      captions.join('\n')
    ].filter(Boolean).join('\n').slice(0, 8000);
    return JSON.stringify({
      url: location.href.slice(0, 2000),
      title: meta('og:title') || document.title.slice(0, 4000),
      description: description,
      comments: comments,
      images: images,
      loginRequired: loginRequired
    });
  })();''';
}
