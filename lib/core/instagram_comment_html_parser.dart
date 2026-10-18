import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// The small, sanitized DOM fragment from an Instagram page the user opened.
/// This parser is shared by Android and Windows instead of relying on
/// platform-specific JavaScript text selectors. No cookies, API requests,
/// hidden endpoints or authentication material are required.
class InstagramCommentRecord {
  final String author;
  final String text;
  final bool pinned;

  const InstagramCommentRecord({
    required this.author,
    required this.text,
    this.pinned = false,
  });

  String get key => '${author.toLowerCase()}\u0000$text';
}

class InstagramCommentParseResult {
  final List<InstagramCommentRecord> comments;
  final int candidateRows;

  const InstagramCommentParseResult(this.comments, this.candidateRows);
}

/// Both patterns below are grounded in the user's actual desktop and mobile
/// Instagram HTML captures (2026-10). Ignore unstable generic CSS classes.
/// Desktop: ul > li._a9zj > div._a9zr (comment content).
/// Mobile: div._ac6x[role=button] (whole comment).
///
/// This class never converts HTML from a remote URL into a network request.
/// Its input must be a DOM fragment observed in the user's own WebView.
abstract final class InstagramCommentHtmlParser {
  static const int maxHtmlLength = 250000;
  static const int maxComments = 120;

  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _username = RegExp(r'^[A-Za-z0-9._]{1,30}$');
  static final RegExp _control = RegExp(
    r'^(?:답글 달기|답글 보기(?:\(\d+개\))?|답글 \d+개 모두 보기|'
    r'댓글 옵션|댓글 더 읽어들이기|번역 보기|좋아요 \d+개|'
    r'더 보기|댓글 달기|고정됨|Pinned|固定|'
    r'Reply|View replies|View all replies|See translation|Like|'
    r'返信|いいね|翻訳を見る)$',
    caseSensitive: false,
  );
  static final RegExp _relativeTime = RegExp(
    r'^\d+\s*(?:초|분|시간|일|주|달|개월|년|s|m|h|d|w|mo|y)$',
    caseSensitive: false,
  );

  static String _clean(String value) =>
      value.replaceAll(_whitespace, ' ').trim();

  static bool _isControl(String value) {
    if (_control.hasMatch(value) || _relativeTime.hasMatch(value)) return true;
    if (value == '앱에서 사진을 사용할 수 있습니다' ||
        value == 'Photo available in the app' ||
        value == '사진을 사용할 수 있습니다') return true;
    return false;
  }

  static String _author(dom.Element row) {
    for (final anchor in row.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (!href.startsWith('/') || href.startsWith('//')) continue;
      final uri = Uri.tryParse(href);
      if (uri == null) continue;
      final path = uri.pathSegments
          .where((segment) => segment.isNotEmpty).toList();
      if (path.length != 1) continue;
      final candidate = path.single;
      if (!_username.hasMatch(candidate)) continue;
      if (const {'p', 'reel', 'tv', 'explore', 'accounts', 'direct', 'stories'}
          .contains(candidate)) continue;
      final label = _clean(anchor.text);
      // Excludes an avatar-only anchor. The author must appear as text in
      // this comment row, so post metadata cannot become a fake author.
      if (label.isNotEmpty && label.toLowerCase() == candidate.toLowerCase()) {
        return candidate;
      }
    }
    return '';
  }

  static bool _withinLink(dom.Element span, dom.Element row) {
    dom.Node? parent = span.parent;
    while (parent != null && !identical(parent, row)) {
      if (parent is dom.Element &&
          (parent.localName == 'a' || parent.localName == 'time' ||
              parent.localName == 'button' ||
              (parent.attributes['role'] == 'button' &&
                  _control.hasMatch(_clean(parent.text))))) {
        return true;
      }
      parent = parent.parent;
    }
    return false;
  }

  static String _body(dom.Element row, String author) {
    final lines = <String>[];
    for (final span in row.querySelectorAll('span[dir="auto"]')) {
      // Android nests one auto-direction span inside another; only use the
      // leaf to avoid counting the entire comment body twice.
      if (span.querySelector('span[dir="auto"]') != null) continue;
      if (_withinLink(span, row)) continue;
      final candidate = _clean(span.text);
      if (candidate.isEmpty || candidate.length > 2000 ||
          candidate.toLowerCase() == author.toLowerCase() ||
          _isControl(candidate)) continue;
      if (!lines.contains(candidate)) lines.add(candidate);
    }
    return _clean(lines.join(' '));
  }

  static bool _containsReplyAction(dom.Element row) {
    // A verified action is more reliable than a heading or a visible
    // 'comments count' label elsewhere on a post.
    for (final action in row.querySelectorAll('button, [role="button"]')) {
      if (_clean(action.text) == '답글 달기' ||
          _clean(action.text).toLowerCase() == 'reply' ||
          _clean(action.text) == '返信') {
        return true;
      }
    }
    return false;
  }

  static InstagramCommentParseResult parse(String markup) {
    if (markup.isEmpty || markup.length > maxHtmlLength) {
      return const InstagramCommentParseResult([], 0);
    }

    final document = html.parse(markup);
    final preferredRows = document.querySelectorAll('._a9zr, ._ac6x');
    // A future Instagram markup change can remove these class hooks.
    // The safe fallback only looks in comment-like LI elements with a
    // reply action and a real author profile link.
    final rows = preferredRows.isNotEmpty
        ? preferredRows
        : document.querySelectorAll('li, div[role="button"]');
    final found = <InstagramCommentRecord>[];
    final seen = <String>{};
    for (final row in rows) {
      if (found.length >= maxComments) break;
      if (!_containsReplyAction(row)) continue;
      final author = _author(row);
      if (author.isEmpty) continue;
      final body = _body(row, author);
      if (body.isEmpty) continue;
      final normalized = body.toLowerCase();
      final pinned = _clean(row.text).contains('고정됨') ||
          _clean(row.text).contains('Pinned') ||
          _clean(row.text).contains('固定');
      final record = InstagramCommentRecord(
          author: author, text: body, pinned: pinned);
      if (normalized.isNotEmpty && seen.add(record.key)) {
        found.add(record);
      }
    }
    return InstagramCommentParseResult(found, rows.length);
  }
}
