import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/android_dpi.dart';
import 'package:hyp_viewer/core/hitomi_web_search.dart';

void main() {
  test('Android MainActivity and native worker accept the same five presets',
      () async {
    final activity = await File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/MainActivity.kt',
    ).readAsString();
    final native = await File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/AndroidDpiService.kt',
    ).readAsString();
    final presets = await File(
      'android/app/src/main/kotlin/com/sopo9880/hyp_viewer/AndroidDpiPresets.kt',
    ).readAsString();

    final setOfNames = RegExp(r'val names = setOf\(([\s\S]*?)\)')
        .firstMatch(presets);
    expect(setOfNames, isNotNull);
    final nativeNames = RegExp(r'"([^"]+)"')
        .allMatches(setOfNames!.group(1)!)
        .map((match) => match.group(1)!)
        .toList();

    expect(nativeNames, AndroidDpiPreferences.presets);
    expect(nativeNames, contains('all_dnsredir'));
    expect(activity, contains('if (preset !in AndroidDpiPresets.names)'));
    expect(activity, contains('?: "all_dnsredir"'));
    expect(activity, isNot(contains('preset !in listOf("standard"')));
    expect(native, contains('AndroidDpiPresets.proxyOptions(preset, blacklist)'));
  });

  test('manual website search opens home with blank query, preserves query search',
      () {
    expect(HitomiWebSearch.searchUri(''), Uri.parse('https://hitomi.la/'));
    expect(HitomiWebSearch.searchUri('  '), Uri.parse('https://hitomi.la/'));
    expect(HitomiWebSearch.searchUri('artist:pochi').toString(),
        'https://hitomi.la/search.html?artist%3Apochi');
    expect(HitomiWebSearch.allowedOrigin(
        HitomiWebSearch.searchUri('')), isTrue);
  });

  test('manual website button works without query and home capture is visible',
      () async {
    final dashboard = await File('lib/ui/hyp_dashboard.dart').readAsString();
    expect(dashboard, contains('onPressed: _search.text.trim().length <= 150'));
    expect(dashboard, isNot(contains(
        'onPressed: _search.text.trim().isNotEmpty &&')));
    expect(dashboard, contains('_webSearchResults.isNotEmpty;'));
    expect(dashboard, contains("'web-results'"));
    expect(dashboard, contains('_webSearchResults.clear();'));
    expect(dashboard, contains('if (_webSearchResults.isNotEmpty) {'));
    expect(dashboard, contains('if (_searchScope == \'local\') _searchScope = \'all\';'));
    // Automatic search should *not* fire on an empty query.
    expect(dashboard, contains('AutoWebSearchPolicy.shouldSearch('));
  });

  test('returning from web and online result sheets avoids search IME focus',
      () async {
    final dashboard = await File('lib/ui/hyp_dashboard.dart').readAsString();
    final focus = await File('lib/ui/reader_navigation_focus.dart')
        .readAsString();
    expect(dashboard, contains('showResult<List<HitomiWebGallery>?>('));
    expect(dashboard, contains('onTap: group.length > 1'));
    expect(dashboard.split('ReaderNavigationFocus.showResult<void>(').length,
        3, reason: 'Both the online edition and work sheets must be covered');
    expect(focus, contains('returnFocus.requestFocus();'));
    expect(focus, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(focus, contains('return await openRoute();'));
  });
}
