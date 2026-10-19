import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/ui/reader_navigation_focus.dart';

void main() {
  testWidgets('returning from reader does not reopen the search keyboard',
      (tester) async {
    final searchFocus = FocusNode(debugLabel: 'library-search');
    final dashboardFocus = FocusNode(debugLabel: 'dashboard-shortcuts');
    final searchController = TextEditingController();
    addTearDown(() {
      searchFocus.dispose();
      dashboardFocus.dispose();
      searchController.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: Focus(
      focusNode: dashboardFocus,
      autofocus: true,
      child: Builder(builder: (dashboardContext) => Scaffold(
        body: Column(children: [
          TextField(
            key: const Key('library-search-input'),
            controller: searchController,
            focusNode: searchFocus,
          ),
          FilledButton(
            key: const Key('open-reader'),
            onPressed: () => ReaderNavigationFocus.show(
              returnFocus: dashboardFocus,
              isMounted: () => dashboardContext.mounted,
              openReader: () => Navigator.of(dashboardContext).push<void>(
                MaterialPageRoute(builder: (readerContext) => Scaffold(
                  body: Center(child: FilledButton(
                    key: const Key('reader-back'),
                    onPressed: () => Navigator.of(readerContext).pop(),
                    child: const Text('Back'),
                  )),
                )),
              ),
            ),
            child: const Text('Open'),
          ),
        ]),
      )),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('library-search-input')), 'Pochi');
    await tester.pump();
    expect(searchFocus.hasPrimaryFocus, isTrue);

    await tester.tap(find.byKey(const Key('open-reader')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsOneWidget);
    expect(searchFocus.hasFocus, isFalse);
    await tester.tap(find.byKey(const Key('reader-back')));
    await tester.pumpAndSettle();

    expect(searchController.text, 'Pochi');
    expect(searchFocus.hasFocus, isFalse,
        reason: 'Returning from the reader must not reopen the mobile keyboard');
    expect(dashboardFocus.hasPrimaryFocus, isTrue);

    // Tapping Search manually must still open input as normal.
    await tester.tap(find.byKey(const Key('library-search-input')));
    await tester.pump();
    expect(searchFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('hardware back after reader also leaves the search unfocused',
      (tester) async {
    final dashboardFocus = FocusNode();
    final searchFocus = FocusNode();
    addTearDown(() {
      dashboardFocus.dispose();
      searchFocus.dispose();
    });
    late BuildContext dashboardContext;
    await tester.pumpWidget(MaterialApp(home: Focus(
      focusNode: dashboardFocus,
      child: Builder(builder: (context) {
        dashboardContext = context;
        return Scaffold(body: Column(children: [
          TextField(key: const Key('search'), focusNode: searchFocus),
          FilledButton(
            key: const Key('open'),
            onPressed: () => ReaderNavigationFocus.show(
              returnFocus: dashboardFocus,
              isMounted: () => dashboardContext.mounted,
              openReader: () => Navigator.of(dashboardContext).push<void>(
                  MaterialPageRoute(builder: (_) =>
                      const Scaffold(body: Text('Reading')))),
            ),
            child: const Text('Open'),
          ),
        ]));
      }),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search')));
    await tester.pump();
    expect(searchFocus.hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('Reading'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Reading'), findsNothing);
    expect(searchFocus.hasFocus, isFalse);
    expect(dashboardFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('online result bottom sheet does not refocus search on close',
      (tester) async {
    final search = FocusNode(debugLabel: 'online-search');
    final dashboard = FocusNode(debugLabel: 'dashboard-shortcuts');
    final controller = TextEditingController();
    addTearDown(() {
      search.dispose();
      dashboard.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: Focus(
      focusNode: dashboard,
      autofocus: true,
      child: Builder(builder: (root) => Scaffold(body: Column(children: [
        TextField(
          key: const Key('online-search-field'),
          controller: controller,
          focusNode: search,
        ),
        FilledButton(
          key: const Key('open-online-result'),
          onPressed: () => ReaderNavigationFocus.showResult<void>(
            returnFocus: dashboard,
            isMounted: () => root.mounted,
            openRoute: () => showModalBottomSheet<void>(
              context: root,
              builder: (sheet) => SafeArea(child: FilledButton(
                key: const Key('close-online-result'),
                onPressed: () => Navigator.of(sheet).pop(),
                child: const Text('Close result'),
              )),
            ),
          ),
          child: const Text('Open result'),
        ),
      ]))),
    )));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('online-search-field')), 'gallery title');
    await tester.pump();
    expect(search.hasPrimaryFocus, isTrue);

    await tester.tap(find.byKey(const Key('open-online-result')));
    await tester.pumpAndSettle();
    expect(search.hasFocus, isFalse);
    await tester.tap(find.byKey(const Key('close-online-result')));
    await tester.pumpAndSettle();

    expect(controller.text, 'gallery title');
    expect(search.hasFocus, isFalse);
    expect(dashboard.hasPrimaryFocus, isTrue);
    await tester.tap(find.byKey(const Key('online-search-field')));
    await tester.pump();
    expect(search.hasPrimaryFocus, isTrue);
  });

  testWidgets('web search route Cancel and Apply preserve text but not focus',
      (tester) async {
    final search = FocusNode(debugLabel: 'web-search');
    final dashboard = FocusNode(debugLabel: 'dashboard-shortcuts');
    final controller = TextEditingController();
    String? selected;
    addTearDown(() {
      search.dispose();
      dashboard.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: Focus(
      focusNode: dashboard,
      autofocus: true,
      child: Builder(builder: (root) => Scaffold(body: Column(children: [
        TextField(
          key: const Key('web-search-field'),
          controller: controller, focusNode: search,
        ),
        FilledButton(
          key: const Key('open-web-result'),
          onPressed: () async {
            selected = await ReaderNavigationFocus.showResult<String?>(
              returnFocus: dashboard,
              isMounted: () => root.mounted,
              openRoute: () => Navigator.of(root).push<String>(
                MaterialPageRoute(builder: (page) => Scaffold(
                  body: FilledButton(
                    key: const Key('apply-web-result'),
                    onPressed: () => Navigator.of(page).pop('work-1234567'),
                    child: const Text('Apply'),
                  ),
                )),
              ),
            );
          },
          child: const Text('Open browser'),
        ),
      ]))),
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('web-search-field')), 'pochi');
    await tester.pump();
    expect(search.hasPrimaryFocus, isTrue);

    await tester.tap(find.byKey(const Key('open-web-result')));
    await tester.pumpAndSettle();
    expect(search.hasFocus, isFalse);
    await tester.tap(find.byKey(const Key('apply-web-result')));
    await tester.pumpAndSettle();
    expect(selected, 'work-1234567');
    expect(controller.text, 'pochi');
    expect(search.hasFocus, isFalse);
    expect(dashboard.hasPrimaryFocus, isTrue);

    // Reopen, then cancel via Android back: it must not restore the IME.
    await tester.tap(find.byKey(const Key('web-search-field')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-web-result')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(search.hasFocus, isFalse);
    expect(dashboard.hasPrimaryFocus, isTrue);
  });

}
