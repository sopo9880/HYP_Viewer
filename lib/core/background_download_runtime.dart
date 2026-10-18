import 'dart:async';
import 'dart:io';

import 'package:flutter_background/flutter_background.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'i18n.dart';
import 'windows_tray_state.dart';

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

  /// Pure-Dart update flag: keep Windows X-close confirmations without
  /// invoking any tray/taskbar plugin while streaming installer bytes.
  Future<void> setInstallerDownloadActive(bool active) async {
    if (Platform.isWindows) await _desktop.setInstallerDownloadActive(active);
  }

  /// On Windows, connect existing application actions to a useful tray.
  /// No Dart callbacks are persisted and Android behavior is unchanged.
  void configureTrayActions({
    void Function()? openRecent,
    void Function()? checkUpdates,
    void Function()? togglePause,
    void Function()? cancelDownloads,
  }) {
    if (Platform.isWindows) {
      _desktop.setActions(
        openRecent: openRecent,
        checkUpdates: checkUpdates,
        togglePause: togglePause,
        cancelDownloads: cancelDownloads,
      );
    }
  }

  void updateTrayRecentTitle(String title) {
    if (Platform.isWindows) _desktop.updateRecent(title);
  }

  void updateTrayTransferControls({
    required bool canPause,
    required bool paused,
  }) {
    if (Platform.isWindows) {
      _desktop.updateTransferControls(canPause: canPause, paused: paused);
    }
  }

  void updateTrayQueueCount(int pending) {
    if (Platform.isWindows) _desktop.updateQueueCount(pending);
  }

  /// The installer progress stays in Dart memory on every chunk; native
  /// menu changes are limited to coarse/slow updates.
  void updateTrayInstallerProgress(double progress) {
    if (Platform.isWindows) _desktop.updateInstallerProgress(progress);
  }

  void markDownloadCompleted(String workId) {
    if (Platform.isWindows) _desktop.markCompleted(workId);
  }

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

/// Persistent Windows tray: single click toggles, double click restores,
/// right click exposes the current transfer and controls. Idle X=exit uses
/// the native Windows close path instead of a Flutter destroy round trip.
class _DesktopDownloadTray with WindowListener, TrayListener {
  final WindowsTrayState state = WindowsTrayState();
  Future<void>? _initializing;
  Future<void> _guardSerial = Future<void>.value();
  bool _initialized = false;
  bool _closing = false;
  bool? _appliedGuard;
  bool _notificationsReady = false;
  LocalNotification? _lastNotification;
  bool _menuRefreshing = false;
  DateTime? _lastMenuUpdate;
  DateTime? _lastInstallerMenu;
  int _lastInstallerPercent = -1;
  Timer? _leftClickTimer;
  Future<bool> Function()? _confirmExit;
  void Function()? _openDownloads;
  void Function()? _openRecent;
  void Function()? _checkUpdates;
  void Function()? _togglePause;
  void Function()? _cancelDownloads;

  String _local(String ko, String en, String ja) {
    final language = HypLanguage.selected.value;
    return language == 'en' ? en : language == 'ja' ? ja : ko;
  }

  String _trimLabel(String label, [int max = 42]) {
    final safe = label.trim().replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    return safe.length > max ? safe.substring(0, max - 1) + '…' : safe;
  }

  void setActions({
    void Function()? openRecent,
    void Function()? checkUpdates,
    void Function()? togglePause,
    void Function()? cancelDownloads,
  }) {
    _openRecent = openRecent;
    _checkUpdates = checkUpdates;
    _togglePause = togglePause;
    _cancelDownloads = cancelDownloads;
    unawaited(_refreshMenu());
  }

  void setDownloadsNavigationHandler(void Function()? handler) {
    _openDownloads = handler;
  }

  void setWindowExitConfirmationHandler(Future<bool> Function()? handler) {
    _confirmExit = handler;
  }

  Future<void> initialize() =>
      _initializing ??= _initializeCore();

  Future<void> _initializeCore() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);
    // Safe before settings load: default action is hide-to-tray.
    await windowManager.setPreventClose(true);
    _appliedGuard = true;
    await trayManager.setIcon('assets/icons/hyp_tray.ico');
    await trayManager.setToolTip('HYP Viewer');
    _initialized = true;
    await _refreshMenu();
    // Never block startup on a Windows notification shortcut/COM plugin.
    unawaited(_setupNotifications());
  }

  Future<void> _setupNotifications() async {
    try {
      await localNotifier.setup(
        appName: 'HYP Viewer',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _notificationsReady = true;
    } catch (_) {
      _notificationsReady = false;
    }
  }

  /// Serialize guard changes: a late async reply cannot restore an old
  /// prevent-close value after the user changes settings.
  Future<void> _syncCloseGuard() {
    if (!_initialized) return Future<void>.value();
    final task = _guardSerial.then((_) async {
      final desired = state.preventClose;
      if (_appliedGuard == desired) return;
      await windowManager.setPreventClose(desired);
      _appliedGuard = desired;
    });
    _guardSerial = task.catchError((Object _) {});
    return task;
  }

  Future<void> setCloseWindowExits(bool enabled) async {
    await initialize();
    state.exitOnClose = enabled;
    await _syncCloseGuard();
    await _refreshMenu();
  }

  Future<void> setInstallerDownloadActive(bool active) async {
    await initialize();
    state.installerActive = active;
    if (!active) state.installerProgress = 0;
    // One native setting transition per updater start/end, not per chunk.
    await _syncCloseGuard();
    await _refreshMenu();
  }

  void updateInstallerProgress(double value) {
    if (!value.isFinite || !state.installerActive) return;
    state.installerProgress = value.clamp(0.0, 1.0).toDouble();
    final percent = state.installerPercent;
    final now = DateTime.now();
    if (_lastInstallerMenu != null &&
        now.difference(_lastInstallerMenu!) < const Duration(seconds: 5) &&
        percent != 100) return;
    if (percent < 100 && _lastInstallerPercent >= 0 &&
        percent - _lastInstallerPercent < 10) return;
    _lastInstallerPercent = percent;
    _lastInstallerMenu = now;
    unawaited(_refreshMenu());
  }

  void updateRecent(String title) {
    final next = _trimLabel(title, 65);
    if (next == state.recentTitle) return;
    state.recentTitle = next;
    unawaited(_refreshMenu());
  }

  void updateTransferControls({
    required bool canPause,
    required bool paused,
  }) {
    if (state.canPause == canPause && state.paused == paused) return;
    state.canPause = canPause;
    state.paused = paused;
    unawaited(_refreshMenu());
  }

  void updateQueueCount(int pending) {
    final next = pending < 0 ? 0 : pending;
    if (state.queuedCount == next) return;
    state.queuedCount = next;
    unawaited(_refreshMenu());
  }

  void markCompleted(String workId) {
    state.recordCompletion();
  }

  String _progressLabel() {
    if (state.installerActive) {
      return _local('앱 업데이트 다운로드', 'App update download',
              'アプリ更新ダウンロード') + ' ' +
          state.installerPercent.toString() + '%';
    }
    if (state.activeLeases == 0) {
      return _local('진행 중인 다운로드 없음', 'No active downloads',
          '進行中のダウンロードなし');
    }
    final percent = state.galleryPercent;
    return [
      if (state.workId.isNotEmpty) '#' + state.workId,
      if (state.paused) _local('일시정지', 'Paused', '一時停止'),
      if (percent == null)
        _local('다운로드 준비 중', 'Preparing download', 'ダウンロード準備中')
      else
        percent.toString() + '% (' +
            state.pagesDone.toString() + '/' +
            state.pagesTotal.toString() + ')',
      if (state.queuedCount > 0)
        _local('대기', 'Queued', '待機') + ' ' +
            state.queuedCount.toString(),
    ].join(' · ');
  }

  Future<void> _refreshMenu() async {
    if (!_initialized || _menuRefreshing || _closing) return;
    _menuRefreshing = true;
    try {
      final items = <MenuItem>[
        MenuItem(key: 'status', label: _trimLabel(_progressLabel(), 105),
            disabled: true),
        if (state.showPause)
          MenuItem(key: 'pause', label: state.paused
              ? _local('다운로드 계속', 'Resume download', 'ダウンロード再開')
              : _local('다운로드 일시정지', 'Pause download', 'ダウンロード一時停止')),
        if (state.canCancel)
          MenuItem(key: 'cancel', label: _local('전체 다운로드 취소...',
              'Cancel all downloads...', 'すべてのダウンロードをキャンセル...')),
        MenuItem.separator(),
        if (state.recentTitle.isNotEmpty)
          MenuItem(key: 'recent',
              label: _local('이어보기: ', 'Continue reading: ', '続きを読む: ') +
                  _trimLabel(state.recentTitle)),
        MenuItem(key: 'downloads', label: _local('다운로드 관리 열기',
            'Open downloads manager', 'ダウンロード管理を開く')),
        MenuItem(key: 'update', disabled: state.installerActive,
            label: _local('업데이트 확인...', 'Check for updates...',
                '更新を確認...')),
        MenuItem(key: 'toggle', label: _local('창 열기 / 숨기기',
            'Show / hide window', 'ウィンドウ表示 / 非表示')),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: _local('완전 종료',
            'Quit completely', '完全に終了')),
      ];
      await trayManager.setContextMenu(Menu(items: items));
      _lastMenuUpdate = DateTime.now();
    } catch (_) {
      // Native tray errors must not terminate an otherwise working app.
    } finally {
      _menuRefreshing = false;
    }
  }

  Future<void> started() async {
    await initialize();
    state.activeLeases++;
    await _syncCloseGuard();
    await _refreshMenu();
  }

  Future<void> updateProgress(int done, int total, {
    String workId = '', int queuedCount = 0, bool paused = false,
  }) async {
    if (!_initialized) return;
    state.setGalleryProgress(done, total, currentWorkId: workId,
        pendingCount: queuedCount, isPaused: paused);
    final now = DateTime.now();
    if (_lastMenuUpdate != null &&
        now.difference(_lastMenuUpdate!) < const Duration(seconds: 2)) return;
    await _refreshMenu();
  }

  Future<void> finished() async {
    if (state.activeLeases > 0) state.activeLeases--;
    if (state.activeLeases == 0) {
      state.resetGallery();
      state.queuedCount = 0;
      final successCount = state.takeCompletions();
      // Announce one completed batch only when the main window is hidden.
      if (successCount > 0) unawaited(_notifyCompleted(successCount));
    }
    await _syncCloseGuard();
    await _refreshMenu();
  }

  Future<void> _notifyCompleted(int count) async {
    if (!_notificationsReady || _closing) return;
    try {
      if (await windowManager.isVisible()) return;
      final notification = LocalNotification(
        title: _local('HYP Viewer 다운로드 완료',
            'HYP Viewer download completed', 'HYP Viewer ダウンロード完了'),
        body: _local('다운로드한 작품 ', 'Downloaded works: ', 'ダウンロード完了: ') +
            count.toString() + _local('개', '', '件'),
      );
      _lastNotification = notification;
      notification.onClick = () {
        unawaited(_openDownloadsManager());
      };
      notification.onClose = (_) {
        if (identical(_lastNotification, notification)) {
          _lastNotification = null;
        }
      };
      await notification.show();
    } catch (_) {
      // System notifications may be disabled; transfers are still complete.
    }
  }

  Future<void> _recordExit(String stage, int elapsedMs) async {
    try {
      final root = Platform.environment['LOCALAPPDATA'];
      if (root == null || root.isEmpty) return;
      final directory = Directory(root + Platform.pathSeparator +
          'HYP_Viewer' + Platform.pathSeparator + 'diagnostics');
      await directory.create(recursive: true);
      final file = File(directory.path + Platform.pathSeparator +
          'window_exit.log');
      await file.writeAsString(
        DateTime.now().toUtc().toIso8601String() +
            ' stage=' + stage + ' elapsedMs=' + elapsedMs.toString() + '\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // Exit diagnostics must never hold the window open.
    }
  }

  /// Explicit tray quit or X during an active download. The idle X->quit
  /// path never enters here: Windows closes it natively, without await.
  Future<void> _requestExit({bool fromTray = false}) async {
    if (_closing) return;
    _closing = true;
    final clock = Stopwatch()..start();
    try {
      if (state.needsExitConfirmation) {
        if (fromTray) await _show();
        final confirm = _confirmExit;
        if (confirm == null || !await confirm()) return;
      }
      _leftClickTimer?.cancel();
      _lastNotification = null;
      unawaited(_recordExit('confirmed', clock.elapsedMilliseconds));
      await windowManager.hide(); // Show an immediate X response.
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      try {
        await trayManager.destroy().timeout(
            const Duration(milliseconds: 750));
      } catch (_) {
        // The destroyed process removes the Windows tray icon anyway.
      }
      unawaited(_recordExit('destroy', clock.elapsedMilliseconds));
      await windowManager.destroy();
    } finally {
      _closing = false;
    }
  }

  @override
  void onWindowClose() {
    if (!state.exitOnClose) {
      unawaited(windowManager.hide());
    } else if (state.hasActiveTransfers || _appliedGuard != false) {
      // A fast click may arrive while the async guard is changing. Do not
      // leave an intercepted X stranded without a destroy request.
      unawaited(_requestExit());
    } else {
      // preventClose=false: the OS closes the last window immediately.
      unawaited(_recordExit('native-idle-close', 0));
    }
  }

  Future<void> _show() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.focus();
  }

  Future<void> _toggleVisibility() async {
    if (await windowManager.isVisible()) {
      if (await windowManager.isMinimized()) {
        await _show();
      } else {
        await windowManager.hide();
      }
    } else {
      await _show();
    }
  }

  Future<void> _openDownloadsManager() async {
    await _show();
    _openDownloads?.call();
  }

  Future<void> _openUpdateCheck() async {
    await _show();
    _checkUpdates?.call();
  }

  @override
  void onTrayIconMouseDown() {
    // Version 0.5.x reports single presses only. Delay one click briefly
    // so a double click cannot hide a window that it just restored.
    if (_leftClickTimer?.isActive == true) {
      _leftClickTimer?.cancel();
      _leftClickTimer = null;
      unawaited(_show());
    } else {
      _leftClickTimer = Timer(const Duration(milliseconds: 280), () {
        _leftClickTimer = null;
        unawaited(_toggleVisibility());
      });
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    // The plugin displays the menu itself on right click. Refresh once
    // using the in-memory state (no download network calls).
    unawaited(_refreshMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'toggle':
        unawaited(_toggleVisibility());
        break;
      case 'recent':
        unawaited(_show().then((_) {
          _openRecent?.call();
        }));
        break;
      case 'downloads':
        unawaited(_openDownloadsManager());
        break;
      case 'update':
        unawaited(_openUpdateCheck());
        break;
      case 'pause':
        if (state.showPause) _togglePause?.call();
        break;
      case 'cancel':
        if (state.canCancel) {
          unawaited(_openDownloadsManager().then((_) {
            _cancelDownloads?.call();
          }));
        }
        break;
      case 'exit':
        unawaited(_requestExit(fromTray: true));
        break;
    }
  }
}
