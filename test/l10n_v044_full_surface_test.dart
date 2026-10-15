import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/i18n.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';

void main() {
  test('every top-level HYP surface has English and Japanese labels', () {
    const pages = [
      '홈', '내 서재', '즐겨찾기', '다운로드', '열람 기록', '설정',
      '작품 찾기', '링크로 작품 찾기', '서재 정렬', 'JSON 백업',
      '온라인 검색에 실패했어. 내 서재 검색은 정상 동작해.',
      '묶음 이름', '한 칸 위로', '한 칸 아래로',
      '현재 표지의 작품 읽기', '작품 번호 또는 제목으로 검색',
      '읽는 중', '다른 언어판 찾기', '표지 선택',
    ];
    for (final key in pages) {
      expect(HypI18n.translate(key, 'en'), isNot(key),
          reason: 'Untranslated English UI: $key');
      expect(HypI18n.translate(key, 'ja'), isNot(key),
          reason: 'Untranslated Japanese UI: $key');
    }
  });

  test('counts in reading, downloads and edition dialogs translate as whole',
      () {
    const statuses = [
      '작품 #123456 서재에 추가했어.',
      '언어판 3개를 같은 작품으로 묶었어.',
      '선택한 묶음 4개 적용을 요청했어.',
      '5페이지를 서재 표지로 지정했어.',
      '작품 8개를 묶었어.',
      '이전 다운로드 6개를 이어서 진행해.',
      '다운로드 대기: 7개 작품. 백그라운드에서도 순서대로 다운로드해.',
      '오프라인 저장 완료! 20페이지를 인터넷 없이 읽을 수 있어.',
      '서재·설정 복원 완료. 이미지 2개는 복원에 실패했어.',
      '백업 작품: 12개',
      '독서 활동 기록 11개 포함됨',
      '작품 29개 정보를 갱신했지만 추천 묶음이 없어. 수동으로 묶어.',
    ];
    for (final status in statuses) {
      for (final locale in ['en', 'ja']) {
        final translated = HypI18n.translate(status, locale);
        expect(translated, isNot(status),
            reason: 'Untranslated $locale status: $status');
        expect(RegExp(r'[가-힣]').hasMatch(translated), false,
            reason: 'Partial Korean text in $locale: $translated');
      }
    }
    const userTitle = '직접 작성한 미번역 작품명 123';
    expect(HypI18n.translate(userTitle, 'en'), userTitle);
  });

  test('all settings, dialogs and reader prompts have ARB counterparts',
      () async {
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));
    final keys = [
      [ko.settingsGeneral, en.settingsGeneral, ja.settingsGeneral],
      [ko.settingsViewer, en.settingsViewer, ja.settingsViewer],
      [ko.settingsBackup, en.settingsBackup, ja.settingsBackup],
      [ko.settingsAndroid, en.settingsAndroid, ja.settingsAndroid],
      [ko.settingsUpdates, en.settingsUpdates, ja.settingsUpdates],
      [ko.editionFinderLoading, en.editionFinderLoading,
          ja.editionFinderLoading],
      [ko.editionLinkConfirmTitle, en.editionLinkConfirmTitle,
          ja.editionLinkConfirmTitle],
      [ko.readerTooltipTwoPage, en.readerTooltipTwoPage,
          ja.readerTooltipTwoPage],
      [ko.settingsReaderHideOnOpen, en.settingsReaderHideOnOpen,
          ja.settingsReaderHideOnOpen],
      [ko.sourceIncomplete, en.sourceIncomplete, ja.sourceIncomplete],
      [ko.searchPartialSources, en.searchPartialSources,
          ja.searchPartialSources],
      [ko.readerFailureHttp, en.readerFailureHttp,
          ja.readerFailureHttp],
      [ko.tooltipSearchLanguage, en.tooltipSearchLanguage,
          ja.tooltipSearchLanguage],
    ];
    for (final triplet in keys) {
      expect(triplet[0], isNotEmpty);
      expect(triplet[1], isNot(triplet[0]));
      expect(triplet[2], isNot(triplet[0]));
    }
    expect(en.editionFinderProgress(2, 8), contains('2'));
    expect(ja.editionFinderLinkSelected(3), contains('3'));
    expect(ko.readerFailedPage(7), contains('7'));
  });

  testWidgets('a live language change rebuilds the 5-page navigation',
      (tester) async {
    final initial = HypLanguage.selected.value;
    addTearDown(() => HypLanguage.selected.value = initial);
    HypLanguage.selected.value = 'ko';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Column(children: [
        HypText('홈'), HypText('내 서재'), HypText('즐겨찾기'),
        HypText('다운로드'), HypText('설정'),
      ])),
    ));
    expect(find.text('홈'), findsOneWidget);
    HypLanguage.selected.value = 'en';
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    HypLanguage.selected.value = 'ja';
    await tester.pump();
    expect(find.text('ホーム'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
  });
}
