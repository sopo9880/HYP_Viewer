import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/web_viewer_store.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';
import 'package:hyp_viewer/ui/hero_banner.dart';
import 'package:hyp_viewer/ui/hyp_theme.dart';
import 'package:hyp_viewer/ui/web_library_visuals.dart';

void main() {
  testWidgets('visual WEB shelves use HYP cover grid, search, progress and sort',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = WebViewerStore();
    addTearDown(store.dispose);
    var opened = 0;
    Widget shelf() => MaterialApp(
      theme: HypTheme.dark,
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(
        child: WebVisualLibrary(
          store: store,
          title: 'WEB 서재',
          subtitle: '표지가 있는 서재',
          icon: Icons.library_books,
          emptyMessage: '비어 있음',
          items: [
            WebVisualEntry(
              id: 'first', title: 'First work', subtitle: 'First author',
              detail: '1 / 6', modifiedAt: DateTime.utc(2026, 11, 6),
              progress: 0.0, downloaded: true, icon: Icons.book,
              onOpen: () => opened++,
            ),
            WebVisualEntry(
              id: 'second', title: 'Second work', subtitle: 'Second author',
              detail: '4 / 6', modifiedAt: DateTime.utc(2026, 11, 7),
              progress: 0.6, downloaded: true, icon: Icons.book,
              onOpen: () => opened++,
            ),
          ],
        ),
      )),
    );
    await tester.pumpWidget(shelf());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('web-visual-cover-grid')), findsOneWidget);
    expect(find.byKey(const Key('web-visual-card-first')), findsOneWidget);
    expect(find.byKey(const Key('web-visual-card-second')), findsOneWidget);
    expect(find.byType(WebCoverPreview), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('web-visual-card-second')));
    await tester.pump();
    expect(opened, 1);
    await tester.enterText(
      find.byKey(const Key('web-visual-library-search')), 'First');
    await tester.pump();
    expect(find.byKey(const Key('web-visual-card-first')), findsOneWidget);
    expect(find.byKey(const Key('web-visual-card-second')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('web-visual-library-search')), '');
    await tester.pump();
    expect(find.byKey(const Key('web-visual-card-second')), findsOneWidget);
  });

  testWidgets('HYP banner accepts WEB branding without changing default HYP',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(760, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: HypTheme.dark,
      home: Scaffold(body: HypHeroBanner(
        viewerLabel: 'WEB Viewer',
        bannerIcon: Icons.public,
        slideTitles: const ['Web custom 1', 'Web custom 2', 'Web custom 3'],
        slideDescriptions: const ['A', 'B', 'C'],
        onOpenLibrary: () {},
        onOpenDownloads: () {},
      )),
    ));
    await tester.pump();
    expect(find.text('WEB Viewer'), findsOneWidget);
    expect(find.text('Web custom 1'), findsOneWidget);
    await tester.tap(find.byTooltip('다음 소개'));
    await tester.pump();
    expect(find.text('Web custom 2'), findsOneWidget);
  });
}
