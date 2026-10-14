import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/i18n.dart';

void main() {
  testWidgets('language choices retain their native names across locales',
      (tester) async {
    HypLanguage.selected.value = 'ko';
    addTearDown(() => HypLanguage.selected.value = 'ko');
    await tester.pumpWidget(ValueListenableBuilder<String>(
      valueListenable: HypLanguage.selected,
      builder: (context, code, _) => MaterialApp(
        locale: Locale(code),
        home: Scaffold(body: DropdownButton<String>(
          value: code,
          items: const [
            DropdownMenuItem(value: 'ko', child: Text('한국어')),
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'ja', child: Text('日本語')),
          ],
          onChanged: (value) => HypLanguage.selected.value = value ?? 'ko',
        )),
      ),
    ));
    for (final language in ['ko', 'en', 'ja']) {
      HypLanguage.selected.value = language;
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('한국어'), findsWidgets);
      expect(find.text('English'), findsWidgets);
      expect(find.text('日本語'), findsWidgets);
      await tester.tap(find.text('日本語').last);
      await tester.pumpAndSettle();
    }
  });
}
