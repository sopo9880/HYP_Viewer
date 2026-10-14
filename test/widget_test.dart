import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/main.dart';

void main() {
  testWidgets('desktop dashboard has functional navigation and Shorts form',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const HypViewerApp());
    await tester.pump();
    expect(find.text('HYP Viewer'), findsWidgets);
    expect(find.byKey(const Key('nav-library')), findsOneWidget);
    expect(find.text('쇼츠 작품 번호 찾기'), findsOneWidget);
    expect(find.byKey(const Key('shorts-url-input')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pump();
    expect(find.text('내 서재'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pump();
    expect(find.byKey(const Key('online-source-input')), findsOneWidget);
    expect(find.byKey(const Key('hero-artwork-upload')), findsOneWidget);
    expect(find.byKey(const Key('reader-vertical-scroll-setting')),
        findsOneWidget);
    expect(find.byKey(const Key('app-language-setting')), findsOneWidget);
    expect(find.byKey(const Key('hero-artwork-source-setting')), findsOneWidget);
    expect(find.byKey(const Key('reader-tap-navigation-setting')), findsOneWidget);
    expect(find.byKey(const Key('reader-webtoon-setting')), findsOneWidget);
    expect(find.byKey(const Key('auto-download-on-save-setting')), findsOneWidget);
    expect(find.byKey(const Key('open-after-save-setting')), findsOneWidget);
    expect(find.byKey(const Key('app-version-label')), findsOneWidget);
    expect(find.text('Excel 내보내기'), findsWidgets);
  });

  testWidgets('mobile navigation and live library search work without dummy data',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const HypViewerApp());
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('쇼츠 작품 번호 찾기'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('library-search-input')), '없는 작품',
    );
    await tester.pump();
    expect(find.text('검색 결과'), findsOneWidget);
    expect(find.textContaining('표시할 작품이 없어'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('library-search-input')), '',
    );
    await tester.pump();
    expect(find.text('쇼츠 작품 번호 찾기'), findsOneWidget);
  });
}
