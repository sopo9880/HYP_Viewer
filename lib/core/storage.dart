import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'work.dart';

/// Serializes all library writes and never deletes the current JSON before
/// the replacement is safely staged. Important on Windows (errno 32).
class LibraryStorage {
  final Directory? baseDirectory;
  LibraryStorage({this.baseDirectory});

  Future<void> _lastWrite = Future<void>.value();
  int _stagingSequence = 0;

  Future<File> get file async {
    final dir = baseDirectory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(dir.path + Platform.pathSeparator + 'hyp_library.json');
  }

  Future<LibraryBackup> load() async {
    final target = await file;
    final previous = File(target.path + '.previous');
    final candidates = <File>[target, previous];
    // Include recently staged, fully flushed copies from an interrupted
    // rename. Only syntactically valid JSON backups can be recovered.
    final dir = target.parent;
    if (await dir.exists()) {
      final staged = await dir.list(followLinks: false)
          .where((entity) => entity is File &&
              entity.path.startsWith(target.path + '.tmp.'))
          .cast<File>()
          .toList();
      staged.sort((a, b) => b.path.compareTo(a.path));
      candidates.addAll(staged.take(6));
    }
    var foundData = false;
    Object? lastError;
    for (final candidate in candidates) {
      if (!await candidate.exists()) continue;
      foundData = true;
      try {
        final contents = await candidate.readAsString();
        final backup = LibraryBackup.decode(contents);
        // The previous backup is never deleted or modified during reading.
        return backup;
      } catch (error) {
        lastError = error;
      }
    }
    if (foundData) {
      // Never turn a corrupted/non-readable library into an empty one:
      // otherwise the next save could destroy the only recoverable copy.
      throw StateError('서재 저장 파일을 복구하지 못했어: $lastError');
    }
    return const LibraryBackup(works: [], collections: []);
  }

  /// Preview last recoverable snapshot without mutating the active library.
  Future<LibraryBackup?> readPrevious() async {
    final backup = File((await file).path + '.previous');
    if (!await backup.exists()) return null;
    return LibraryBackup.decode(await backup.readAsString());
  }

  Future<void> save(LibraryBackup backup) {
    // The returned task reports its own error, but it never poisons the queue:
    // even if one save fails, a later save gets another chance.
    final task = _lastWrite.then((_) => _writeSafely(backup));
    _lastWrite = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<void> _writeSafely(LibraryBackup backup) async {
    final target = await file;
    final previous = File(target.path + '.previous');
    final staged = File(
      target.path + '.tmp.' +
      DateTime.now().microsecondsSinceEpoch.toString() + '.' +
      (++_stagingSequence).toString(),
    );
    await staged.writeAsString(backup.encode(), flush: true);

    try {
      for (var attempt = 0; attempt < 6; attempt++) {
        var movedOld = false;
        try {
          if (await target.exists()) {
            // Keep a rollback copy without deleting the live library first.
            if (await previous.exists()) await previous.delete();
            await target.rename(previous.path);
            movedOld = true;
          }
          await staged.rename(target.path);
          return;
        } on FileSystemException {
          if (movedOld && !await target.exists() && await previous.exists()) {
            await previous.rename(target.path);
          }
          if (attempt == 5) rethrow;
          // Antivirus, indexing and other readers can temporarily lock files
          // on Windows; retry only transient file-system rename failures.
          await Future<void>.delayed(
            Duration(milliseconds: 60 * (attempt + 1)),
          );
        }
      }
    } finally {
      if (await staged.exists()) {
        try {
          await staged.delete();
        } on FileSystemException {
          // Harmless leftover staging file; never delete the live library.
        }
      }
    }
  }
}
