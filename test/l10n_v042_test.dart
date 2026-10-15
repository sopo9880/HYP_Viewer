import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v0.4.2 settings, search, and work info translate in all locales',
      () async {
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));
    expect(ko.settingsDataSaverNote, contains('요청'));
    expect(en.settingsDataSaverNote, contains('network'));
    expect(ja.settingsTapZonesNote, contains('30'));
    expect(en.workInfoHeader, 'Work Information');
    expect(ja.workInfoProgress(4, 60), contains('60%'));
    expect(en.workInfoFromPage(5), contains('5'));
    expect(ko.searchFieldCount('작가', 10), contains('10'));
    expect(en.searchFieldCount('Artist', 10), contains('Artist'));
    expect(ja.searchLanguageChip('日本語'), contains('日本語'));
    expect(en.searchResultMatches('Artist, Series'), contains('Series'));
    expect(en.coverCropHelp, contains('Drag'));
    expect(ja.coverCropImageFailed, contains('画像'));
    expect(en.androidSecurityNotice, contains('SHA-256'));
    expect(ja.androidSecurityNotice, contains('SHA-256'));
  });
}
