import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/i18n.dart';
import 'package:hyp_viewer/core/social_web_capture.dart';
import 'package:hyp_viewer/ui/image_search_placeholder.dart';

void main() {
  testWidgets('image lookup is an independent, inactive page', (tester) async {
    HypLanguage.selected.value = 'ko';
    await tester.pumpWidget(
      const MaterialApp(home: ImageSearchPlaceholder()));
    expect(find.text('이미지로 작품 찾기'), findsNWidgets(2));
    expect(find.text(
      '이미지 검색은 준비 중이야. 이번 버전에서는 이미지 검색을 실행하지 않아.'),
      findsOneWidget);
    expect(find.byIcon(Icons.image_search_outlined), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  test('manual social text inspection no longer exposes image searches', () {
    final source = File('lib/ui/visual_source_inspector.dart')
        .readAsStringSync();
    expect(source, isNot(contains('onPressed: _busy ? null : _pickImages')));
    expect(source, isNot(contains('onPressed: _busy || !hasImages ? null : _searchRemote')));
    expect(source, isNot(contains('onPressed: _busy || !hasImages ? null : _analyze')));
    expect(source, isNot(contains('onPressed: _busy || !_webReady ? null :\n                              _sampleFrames')));
  });

  test('public Instagram snapshot can observe dynamic visible comments', () {
    expect(SocialWebCapture.observerJavascript, contains('MutationObserver'));
    expect(SocialWebCapture.javascript, contains('Pinned'));
    expect(SocialWebCapture.observerJavascript, isNot(contains('fetch(')));
    expect(SocialWebCapture.observerJavascript, isNot(contains('document.cookie')));
  });

  test('single-instance launch guard applied in Windows CI and release', () {
    const script = 'scripts/patch_windows_single_instance.py';
    expect(File(script).existsSync(), isTrue);
    expect(File(script).readAsStringSync(),
      contains('CreateMutexW'));
    for (final path in [
      '.github/workflows/verify.yml', '.github/workflows/release.yml',
    ]) {
      expect(File(path).readAsStringSync(), contains(script));
    }
  });
}
