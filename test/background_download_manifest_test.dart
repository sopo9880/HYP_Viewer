import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android background service uses declared dataSync foreground type', () async {
    final xml = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    expect(xml, contains('FOREGROUND_SERVICE_DATA_SYNC'));
    expect(xml, contains('FOREGROUND_SERVICE'));
    expect(xml, contains('IsolateHolderService'));
    expect(xml, contains('android:foregroundServiceType="dataSync"'));
    expect(xml, contains('POST_NOTIFICATIONS'));
  });

  test('Android download progress replaces the existing foreground notification', () async {
    final source = await File('android/app/src/main/kotlin/com/sopo9880/hyp_viewer/MainActivity.kt')
        .readAsString();
    expect(source, contains('private val ongoingNotificationId = 1'));
    expect(source, contains('private val foregroundChannelId = "flutter_background"'));
    expect(source, contains('.setProgress(total, done, preparing)'));
    expect(source, contains('requestNotificationPermission'));
    expect(source, contains('notificationPermissionRequest'));
    final runtime = await File('lib/core/background_download_runtime.dart')
        .readAsString();
    expect(runtime, contains('Future<T> holdQueue<T>'));
    expect(runtime,
        contains("invokeMethod<bool>('requestNotificationPermission')"));
    final main = await File('lib/main.dart').readAsString();
    expect(main, contains('_backgroundDownloads.holdQueue('));
    expect(main, contains('await _initialLibraryRead.future'));
    expect(source, contains('notificationManager().notify(ongoingNotificationId, notification)'));
    expect(source, contains('KeyEvent.ACTION_UP'));
    expect(source, contains('volumeHandler.postDelayed(tick, 500L)'));
    expect(source, contains('"pauseVolumeRepeat"'));
    expect(source, contains('"consumeOpenDownloads"'));
  });
}
