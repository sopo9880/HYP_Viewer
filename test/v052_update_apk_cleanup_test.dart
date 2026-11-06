import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/update_apk_cleanup.dart';

void main() {
  test('scans and clears only HYP-owned updater APK and companions', () async {
    final root = await Directory.systemTemp.createTemp('hyp-apk-cleanup-');
    try {
      final updates = Directory(root.path + '/hyp_updates')
        ..createSync(recursive: true);
      for (final name in [
        'HYP_Viewer_v0.2.2.apk',
        'HYP_Viewer_v0.5.1.apk',
        'HYP_Viewer_v0.5.1.apk.part',
        'HYP_Viewer_v0.5.1.apk.metadata.json',
        'HYP_Viewer_Setup_v0.5.1.exe',
        'unrelated.apk',
        'update_diagnostics.log',
        'HYP_Viewer_v1.0.0.apk',
      ]) {
        File(updates.path + '/' + name).writeAsStringSync('12345');
      }
      Directory(updates.path + '/nested').createSync();
      File(updates.path + '/nested/HYP_Viewer_v0.4.0.apk')
          .writeAsStringSync('nested');
      File(root.path + '/HYP_Viewer_v0.4.0.apk').writeAsStringSync('outside');
      final cleaner = UpdateApkCleanup(baseDirectory: root);
      final before = await cleaner.scan();
      expect(before.count, 4);
      expect(before.bytes, 20);
      final result = await cleaner.cleanup(installedVersion: '0.5.2');
      expect(result.blocked, isFalse);
      expect(result.removed, 4);
      expect(result.failed, 0);
      expect(result.bytes, 20);
      expect((await cleaner.scan()).count, 0);
      expect(File(updates.path + '/unrelated.apk').existsSync(), isTrue);
      expect(File(updates.path + '/update_diagnostics.log').existsSync(), isTrue);
      expect(File(updates.path + '/HYP_Viewer_v1.0.0.apk').existsSync(), isTrue);
      expect(File(updates.path + '/HYP_Viewer_Setup_v0.5.1.exe').existsSync(), isTrue);
      expect(File(updates.path + '/nested/HYP_Viewer_v0.4.0.apk').existsSync(), isTrue);
      expect(File(root.path + '/HYP_Viewer_v0.4.0.apk').existsSync(), isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('keeps installer and partial bytes while a newer update is pending',
      () async {
    final root = await Directory.systemTemp.createTemp('hyp-apk-pending-');
    try {
      final updates = Directory(root.path + '/hyp_updates')
        ..createSync(recursive: true);
      final current = File(updates.path + '/HYP_Viewer_v0.5.2.apk')
        ..writeAsStringSync('signed');
      File(root.path + '/hyp_pending_update_version.txt')
          .writeAsStringSync('0.5.2');
      final cleaner = UpdateApkCleanup(baseDirectory: root);
      final waiting = await cleaner.cleanup(installedVersion: '0.5.1');
      expect(waiting.blocked, isTrue);
      expect(current.existsSync(), isTrue);
      final active = await cleaner.cleanup(
          installedVersion: '0.5.2', downloadInProgress: true);
      expect(active.blocked, isTrue);
      expect(current.existsSync(), isTrue);
      final installed = await cleaner.cleanup(installedVersion: '0.5.2');
      expect(installed.blocked, isFalse);
      expect(installed.removed, 1);
      expect(current.existsSync(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('fails closed on an invalid pending-version marker', () async {
    final root = await Directory.systemTemp.createTemp('hyp-apk-marker-');
    try {
      final updates = Directory(root.path + '/hyp_updates')
        ..createSync(recursive: true);
      final file = File(updates.path + '/HYP_Viewer_v0.1.0.apk')
        ..writeAsStringSync('old');
      File(root.path + '/hyp_pending_update_version.txt')
        .writeAsStringSync('malformed');
      final cleaner = UpdateApkCleanup(baseDirectory: root);
      expect((await cleaner.cleanup(installedVersion: '0.5.2')).blocked, isTrue);
      expect((await cleaner.cleanup(installedVersion: 'not-a-version')).blocked,
        isTrue);
      expect(file.existsSync(), isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
