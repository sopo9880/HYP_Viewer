import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all settings panels and Reading Insights sections translate', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));
    expect(en.settingsGeneral, 'Language & General');
    expect(ja.settingsGeneral, '言語・一般');
    expect(en.insightsA, 'A · Reading Overview');
    expect(ja.insightsL, 'L・統計フィルターと履歴管理');
    expect(en.insightOverview(4, 60, '50%'),
        contains('Unread 4'));
    expect(ja.insightCompletedRate(70), contains('70%'));
    expect(en.editionCoverPercent(87), contains('87%'));
    expect(ja.legacyCompletionReview, contains('読了'));
  });
}
