import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/announcements.dart';
import 'package:hyp_viewer/core/i18n.dart';
import 'package:hyp_viewer/core/social_web_capture.dart';
import 'package:hyp_viewer/core/source_links.dart';
import 'package:hyp_viewer/ui/instagram_source_inspector.dart';

SocialWebCapture snapshot(String url, List<String> comments, {
  List<String> pinned = const [],
  String description = '',
  bool login = false,
}) => SocialWebCapture(
  url: url, title: 'Post',
  description: description, comments: comments, pinnedComments: pinned,
  imageUrls: const [], loginRequired: login, commentAreaPresent: true);

void main() {
  test('comments accumulate across scrolls, dedupe and preserve pinned first', () {
    final collected = SocialCommentAccumulator();
    const url = 'https://www.instagram.com/reel/SAMPLE01/';
    expect(collected.add(snapshot(url, ['user1 1234567'],
        pinned: ['pinned 2345678'], description: 'Original caption')), 2);
    expect(collected.add(snapshot(url + '?utm_source=share',
        ['user1 1234567', 'user2 3456789'])), 1);
    expect(collected.count, 3);
    expect(collected.pinnedComments.single, contains('2345678'));
    expect(collected.combinedText, contains('3456789'));
    expect(collected.combinedText.indexOf('2345678'),
        lessThan(collected.combinedText.indexOf('1234567')));
    expect(collected.description, 'Original caption');
    expect(collected.add(snapshot('https://www.instagram.com/p/NEWPOST/',
        ['user3 4567890'])), 1);
    expect(collected.count, 1);
    expect(collected.combinedText, isNot(contains('1234567')));
  });

  test('session collection is capped and login wall remains explicit', () {
    final ledger = SocialCommentAccumulator();
    const url = 'https://www.instagram.com/p/ANYTHING/';
    for (var batch = 0; batch < 6; batch++) {
      ledger.add(snapshot(url,
        List.generate(50, (index) => 'comment ' +
          (index + batch * 50).toString())));
    }
    expect(ledger.count, SocialCommentAccumulator.maxCollectedComments);
    ledger.add(snapshot(url, const [], login: true));
    expect(ledger.loginRequired, true);
    expect(ledger.count, SocialCommentAccumulator.maxCollectedComments);
  });

  test('DOM inspection is read-only with visible pinned comment hints', () {
    final script = SocialWebCapture.javascript;
    expect(script, contains('pinnedComments'));
    expect(script, contains('commentAreaPresent'));
    expect(script, contains('[role="listitem"]'));
    expect(script, isNot(contains('fetch(')));
    expect(script, isNot(contains('document.cookie')));
    expect(SocialWebCapture.observerJavascript, contains('MutationObserver'));
  });

  testWidgets('Instagram inspector is a full scaffold, not a small dialog',
      (tester) async {
    HypLanguage.selected.value = 'en';
    addTearDown(() => HypLanguage.selected.value = 'ko');
    final link = SourceLink.parse('https://www.instagram.com/reel/ABC123/');
    expect(link, isNotNull);
    await tester.pumpWidget(MaterialApp(
      home: InstagramSourceInspector(source: link!),
    ));
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('Analyze Instagram Posts & Reels'), findsOneWidget);
  }, skip: Platform.isAndroid || Platform.isWindows);

  test('app notifications translate fixed and counted values', () {
    final messages = <String>[
      '승인된 작품을 오프라인으로 다운로드 중',
      '번호를 찾지 못했어. 댓글을 확인하고 직접 입력해줘.',
      '공유 내용을 받았어. 링크에서 작품 번호를 찾을게.',
      '알림 권한이 꺼져 있어 진행률이 알림창에 표시되지 않아. 다운로드는 계속 시도할게. Android 설정에서 알림을 허용해줘.',
      '후보 3개 발견. 확인 후 저장해줘.',
      '작품 12345 다운로드 실패: timeout',
      '백그라운드 다운로드 시작 실패: timeout. 작업은 저장되어 있으니 앱으로 돌아와 다시 시도해줘.',
      '다운로드 대기: 4개 작품. 백그라운드에서도 순서대로 다운로드해.',
    ];
    for (final input in messages) {
      for (final language in ['en', 'ja']) {
        final output = HypI18n.translate(input, language);
        expect(output, isNot(input),
            reason: 'Unlocalized notice for language ' + language);
        expect(RegExp(r'[가-힣]').hasMatch(output), isFalse,
            reason: 'Korean leaked into ' + language + ': ' + output);
      }
    }
  });

  test('announcements choose translations without faking legacy copies', () {
    final notice = AppAnnouncement.fromJson({
      'id': 'notice_20261017',
      'title': '새 버전',
      'message': '업데이트가 있어요.',
      'publishedAt': '2026-10-17T09:00:00Z',
      'translations': {
        'en': {'title': 'New Version', 'message': 'Update available.'},
        'ja': {'title': '新しいバージョン', 'message': '更新があります。'},
      },
    });
    expect(notice.titleFor('en'), 'New Version');
    expect(notice.messageFor('ja'), '更新があります。');
    expect(notice.titleFor('ko'), '새 버전');
    final old = AppAnnouncement.fromJson({
      'id': 'legacy_20261017',
      'title': '긴급 공지',
      'message': '확인하세요.',
      'publishedAt': '2026-10-17T09:00:00Z',
    });
    expect(RegExp(r'[가-힣]').hasMatch(old.titleFor('en')), false);
    expect(RegExp(r'[가-힣]').hasMatch(old.messageFor('ja')), false);
    expect(old.messageFor('ko'), '확인하세요.');
  });

  test('Android initial download notification uses app locale', () {
    final flutter = File('lib/core/background_download_runtime.dart')
        .readAsStringSync();
    expect(flutter, contains("HypLanguage.selected.value"));
    expect(flutter, contains("notificationText: HypI18n.translate("));
    final kotlin = File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/MainActivity.kt')
        .readAsStringSync();
    expect(kotlin, contains('if (preparing) 0 else'));
  });
}
