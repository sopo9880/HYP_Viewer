import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/social_web_capture.dart';

void main() {
  test('visible Instagram comment rows survive double JSON serialization', () {
    final data = jsonEncode({
      'url': 'https://www.instagram.com/reel/ABC12345/',
      'title': 'Public post',
      'description': 'Public caption 3172801',
      'comments': ['userA 3172801', 'userB 3999999', 'userA 3172801'],
      'images': ['https://cdninstagram.com/a.jpg', 'file:///local'],
      'loginRequired': false,
    });
    final result = SocialWebCapture.parse(jsonEncode(data))!;
    expect(result.comments, hasLength(2));
    expect(result.imageUrls, hasLength(1));
    expect(result.combinedText, contains('3999999'));
    expect(result.limited, true);
  });

  test('login wall stays explicit; zero comments means none loaded', () {
    final result = SocialWebCapture.parse({
      'url': 'https://www.instagram.com/p/ABC12345/',
      'title': 'Instagram',
      'description': '',
      'comments': <String>[],
      'images': <String>[],
      'loginRequired': true,
    })!;
    expect(result.loginRequired, true);
    expect(result.comments, isEmpty);
  });

  test('web script is read-only, but supports dialog and listitem comments', () {
    final js = SocialWebCapture.javascript;
    expect(js, contains('[role="dialog"] article'));
    expect(js, contains('[role="listitem"]'));
    expect(js, contains('loginRequired'));
    expect(js, isNot(contains('document.cookie')));
    expect(js, isNot(contains('fetch(')));
  });
}
