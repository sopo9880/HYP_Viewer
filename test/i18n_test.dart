import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/i18n.dart';

void main() {
  test('all supported languages translate essential navigation and controls', () {
    expect(HypI18n.translate('내 서재', 'ko'), '내 서재');
    expect(HypI18n.translate('내 서재', 'en'), 'My Library');
    expect(HypI18n.translate('내 서재', 'ja'), 'マイ本棚');
    expect(HypI18n.translate('작품 찾기', 'en'), 'Find Work');
    expect(HypI18n.translate('작품 찾기', 'ja'), '作品を探す');
    expect(HypI18n.translate('서재에서 작품 삭제', 'en'),
        'Remove Work from Library');
    expect(HypI18n.translate('발견된 번호 후보: 2개', 'en'),
        'Candidate IDs found: 2');
    expect(HypI18n.translate('현재 버전: v0.1.8 (build 9)', 'ja'),
        '現在のバージョン: v0.1.8 (build 9)');
    expect(HypI18n.translate('USER BOOK TITLE', 'ja'), 'USER BOOK TITLE');
  });

  testWidgets('language selection updates visible text without restart',
      (tester) async {
    HypLanguage.selected.value = 'ko';
    addTearDown(() => HypLanguage.selected.value = 'ko');
    await tester.pumpWidget(ValueListenableBuilder<String>(
      valueListenable: HypLanguage.selected,
      builder: (context, language, _) => MaterialApp(
        locale: Locale(language),
        home: const Scaffold(
          body: Column(children: [
            HypText('내 서재'),
            HypText('작품 찾기'),
          ]),
        ),
      ),
    ));
    expect(find.text('내 서재'), findsOneWidget);
    HypLanguage.selected.value = 'en';
    await tester.pumpAndSettle();
    expect(find.text('My Library'), findsOneWidget);
    expect(find.text('Find Work'), findsOneWidget);
    HypLanguage.selected.value = 'ja';
    await tester.pumpAndSettle();
    expect(find.text('マイ本棚'), findsOneWidget);
    expect(find.text('作品を探す'), findsOneWidget);
  });
}
