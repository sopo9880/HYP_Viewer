import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/instagram_comment_html_parser.dart';
import 'package:hyp_viewer/core/number_extractor.dart';
import 'package:hyp_viewer/core/social_web_capture.dart';

// Anonymized DOM shapes derived from two user-supplied October 2026 HTML
// captures. The originals may include account metadata and are NEVER saved
// to the repo. The actual structural fixture counts were 8 desktop and
// 9 mobile text comments, with image-only/empty entries excluded.
String _desktopRow(int n, {String? body, bool pinned = false}) {
  final comment = body ?? 'Desktop comment $n';
  return '''
<li class="_a9zj">
  <div class="_a9zr">
    <h3><a href="/reader_$n/" role="link">reader_$n</a></h3>
    <div><span dir="auto">$comment</span></div>
    <span dir="ltr">
      <time>2주</time><button>좋아요 12345678개</button>
      <button>답글 달기</button>
      ${pinned ? '<span>고정됨</span>' : ''}
    </span>
  </div>
</li>''';
}

String _mobileRow(int n, {String? body, bool photo = false}) {
  final comment = photo ? '앱에서 사진을 사용할 수 있습니다' :
      (body ?? 'Mobile comment $n');
  return '''
<div class="_ac6x" role="button">
  <a href="/reader_$n/" role="link">
    <span dir="auto">reader_$n</span>
  </a>
  <span dir="auto"><span dir="auto">$comment</span></span>
  <span dir="auto">2주</span>
  <a role="link" href="/p/12345678/c/45678901/liked_by/">
    <span dir="auto">좋아요 9999999개</span>
  </a>
  <div role="button"><span dir="auto">답글 달기</span></div>
</div>''';
}

void main() {
  test('PC role-dialog LI fixture extracts exactly eight real comment bodies', () {
    final html = '''
<div role="dialog">
  <p>9999999명이 좋아합니다</p>
  <ul>
    ${List.generate(8, (n) => _desktopRow(n + 1,
      body: n == 0 ? '작품 번호 1234567' : '일반적인 댓글 ${n+1}',
      pinned: n == 0)).join('')}
    ${_desktopRow(90, body: '앱에서 사진을 사용할 수 있습니다')}
    ${_desktopRow(91, body: '')}
  </ul>
</div>''';
    final parsed = InstagramCommentHtmlParser.parse(html);
    expect(parsed.comments, hasLength(8));
    expect(parsed.comments.first.author, 'reader_1');
    expect(parsed.comments.first.text, '작품 번호 1234567');
    expect(parsed.comments.first.pinned, true);
    expect(parsed.comments.where((e) => e.text.contains('좋아요')), isEmpty);
    expect(parsed.comments.where((e) => e.text.contains('2주')), isEmpty);
  });

  test('Android _ac6x fixture extracts nine comments with nested auto spans', () {
    final html = '''
<main>
  ${List.generate(9, (n) => _mobileRow(n + 1,
    body: n == 0 ? 'Mobile note 2345678' : '일반 댓글 ${n+1}')).join('')}
  ${_mobileRow(91, photo: true)}
  <div role="button"><span dir="auto">답글 달기</span></div>
</main>''';
    final parsed = InstagramCommentHtmlParser.parse(html);
    expect(parsed.comments, hasLength(9));
    expect(parsed.comments.first.text, 'Mobile note 2345678');
    expect(parsed.comments.last.author, 'reader_9');
    expect(parsed.comments.last.text, '일반 댓글 9');
    expect(parsed.comments.where((e) => e.text.contains('9999999')), isEmpty);
  });

  test('same comment body from two authors is collected twice', () {
    final html = '<main>${_mobileRow(1, photo: true)}'
        '${_mobileRow(2, body: '똑같은 댓글')}'
        '${_mobileRow(3, body: '똑같은 댓글')}</main>';
    final result = InstagramCommentHtmlParser.parse(html);
    expect(result.comments, hasLength(2));
    expect(result.comments[0].author, 'reader_2');
    expect(result.comments[1].author, 'reader_3');
  });

  test('untrusted UI counts, markup, and usernames never become gallery IDs', () {
    final html = '<main>'
        '${_mobileRow(1234567, body: '이것은 평범한 텍스트')}'
        '${_mobileRow(2, body: '작품 번호 3456789')}'
        '</main>';
    final snapshot = SocialWebCapture.parse({
      'url': 'https://www.instagram.com/reel/TESTID/',
      'title': '',
      'description': '',
      'comments': ['bogus 9999999'],
      'pinnedComments': <String>[],
      'commentHtml': html,
      'diagnostics': 'rows=0; modal=no; fallback=0',
      'images': <String>[],
    })!;
    expect(snapshot.commentRecords, hasLength(2));
    expect(snapshot.commentRecords.first.author, 'reader_1234567');
    expect(snapshot.comments, hasLength(2));
    final saved = SocialCommentAccumulator();
    saved.add(snapshot);
    final ids = NumberExtractor.extract(saved.combinedText)
        .map((candidate) => candidate.code).toSet();
    expect(ids, contains('3456789'));
    expect(ids, isNot(contains('1234567')));
    expect(ids, isNot(contains('9999999')));
    expect(saved.count, 2);
    expect(snapshot.collectorDiagnostics, contains('parsed=2'));
  });

  test('comment sessions dedupe scroll snapshots and distinguish authors', () {
    const url = 'https://www.instagram.com/reel/SAME/';
    SocialWebCapture domSnapshot(String fragment) =>
        SocialWebCapture.parse({
          'url': url,
          'title': '',
          'description': '',
          'comments': <String>[],
          'commentHtml': '<main>$fragment</main>',
        })!;
    final collector = SocialCommentAccumulator();
    expect(collector.add(domSnapshot(_mobileRow(1, body: '같은 댓글'))), 1);
    expect(collector.add(domSnapshot(_mobileRow(1, body: '같은 댓글') +
      _mobileRow(2, body: '같은 댓글'))), 1);
    expect(collector.count, 2);
    expect(collector.commentRecords[0].author, 'reader_1');
    expect(collector.commentRecords[1].author, 'reader_2');
  });

  test('no comment/body and too large fragments fail closed', () {
    expect(InstagramCommentHtmlParser.parse('<main>없음</main>')
        .comments, isEmpty);
    expect(InstagramCommentHtmlParser.parse(List.filled(InstagramCommentHtmlParser.maxHtmlLength + 1, 'a').join())
        .comments, isEmpty);
  });

  test('WebView only sends sanitized on-page DOM and no login credentials', () {
    final script = SocialWebCapture.javascript;
    expect(script, contains('commentHtml: commentHtml'));
    expect(script, contains('cloneNode(true)'));
    expect(script, contains('node.removeAttribute(attribute.name)'));
    expect(script, contains('script, style, svg, img, video'));
    expect(script, isNot(contains('document.cookie')));
    expect(script, isNot(contains('fetch(')));
    expect(script, isNot(contains('localStorage')));
  });
}
