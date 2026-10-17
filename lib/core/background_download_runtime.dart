import 'dart:async';
import 'dart:io';

import 'package:flutter_background/flutter_background.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'i18n.dart';

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
  static const MethodChannel _downloadChannel =
      MethodChannel('hyp_viewer/download_notification');
  void Function()? _onOpenDownloads;
  bool? _notificationsAllowed;

  /// Android 13+ may keep foreground transfers running while hiding their
  /// notification from the drawer when the user denies notification access.
  bool? get notificationsAllowed => _notificationsAllowed;

  /// Own ONE lease for an entire batch, including metadata lookup between
  /// works. Per-work nested leases must not stop the Android service.
  Future<T> holdQueue<T>(Future<T> Function() process) async {
    await acquire();
    try {
      return await process();
    } finally {
      await release();
    }
  }

  void setDownloadsNavigationHandler(void Function()? handler) {
    _onOpenDownloads = handler;
    _desktop.setDownloadsNavigationHandler(handler);
    _downloadChannel.setMethodCallHandler(handler == null ? null : (call) async {
      if (call.method == 'openDownloads') {
        await consumePendingDownloadsNavigation();
        _onOpenDownloads?.call();
      }
    });
  }

  Future<bool> consumePendingDownloadsNavigation() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _downloadChannel.invokeMethod<bool>('consumeOpenDownloads') ?? false;
    } on MissingPluginException { return false; }
    on PlatformException { return false; }
  }

  bool get hasTransfers => _leases > 0;

  void setWindowExitConfirmationHandler(Future<bool> Function()? handler) {
    _desktop.setWindowExitConfirmationHandler(handler);
  }

  Future<void> setCloseWindowExits(bool enabled) async {
    if (Platform.isWindows) await _desktop.setCloseWindowExits(enabled);
  }

  Future<void> configureDesktop() async {
    if (Platform.isWindows) await _desktop.initialize();
  }

  Future<void> acquire() => _exclusive(() async {
    if (_leases == 0) {
      if (Platform.isAndroid) {
        try {
          _notificationsAllowed = await _downloadChannel
              .invokeMethod<bool>('requestNotificationPermission');
        } on MissingPluginException {
          _notificationsAllowed = null;
        } on PlatformException {
          _notificationsAllowed = false;
        }
        try { await _downloadChannel.invokeMethod<void>('clearResult'); }
        on MissingPluginException { /* Non-Android test runner. */ }
        on PlatformException { /* Notification disabled by the user. */ }
        final ok = await FlutterBackground.initialize(
          androidConfig: FlutterBackgroundAndroidConfig(
            notificationTitle: 'HYP Viewer',
            notificationText: HypI18n.translate(
              '승인된 작품을 오프라인으로 다운로드 중',
              HypLanguage.selected.value,
            ),
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

  /// On Android update the flutter_background FOREGROUND notification ID=1,
  /// not an additional ongoing notification. The native side owns its UI.
  Future<void> setProgress(int done, int total, {
    String workId = '', bool paused = false, int queuedCount = 0,
    bool isUpdate = false, String language = 'ko',
  }) async {
    // total=0 is a real indeterminate progress state while downloading
    // metadata. A spinner is better than hiding the notification progress.
    if (total < 0) return;
    if (Platform.isAndroid) {
      try {
        await _downloadChannel.invokeMethod<void>('updateProgress', {
          'done': total == 0 ? 0 : done.clamp(0, total).toInt(),
          'total': total,
          'workId': workId, 'paused': paused,
          'queued': queuedCount, 'update': isUpdate, 'language': language,
        });
      } on MissingPluginException { /* Old Android runner. */ }
      on PlatformException { /* System notification permission blocked. */ }
    } else if (Platform.isWindows) {
      await _desktop.updateProgress(done, total, workId: workId,
          queuedCount: queuedCount, paused: paused);
      try {
        await windowManager.setProgressBar(
            total == 0 ? 0 : done.clamp(0, total) / total);
      } catch (_) {}
    }
  }

  Future<void> showDownloadResult(String workId, {
    required bool success, bool cancelled = false, String language = 'ko',
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _downloadChannel.invokeMethod<void>('showResult', {
        'workId': workId, 'success': success,
        'cancelled': cancelled, 'language': language,
      });
    } on MissingPluginException { /* Old Android runner. */ }
    on PlatformException { /* Notifications are optional. */ }
  }

  Future<void> clearProgress() async {
    if (Platform.isWindows) {
      try { await windowManager.setProgressBar(0); } catch (_) {}
    }
    // Never cancel notification ID=1 here; it belongs to the active
    // foreground service and is removed when the last lease is released.
  }

  Future<void> _exclusive(Future<void> Function() callback) {
    final next = _serial.then((_) => callback());
    _serial = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}

/// Persistent Windows tray. X hides by default, with an explicit exit menu.
class _DesktopDownloadTray with WindowListener, TrayListener {
  bool _initialized = false;
  bool _exitOnClose = false;
  bool _closing = false;
  void Function()? _openDownloads;
  Future<bool> Function()? _confirmExit;
  int _active = 0;
  String _progress = '진행 중인 다운로드 없음';
  DateTime? _lastMenuUpdate;

  void setDownloadsNavigationHandler(void Function()? handler) {
    _openDownloads = handler;
  }

  void setWindowExitConfirmationHandler(Future<bool> Function()? handler) {
    _confirmExit = handler;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    await trayManager.setIcon('assets/icons/hyp_tray.ico');
    await trayManager.setToolTip('HYP Viewer');
    _initialized = true;
    await _refreshMenu();
  }

  Future<void> setCloseWindowExits(bool enabled) async {
    await initialize();
    _exitOnClose = enabled;
    await _refreshMenu();
  }

  String _local(String ko, String en, String ja) {
    final language = HypLanguage.selected.value;
    return language == 'en' ? en : language == 'ja' ? ja : ko;
  }

  Future<void> _refreshMenu() async {
    if (!_initialized) return;
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: _local('HYP Viewer 열기',
          'Open HYP Viewer', 'HYP Viewerを開く')),
      MenuItem.separator(),
      MenuItem(key: 'progress', label: _progress, disabled: true),
      MenuItem(key: 'downloads', label: _local('다운로드 관리 열기',
          'Open Downloads Manager', 'ダウンロード管理を開く')),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: _local('완전 종료',
          'Quit Completely', '完全に終了')),
    ]));
  }

  Future<void> started() async {
    await initialize();
    _active++;
    _progress = _local('다운로드 준비 중', 'Preparing download',
        'ダウンロードを準備中');
    await _refreshMenu();
  }

  Future<void> updateProgress(int done, int total, {
    String workId = '', int queuedCount = 0, bool paused = false,
  }) async {
    if (!_initialized) return;
    final percent = total > 0 ? (done * 100 ~/ total).clamp(0, 100) : null;
    _progress = [
      if (workId.isNotEmpty) '#$workId',
      if (paused) _local('일시정지', 'Paused', '一時停止'),
      if (percent == null) _local('다운로드 준비 중',
          'Preparing download', 'ダウンロードを準備中') else '$percent% ($done/$total)',
      if (queuedCount > 0) _local('대기 $queuedCount개',
          '$queuedCount queued', '待機 $queuedCount 件'),
    ].join(' · ');
    final now = DateTime.now();
    if (_lastMenuUpdate != null &&
        now.difference(_lastMenuUpdate!) < const Duration(seconds: 1)) return;
    _lastMenuUpdate = now;
    await _refreshMenu();
  }

  Future<void> finished() async {
    if (_active > 0) _active--;
    if (_active == 0) {
      _progress = _local('진행 중인 다운로드 없음',
          'No active downloads', '進行中のダウンロードなし');
      await _refreshMenu();
    }
  }

  /// Never silently interrupt an active transfer, even when the X setting
  /// requests complete shutdown. A cancelled dialog leaves the app open.
  Future<void> _requestExit({bool fromTray = false}) async {
    if (_closing) return;
    _closing = true;
    try {
      if (_active > 0) {
        if (fromTray) await _show();
        final confirm = _confirmExit;
        if (confirm == null || !await confirm()) return;
      }
      await windowManager.destroy();
    } finally {
      _closing = false;
    }
  }

  @override
  void onWindowClose() {
    if (_exitOnClose) {
      unawaited(_requestExit());
    } else {
      unawaited(windowManager.hide());
    }
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _openDownloadsManager() async {
    await _show();
    _openDownloads?.call();
  }

  @override
  void onTrayIconMouseDown() { unawaited(_show()); }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'show') {
      unawaited(_show());
    } else if (item.key == 'downloads') {
      unawaited(_openDownloadsManager());
    } else if (item.key == 'exit') {
      unawaited(_requestExit(fromTray: true));
    }
  }
}
