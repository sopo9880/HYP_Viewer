import 'dart:async';
import 'dart:io';

import 'package:flutter_background/flutter_background.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Only active user-approved transfers hold an Android foreground-service
/// notification. Android OS/force-stop may interrupt it: the persisted queue
/// and per-page checkpoints are recovered on the next application launch.
class BackgroundDownloadRuntime {
  BackgroundDownloadRuntime._();
  static final BackgroundDownloadRuntime instance =
      BackgroundDownloadRuntime._();

  int _leases = 0;
  Future<void> _serial = Future<void>.value();
  final _desktop = _DesktopDownloadTray();

  bool get hasTransfers => _leases > 0;

  Future<void> configureDesktop() async {
    if (Platform.isWindows) await _desktop.initialize();
  }

  Future<void> acquire() => _exclusive(() async {
    if (_leases == 0) {
      if (Platform.isAndroid) {
        final ok = await FlutterBackground.initialize(
          androidConfig: FlutterBackgroundAndroidConfig(
            notificationTitle: 'HYP Viewer',
            notificationText: '승인된 작품을 오프라인으로 다운로드 중',
            notificationImportance: AndroidNotificationImportance.normal,
            enableWifiLock: false,
            shouldRequestBatteryOptimizationsOff: false,
          ),
        );
        if (!ok || !await FlutterBackground.enableBackgroundExecution()) {
          throw StateError('Android 백그라운드 실행 권한이 없어. '
              '알림/배터리 설정을 확인한 뒤 다시 시도해줘.');
        }
      } else if (Platform.isWindows) {
        await _desktop.started();
      }
    }
    _leases++;
  });

  Future<void> release() => _exclusive(() async {
    if (_leases == 0) return;
    _leases--;
    if (_leases != 0) return;
    if (Platform.isAndroid) {
      try {
        if (FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      } catch (_) { /* OS may have already stopped the service. */ }
    } else if (Platform.isWindows) {
      await _desktop.finished();
    }
  });

  Future<void> setProgress(int done, int total) async {
    if (!Platform.isWindows || total <= 0) return;
    try { await windowManager.setProgressBar(done / total); } catch (_) {}
  }

  Future<void> clearProgress() async {
    if (!Platform.isWindows) return;
    try { await windowManager.setProgressBar(0); } catch (_) {}
  }

  Future<void> _exclusive(Future<void> Function() callback) {
    final next = _serial.then((_) => callback());
    _serial = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}

/// Closing a Windows window while transferring hides it to the system tray,
/// not the task manager. Explicit "Exit" keeps resumable pages for next launch.
class _DesktopDownloadTray with WindowListener, TrayListener {
  bool _initialized = false;
  bool _iconVisible = false;
  bool _finishedWhileHidden = false;
  int _active = 0;

  Future<void> initialize() async {
    if (_initialized) return;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    _initialized = true;
  }

  Future<void> started() async {
    await initialize();
    _finishedWhileHidden = false;
    if (_iconVisible) { _active++; return; }
    await trayManager.setIcon('assets/icons/hyp_tray.ico');
    await trayManager.setToolTip('HYP Viewer · 다운로드 중');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'HYP Viewer 열기'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: '다운로드 중단하고 종료'),
    ]));
    _iconVisible = true;
    _active++;
  }

  Future<void> finished() async {
    if (_active > 0) _active--;
    if (_active > 0) return;
    if (await windowManager.isVisible()) {
      await _hideIcon();
    } else {
      // Keep a recovery route after the last job finishes while hidden.
      _finishedWhileHidden = true;
      if (_iconVisible) {
        await trayManager.setToolTip('HYP Viewer · 다운로드 완료');
        await trayManager.setContextMenu(Menu(items: [
          MenuItem(key: 'show', label: 'HYP Viewer 열기'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '종료'),
        ]));
      }
    }
  }

  Future<void> _hideIcon() async {
    if (!_iconVisible) return;
    await trayManager.destroy();
    _iconVisible = false;
    _finishedWhileHidden = false;
  }

  @override
  void onWindowClose() async {
    if (_active > 0 || _finishedWhileHidden) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
    if (_active == 0) await _hideIcon();
  }

  @override
  void onTrayIconMouseDown() { unawaited(_show()); }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'show') {
      unawaited(_show());
    } else if (item.key == 'exit') {
      // Closing intentionally stops the Dart process. The persisted queue and
      // complete page files are read back on the next app launch.
      unawaited(windowManager.destroy());
    }
  }
}
