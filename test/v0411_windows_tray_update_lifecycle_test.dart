import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/updates.dart';
import 'package:hyp_viewer/core/windows_tray_state.dart';

void main() {
  test('idle X quits uses native close while hide-to-tray intercepts', () {
    final state = WindowsTrayState();
    expect(state.preventClose, true); // default keep-in-tray
    expect(state.needsExitConfirmation, false);
    state.exitOnClose = true;
    expect(state.preventClose, false);
    state.activeLeases = 1;
    expect(state.preventClose, true);
    expect(state.needsExitConfirmation, true);
    state.activeLeases = 0;
    expect(state.preventClose, false);
    state.installerActive = true;
    expect(state.preventClose, true);
    expect(state.needsExitConfirmation, true);
    state.resetInstaller();
    expect(state.preventClose, false);
    state.exitOnClose = false;
    expect(state.preventClose, true);
  });

  test('gallery progress, queue and pause controls never mix with installer', () {
    final state = WindowsTrayState()..activeLeases = 1;
    state.setGalleryProgress(18, 42,
        currentWorkId: '123456', pendingCount: 3, isPaused: false);
    state.canPause = true;
    expect(state.galleryPercent, 42);
    expect(state.queuedCount, 3);
    expect(state.showPause, true);
    expect(state.canCancel, true);
    state.paused = true;
    expect(state.showPause, true);
    state.installerActive = true;
    state.installerProgress = .314;
    expect(state.installerPercent, 31);
    expect(state.showPause, false);
    state.resetInstaller();
    expect(state.showPause, true);
    state.activeLeases = 0;
    state.resetGallery();
    state.queuedCount = 0;
    expect(state.canCancel, false);
    expect(state.galleryPercent, null);
  });

  test('finished downloads yield one batched notification count', () {
    final state = WindowsTrayState();
    state.recordCompletion();
    state.recordCompletion();
    expect(state.takeCompletions(), 2);
    expect(state.takeCompletions(), 0);
  });

  test('updates diagnose interrupted native exits without leaking URLs', () {
    const interrupted = '2026-10-18T00:01:00Z begin\n'
        '2026-10-18T00:01:01Z download-request-start\n'
        '2026-10-18T00:01:02Z download-first-chunk\n';
    expect(UpdateDiagnostics.unfinishedPhase(interrupted),
        'download-first-chunk');
    expect(UpdateDiagnostics.unfinishedPhase(
        interrupted + '2026-10-18T00:01:03Z failed\n'), isNull);
    expect(UpdateDiagnostics.unfinishedPhase(
        interrupted + '2026-10-18T00:01:03Z end\n'), isNull);
    expect(UpdateDiagnostics.unfinishedPhase(
        interrupted + '2026-10-18T00:01:03Z interrupted-detected\n'), isNull);
    expect(UpdateDiagnostics.unfinishedPhase(
        interrupted + '2026-10-18T00:01:03Z verified\n'), isNull);
    expect(UpdateDiagnostics.unfinishedPhase('garbage'), isNull);
    expect(interrupted, isNot(contains('https://')));
  });

  test('Windows X-close uses native policy and restores after downloads', () {
    final tray = File('lib/core/background_download_runtime.dart')
        .readAsStringSync().replaceAll('\r\n', '\n');
    expect(tray, contains('await windowManager.setPreventClose(desired);'));
    expect(tray, contains('final desired = state.preventClose;'));
    expect(tray, contains('else if (state.hasActiveTransfers || _appliedGuard != false)'));
    expect(tray, contains('onTrayIconMouseDown()'));
    expect(tray, contains('onTrayIconRightMouseDown()'));
    expect(tray, contains('onTrayMenuItemClick(MenuItem item)'));
    expect(tray, contains('case \'recent\':'));
    expect(tray, contains('case \'pause\':'));
    expect(tray, contains('case \'cancel\':'));
    expect(tray, contains('case \'update\':'));
    expect(tray, contains('case \'exit\':'));
    expect(tray, contains('LocalNotification('));
    expect(tray, contains('window_exit.log'));
  });

  test('updater resets its flag in its OWN finally; library never clears it', () {
    final main = File('lib/main.dart')
        .readAsStringSync().replaceAll('\r\n', '\n');
    final updaterStart = main.indexOf('Future<void> _downloadInstaller(');
    final updaterEnd = main.indexOf('/// One GitHub update check', updaterStart);
    expect(updaterStart, greaterThan(0));
    expect(updaterEnd, greaterThan(updaterStart));
    final updater = main.substring(updaterStart, updaterEnd);
    expect(updater, contains('await _backgroundDownloads.setInstallerDownloadActive(true);'));
    expect(updater, contains('await _backgroundDownloads.setInstallerDownloadActive(false);'));
    expect(updater, contains("await UpdateDiagnostics.record('failed');"));
    expect(updater, contains("await UpdateDiagnostics.record('end');"));
    expect(updater, contains('onPhase: (stage) async {'));
    expect(main.substring(0, updaterStart),
        isNot(contains('setInstallerDownloadActive(false)')));
    final updates = File('lib/core/updates.dart').readAsStringSync();
    for (final phase in [
      'checksum-start', 'storage-ready', 'request-start',
      'response-headers', 'stream-start', 'first-chunk',
      'bytes-written', 'sha256-verified',
    ]) {
      expect(updates, contains(phase));
    }
  });

  test('main wires tray actions to existing download and reader features', () {
    final main = File('lib/main.dart').readAsStringSync();
    for (final text in [
      'configureTrayActions(',
      'openRecent: () => unawaited(_openRecentFromTray())',
      'checkUpdates: () => unawaited(_checkRelease())',
      'togglePause: _pauseOrResumeReaderDownload',
      'cancelDownloads: () => unawaited(_cancelDownloadsFromTray())',
      'updateTrayTransferControls(',
      'markDownloadCompleted(work.workId)',
      'updateTrayQueueCount(',
      'updateTrayInstallerProgress(value)',
      "'browser-download'",
    ]) {
      expect(main, contains(text));
    }
  });

  test('version and 0.x release request stay aligned', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = File('lib/core/release_version.dart').readAsStringSync();
    final request = File('.github/release-request.txt')
        .readAsStringSync().trim();
    final release = pubspec.split('version: ').last.split('+').first.trim();
    expect(release, startsWith('0.'));
    expect(version, contains("const String hypReleaseVersion = '$release';"));
    expect(request, 'v$release');
    expect(pubspec, contains('local_notifier: ^0.1.6'));
  });
}
