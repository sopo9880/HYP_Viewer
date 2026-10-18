import 'dart:convert';

import 'social_share_text.dart';
import 'instagram_comment_html_parser.dart';

/// Snapshot of rendered PUBLIC content of a user-opened social page.
/// Comments are only those already visible in the WebView, never a promise
/// to download the entire thread or bypass a login wall.
class SocialWebCapture {
  final String url, title, description;
  final List<String> comments, pinnedComments, imageUrls;
  final List<InstagramCommentRecord> commentRecords;
  final bool limited, loginRequired, commentAreaPresent;
  final String collectorDiagnostics;

  const SocialWebCapture({
    required this.url, required this.title, required this.description,
    required this.comments, required this.imageUrls,
    this.pinnedComments = const [], this.commentAreaPresent = false,
    this.commentRecords = const [],
    this.limited = true, this.loginRequired = false,
    this.collectorDiagnostics = '',
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
      final htmlSnippet = decoded['commentHtml'] is String
          ? decoded['commentHtml'] as String : '';
      final parsed = InstagramCommentHtmlParser.parse(htmlSnippet);
      final hasDom = htmlSnippet.isNotEmpty;
      final records = parsed.comments;
      final log = read('diagnostics');
      return SocialWebCapture(
        url: read('url'), title: read('title'),
        description: read('description'),
        commentRecords: records,
        pinnedComments: hasDom
            ? records.where((e) => e.pinned).map((e) => e.text).toList()
            : readList('pinnedComments').take(30).toList(),
        comments: hasDom
            ? records.map((e) => e.text).toList()
            : readList('comments').take(60).toList(),
        commentAreaPresent: decoded['commentAreaPresent'] == true ||
            parsed.candidateRows > 0,
        collectorDiagnostics: hasDom
            ? '$log; domRows=${parsed.candidateRows}; parsed=${records.length}'
            : log,
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

  /// A one-shot click only when the user explicitly selects 'Open comments'
  /// in the inspector. Never clicks 'login', 'follow' or private controls.
  static const String openCommentsJavascript = r'''(function () {
    var selectors = [
      'svg[aria-label*="Comment"]', 'svg[aria-label*="comment"]',
      'svg[aria-label*="댓글"]', 'svg[aria-label*="コメント"]',
      '[aria-label="View all comments"]',
      '[aria-label="댓글 보기"]',
      'button[aria-label*="comment"]',
      'button[aria-label*="Comment"]',
      'a[href*="/comments/"]'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var nodes = document.querySelectorAll(selectors[i]);
      for (var j = 0; j < nodes.length; j++) {
        var node = nodes[j];
        var target = node.closest('button, a, [role="button"]') || node;
        var bounds = target.getBoundingClientRect();
        if (bounds.width <= 0 || bounds.height <= 0) continue;
        var style = window.getComputedStyle(target);
        if (style.display === 'none' || style.visibility === 'hidden') continue;
        target.click();
        return 'clicked';
      }
    }
    return 'not_found';
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
    // Instagram can render the comments OUTSIDE the post article (especially
    // in desktop modal and Reels). Search document-level visible comment rows
    // rather than assuming the first article/dialog owns the entire thread.
    var commentSelectors = [
      '[role="dialog"] [role="listitem"]',
      '[role="dialog"] ul li',
      '[role="dialog"] [data-testid="comment"]',
      '[role="dialog"] [data-testid="post-comment-root"]',
      'main [role="listitem"]', 'main ul li',
      'article [role="listitem"]', 'article ul li',
      '[data-testid="post-comment-root"]',
      '[role="listitem"]', 'ul li'
    ];
    var pinnedComments = instagram ? collect(document, [
      '[aria-label*="Pinned"]', '[aria-label*="고정"]',
      '[aria-label*="固定"]',
      '[role="dialog"] [data-testid*="pinned"]'
    ], 20) : [];
    var comments = instagram ? collect(document,
      commentSelectors, 60) : youtube ? collect(document, [
      'ytd-comment-thread-renderer #content-text',
      'ytd-comment-view-model #content-text',
      'yt-comment-thread-renderer #content-text',
      'ytd-backstage-post-thread-renderer #content-text'
    ], 60) : [];
    var matchingRows = instagram ? document.querySelectorAll(
      commentSelectors.join(',')).length : 0;
    // Some desktop Instagram layouts use text spans with no list item wrapper.
    // Only as a fallback, collect short rendered fragments with likely work
    // IDs from the current post/dialog. Never request hidden server content.
    var fallbackCount = 0;
    if (instagram) {
      var seenText = {};
      comments.forEach(function(value) { seenText[value] = true; });
      var candidates = document.querySelectorAll(
        '[role="dialog"] span, [role="dialog"] div[dir="auto"], ' +
        'main span, main div[dir="auto"], article span');
      for (var i = 0; i < candidates.length && i < 650 &&
           comments.length < 60; i++) {
        var node = candidates[i];
        if (node.closest('nav, [role="navigation"], header')) continue;
        var value = text(node);
        if (value.length < 5 || value.length > 550 ||
            !/[0-9]{5,12}/.test(value) || seenText[value]) continue;
        seenText[value] = true;
        comments.push(value);
        fallbackCount++;
      }
    }
    var commentAreaPresent = instagram &&
      (matchingRows > 0 || document.querySelector('[role="dialog"]') != null);
    var diagnostics = instagram
      ? ('rows=' + matchingRows + '; modal=' +
        (document.querySelector('[role="dialog"]') ? 'yes' : 'no') +
        '; fallback=' + fallbackCount)
      : '';
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
    // Inspect only the DOM that Instagram has already mounted in this
    // user-opened WebView. Send a compact sanitized fragment to a shared
    // Dart parser, so Windows and Android use identical extraction rules.
    // Never export cookies, scripts, form controls, tokens or whole page HTML.
    var commentHtml = '';
    if (instagram) {
      var root = null;
      var dialogs = document.querySelectorAll('[role="dialog"]');
      for (var di = 0; di < dialogs.length; di++) {
        if (dialogs[di].querySelector('._a9zr, ._ac6x, li._a9zj')) {
          root = dialogs[di];
          break;
        }
      }
      root = root || document.querySelector('main') || post;
      if (root) {
        var clone = root.cloneNode(true);
        clone.querySelectorAll(
          'script, style, svg, img, video, canvas, iframe, source, ' +
          'picture, textarea, input, noscript').forEach(function(node) {
          node.remove();
        });
        var allowedClass = {
          '_a9zr': true, '_a9zj': true, '_ac6x': true, '_ap3a': true
        };
        clone.querySelectorAll('*').forEach(function(node) {
          Array.from(node.attributes).forEach(function(attribute) {
            if (['role', 'dir', 'href', 'class', 'aria-label']
                .indexOf(attribute.name) < 0) {
              node.removeAttribute(attribute.name);
            }
          });
          if (node.hasAttribute('class')) {
            var classes = node.getAttribute('class').split(/\s+/)
                .filter(function(value) { return !!allowedClass[value]; });
            if (classes.length) node.setAttribute('class', classes.join(' '));
            else node.removeAttribute('class');
          }
          if (node.hasAttribute('href')) {
            var href = node.getAttribute('href');
            if (!href.startsWith('/') || href.startsWith('//') ||
                href.length > 160) node.removeAttribute('href');
          }
        });
        var markup = clone.outerHTML || '';
        if (markup.length <= 250000) commentHtml = markup;
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
      pinnedComments: pinnedComments,
      commentHtml: commentHtml,
      commentAreaPresent: commentAreaPresent,
      diagnostics: diagnostics,
      images: images,
      loginRequired: loginRequired
    });
  })();''';
}

/// Keeps public comments already displayed in the user's current WebView.
/// Instagram may unmount old rows while scrolling, so each DOM snapshot alone
/// cannot represent all comments that the user has seen in this session.
class SocialCommentAccumulator {
  String _postKey = '';
  String title = '';
  String description = '';
  bool loginRequired = false;
  bool commentAreaPresent = false;
  final Set<String> _seen = <String>{};
  final List<InstagramCommentRecord> _records = [];

  static const int maxCollectedComments = 200;
  List<InstagramCommentRecord> get commentRecords => List.unmodifiable([
    ..._records.where((e) => e.pinned),
    ..._records.where((e) => !e.pinned),
  ]);
  List<String> get comments =>
      List.unmodifiable(_records.map((e) => e.text));
  List<String> get pinnedComments =>
      List.unmodifiable(_records.where((e) => e.pinned).map((e) => e.text));
  int get count => _records.length;
  String get combinedText => [
    title, description,
    ..._records.where((e) => e.pinned).map((e) => e.text),
    ..._records.where((e) => !e.pinned).map((e) => e.text),
  ].where((value) => value.trim().isNotEmpty).toSet().join('\n\n');

  /// Ignore a location fragment or tracking query when identifying a post,
  /// but clear the ledger if a user browses to another post/reel.
  String _key(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && {'p', 'reel', 'tv'}.contains(segments.first)) {
      return segments.take(2).join('/');
    }
    return uri.host + uri.path;
  }

  void clear() {
    _postKey = '';
    title = '';
    description = '';
    loginRequired = false;
    commentAreaPresent = false;
    _seen.clear();
    _records.clear();
  }

  /// Returns newly observed comment count. Does not scrape hidden/private
  /// content, reach external endpoints or auto-expand comments.
  int add(SocialWebCapture snapshot) {
    final newKey = _key(snapshot.url);
    if (_postKey.isNotEmpty && newKey.isNotEmpty && newKey != _postKey) clear();
    if (newKey.isNotEmpty) _postKey = newKey;
    if (snapshot.title.isNotEmpty) title = snapshot.title;
    if (snapshot.description.length > description.length) {
      description = snapshot.description;
    }
    loginRequired = snapshot.loginRequired;
    commentAreaPresent = snapshot.commentAreaPresent;
    final before = _records.length;
    // Keep the author as part of the identity, but pass ONLY the body text
    // into NumberExtractor; numeric usernames are not gallery identifiers.
    final observed = snapshot.commentRecords.isNotEmpty
        ? snapshot.commentRecords
        : <InstagramCommentRecord>[
            ...snapshot.pinnedComments.map((text) =>
                InstagramCommentRecord(author: '', text: text, pinned: true)),
            ...snapshot.comments.map((text) =>
                InstagramCommentRecord(author: '', text: text)),
          ];
    for (final comment in observed) {
      final trimmed = comment.text.trim();
      if (trimmed.isEmpty || trimmed.length > 2000) continue;
      final record = InstagramCommentRecord(
        author: comment.author, text: trimmed, pinned: comment.pinned);
      if (_records.length < maxCollectedComments && _seen.add(record.key)) {
        _records.add(record);
      }
    }
    return _records.length - before;
  }
}
