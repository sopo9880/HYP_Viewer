import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v0.4.3 aliases, provenance, reader, stats and comments translate',
      () async {
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));

    expect(ko.editionAliasTitles, contains('번역'));
    expect(en.editionAliasHelp, contains('verified'));
    expect(ja.workSourceCount(3), contains('3'));
    expect(en.workSourceInvalid, contains('HTTPS'));
    expect(ko.searchProgress(3, 7), contains('3/7'));
    expect(en.onlineLinkedShelf('Sky Wind'), contains('Sky Wind'));
    expect(ja.youtubeMoreVideos, contains('動画'));
    expect(en.youtubeCommentsPartial, contains('comments'));
    expect(ja.readerTooltipNext, contains('PageDown'));
    expect(en.readerTooltipShowTools, contains('Show'));
    expect(en.readerFailedPage(7), contains('7'));
    expect(ko.readingSaveReportFailed('IOException'), contains('IOException'));
    expect(ja.readingActivityDay('2026-10-16', 2), contains('2'));
    expect(en.readingStatsSummary(20, 5, 30, 10), contains('30'));
    expect(ko.readingStatsEraseConfirm, contains('되돌릴 수 없어'));
  });
}
