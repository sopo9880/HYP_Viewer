import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'updates.dart';

/// App-owned updater files only. Never traverses shared Downloads, Gallery,
/// WEB/Series CBZ data, or other directories.
class UpdateApkCleanup {
  final Directory? baseDirectory;
  const UpdateApkCleanup({this.baseDirectory});

  static final RegExp _ownedFileName = RegExp(
    r'^HYP_Viewer_v0\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\.apk'
    r'(?:\.part|\.metadata\.json)?$',
  );
  static final RegExp _version = RegExp(
    r'^0\.[0-9]+\.[0-9]+(?:\.[0-9]+)?$',
  );

  Future<Directory> get _base async =>
      baseDirectory ?? await getApplicationSupportDirectory();

  Future<Directory> get _updatesFolder async {
    final root = await _base;
    return Directory(root.path + Platform.pathSeparator + 'hyp_updates');
  }

  /// Does not create the directory or read any unrelated content.
  Future<List<File>> _ownedFiles() async {
    final directory = await _updatesFolder;
    if (!await directory.exists()) return [];
    final files = <File>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue; // Avoid symlink and nested directories.
      final name = entry.uri.pathSegments.last;
      if (_ownedFileName.hasMatch(name)) files.add(entry);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<UpdateApkInventory> scan() async {
    final files = await _ownedFiles();
    var bytes = 0;
    final names = <String>[];
    for (final file in files) {
      if (!await file.exists()) continue;
      names.add(file.uri.pathSegments.last);
      bytes += await file.length();
    }
    return UpdateApkInventory(names, bytes);
  }

  /// An unfinished installation must keep its verified APK for a retry.
  Future<bool> canCleanup({
    required String installedVersion,
    bool downloadInProgress = false,
  }) async {
    if (downloadInProgress || !_version.hasMatch(installedVersion)) return false;
    final root = await _base;
    final pending = File(
      root.path + Platform.pathSeparator + 'hyp_pending_update_version.txt',
    );
    if (!await pending.exists()) return true;
    final pendingVersion = (await pending.readAsString()).trim();
    if (!_version.hasMatch(pendingVersion)) return false; // Fail closed.
    return !UpdateService.isNewer(pendingVersion, installedVersion);
  }

  /// Purges ALL matching old/new updater APKs and their .part/.metadata
  /// companions once the running installed version is confirmed. No CBZ,
  /// HYP/WEB libraries, update diagnostics, or manual Downloads are touched.
  Future<UpdateApkCleanupResult> cleanup({
    required String installedVersion,
    bool downloadInProgress = false,
  }) async {
    if (!await canCleanup(
        installedVersion: installedVersion,
        downloadInProgress: downloadInProgress)) {
      return const UpdateApkCleanupResult(0, 0, 0, blocked: true);
    }
    var removed = 0;
    var bytes = 0;
    var failed = 0;
    for (final file in await _ownedFiles()) {
      try {
        if (!await file.exists()) continue;
        final size = await file.length();
        await file.delete();
        removed++;
        bytes += size;
      } catch (_) {
        failed++;
      }
    }
    return UpdateApkCleanupResult(removed, bytes, failed);
  }
}

class UpdateApkInventory {
  final List<String> names;
  final int bytes;
  const UpdateApkInventory(this.names, this.bytes);
  int get count => names.length;
}

class UpdateApkCleanupResult {
  final int removed;
  final int bytes;
  final int failed;
  final bool blocked;
  const UpdateApkCleanupResult(
    this.removed, this.bytes, this.failed, {this.blocked = false});
}
