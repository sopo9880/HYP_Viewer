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
    expect(find.text('링크로 작품 찾기'), findsOneWidget);
    expect(find.byKey(const Key('shorts-url-input')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pump();
    expect(find.text('내 서재'), findsWidgets);
    expect(find.byKey(const Key('library-select-mode')), findsOneWidget);
    expect(find.byKey(const Key('library-completed-toggle')), findsOneWidget);
    await tester.tap(find.byKey(const Key('library-select-mode')));
    await tester.pump();
    expect(find.byKey(const Key('library-select-visible')), findsOneWidget);
    expect(find.byKey(const Key('library-delete-selected')), findsOneWidget);
    expect(find.byKey(const Key('library-edit-selected')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-section-viewer-closed')),
        findsOneWidget);
    expect(find.byKey(const Key('settings-section-backup-closed')),
        findsOneWidget);
    await tester.ensureVisible(find.text('뷰어·로딩 설정'));
    await tester.tap(find.text('뷰어·로딩 설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-webtoon-setting')), findsOneWidget);
    expect(find.byKey(const Key('data-saver-setting')), findsOneWidget);
    expect(find.byKey(const Key('reader-tap-navigation-setting')), findsOneWidget);
    await tester.ensureVisible(find.text('서재 데이터·백업'));
    // ensureVisible updates scroll position; allow a frame for layout/hit testing.
    await tester.pumpAndSettle();
    await tester.tap(find.text('서재 데이터·백업'));
    await tester.pumpAndSettle();
    expect(find.text('JSON 백업'), findsWidgets);
    expect(find.text('Excel 내보내기'), findsWidgets);
  });

  testWidgets('mobile navigation and live library search work without dummy data',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const HypViewerApp());
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('링크로 작품 찾기'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('library-search-input')), '없는 작품',
    );
    await tester.pump();
    expect(find.text('통합 작품 검색'), findsOneWidget);
    expect(find.textContaining('내 서재에서 찾지 못했어'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('library-search-input')), '',
    );
    await tester.pump();
    expect(find.text('링크로 작품 찾기'), findsOneWidget);
  });
}
