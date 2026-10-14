import 'dart:io';

/// Best-effort cleanup of reader previews/full-size page caches.
/// Does not touch offline CBZ archives, covers, JSON backups, or active work.
class ReaderCachePruner {
  static DateTime? _lastRun;

  static Future<void> prune(Directory root, {required String activeWorkId,
      int maxBytes = 1024 * 1024 * 1024}) async {
    final now = DateTime.now();
    if (_lastRun != null && now.difference(_lastRun!) <
        const Duration(hours: 12)) return;
    _lastRun = now;
    if (!await root.exists()) return;
    try {
      final saved = <({File file, DateTime modified, int size})>[];
      var bytes = 0;
      await for (final workDir in root.list(followLinks: false)) {
        if (workDir is! Directory) continue;
        if (workDir.uri.pathSegments
            .where((segment) => segment.isNotEmpty).last == activeWorkId) {
          continue;
        }
        await for (final entry in workDir.list(
            recursive: true, followLinks: false)) {
          if (entry is! File || !entry.path.endsWith('.bin')) continue;
          try {
            final stat = await entry.stat();
            if (now.difference(stat.modified) > const Duration(days: 21)) {
              await entry.delete();
              continue;
            }
            bytes += stat.size;
            saved.add((file: entry, modified: stat.modified, size: stat.size));
          } catch (_) {}
        }
      }
      // Oldest content goes first, preserving current reader and newest pages.
      saved.sort((a, b) => a.modified.compareTo(b.modified));
      for (final item in saved) {
        if (bytes <= maxBytes) break;
        try {
          await item.file.delete();
          bytes -= item.size;
        } catch (_) {}
      }
    } catch (_) {
      // Cache cleanup must never prevent a book from opening.
    }
  }
}
