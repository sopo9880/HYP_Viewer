import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/l10n/app_localizations.dart';

void main() {
  test('generated language bundles contain the same translations', () async {
    const languages = ['ko', 'en', 'ja'];
    Set<String>? expected;
    for (final language in languages) {
      final file = File('lib/l10n/app_$language.arb');
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final keys = data.keys.where((value) => !value.startsWith('@')).toSet();
      expect(data['@@locale'], language);
      expect(keys, isNotEmpty);
      if (expected == null) {
        expected = keys;
      } else {
        expect(keys, expected);
      }
    }
    expect(AppLocalizations.supportedLocales.length, 3);
  });
}
