import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/instagram_navigation.dart';
import 'package:hyp_viewer/core/social_web_capture.dart';
import 'package:hyp_viewer/core/updates.dart';

void main() {
  test('Instagram navigation permits only trusted HTTPS content and login', () {
    expect(InstagramNavigation.isAllowed(
        Uri.parse('https://www.instagram.com/reel/ABCDEFG/')), true);
    expect(InstagramNavigation.isAllowed(
        Uri.parse('https://www.facebook.com/login/')), true);
    expect(InstagramNavigation.isAllowed(
        Uri.parse('https://m.facebook.com/login/')), true);
    expect(InstagramNavigation.isAllowed(
        Uri.parse('https://facebook.com.evil.org/login')), false);
    expect(InstagramNavigation.isAllowed(
        Uri.parse('https://instagram.com@evil.org/reel/a')), false);
    expect(InstagramNavigation.isAllowed(
        Uri.parse('http://instagram.com/reel/a')), false);
    expect(InstagramNavigation.isAllowed(
        Uri.parse('https://instagram.com:8443/reel/a')), false);
    expect(InstagramNavigation.isAllowed(
        Uri.parse('intent://instagram.com/reel/a')), false);
    expect(InstagramNavigation.isAllowed(
        Uri.parse('about:blank')), false);
    expect(InstagramNavigation.isAllowed(
        Uri.parse('about:blank'), popup: true), true);
  });

  test('desktop popup selector and user-initiated comment controls remain safe', () {
    final script = SocialWebCapture.javascript;
    expect(script, contains("commentSelectors.join(',')"));
    expect(script, contains('document.querySelectorAll'));
    expect(script, contains('fallbackCount'));
    expect(script, contains('diagnostics: diagnostics'));
    expect(script, isNot(contains('fetch(')));
    expect(script, isNot(contains('document.cookie')));
    final action = SocialWebCapture.openCommentsJavascript;
    expect(action, contains('target.click()'));
    expect(action, contains('Comment'));
    expect(action, isNot(contains('fetch(')));
    expect(action, isNot(contains('document.cookie')));
  });

  test('parses zero-comment diagnostic and keeps all session comments', () {
    final snapshot = SocialWebCapture.parse({
      'url': 'https://www.instagram.com/reel/SAMPLE01/',
      'title': 'Example',
      'description': 'caption',
      'comments': <String>[],
      'pinnedComments': <String>[],
      'images': <String>[],
      'diagnostics': 'rows=0; modal=yes; fallback=0',
      'commentAreaPresent': true,
    })!;
    expect(snapshot.collectorDiagnostics, contains('modal=yes'));
    expect(snapshot.commentAreaPresent, true);
    final history = SocialCommentAccumulator();
    history.add(snapshot);
    expect(history.count, 0);
    history.add(SocialWebCapture(
      url: snapshot.url,
      title: 'Example',
      description: '',
      comments: ['writer: 1234567'],
      imageUrls: const [],
    ));
    expect(history.count, 1);
    history.add(snapshot);
    expect(history.combinedText, contains('1234567'));
  });

  test('Android starts unobstructed and popup requests keep native window IDs', () {
    final source = File('lib/ui/instagram_source_inspector.dart')
        .readAsStringSync();
    expect(source, contains('supportMultipleWindows: true'));
    expect(source, contains('javaScriptCanOpenWindowsAutomatically: true'));
    expect(source, contains('windowId: windowId'));
    expect(source, contains('request.hasGesture == false'));
    expect(source, contains('if (_resultsOpen) DraggableScrollableSheet('));
    expect(source, isNot(contains('initialChildSize: 0.22')));
    expect(source, contains('source: SocialWebCapture.openCommentsJavascript'));
    expect(source, contains('_popupWeb ?? _web'));
  });

  test('progress limiter prevents excessive native or Flutter redraw calls', () {
    final throttle = UpdateProgressLimiter();
    final now = DateTime.utc(2026, 10, 17);
    expect(throttle.shouldEmit(0.0, now), true);
    expect(throttle.shouldEmit(0.01,
        now.add(const Duration(milliseconds: 100))), false);
    expect(throttle.shouldEmit(0.08,
        now.add(const Duration(milliseconds: 140))), true);
    expect(throttle.shouldEmit(0.09,
        now.add(const Duration(milliseconds: 200))), false);
    expect(throttle.shouldEmit(0.10,
        now.add(const Duration(milliseconds: 600))), true);
    expect(throttle.shouldEmit(1.0,
        now.add(const Duration(milliseconds: 610))), true);
    expect(throttle.shouldEmit(1.0,
        now.add(const Duration(milliseconds: 700))), false);
  });

  test('Windows updater is isolated from native download tray', () {
    final source = File('lib/main.dart').readAsStringSync();
    final begin = source.indexOf('Future<void> _downloadInstaller(');
    final end = source.indexOf('/// One GitHub update check', begin);
    expect(begin, greaterThan(-1));
    expect(end, greaterThan(begin));
    final updater = source.substring(begin, end);
    expect(updater, contains('UpdateProgressLimiter()'));
    expect(updater, contains("phase = 'download'"));
    expect(updater, contains('UpdateDiagnostics.record('));
    expect(updater, contains('if (Platform.isAndroid) {'));
    expect(updater, contains(
        'if (Platform.isAndroid) {\n              unawaited(_backgroundDownloads.setProgress('));
  });

  test('diagnostic log records update stages without failing the download',
      () async {
    final temp = await Directory.systemTemp.createTemp('hyp-update-log-');
    addTearDown(() => temp.delete(recursive: true));
    await UpdateDiagnostics.record('begin', baseDirectory: temp);
    await UpdateDiagnostics.record('download',
        error: const FileSystemException('simulated'),
        baseDirectory: temp);
    final file = File(temp.path + Platform.pathSeparator +
        'hyp_updates' + Platform.pathSeparator + 'update_diagnostics.log');
    final data = await file.readAsString();
    expect(data, contains('begin'));
    expect(data, contains('download type='));
    expect(data, isNot(contains('https://')));
  });
}
