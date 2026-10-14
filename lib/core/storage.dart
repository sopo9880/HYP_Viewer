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
    if (await target.exists()) {
      return LibraryBackup.decode(await target.readAsString());
    }
    final previous = File(target.path + '.previous');
    // Recover from a crash between renaming the old file and committing
    // the new staged file. Do not mutate the original rollback copy here.
    if (await previous.exists()) {
      return LibraryBackup.decode(await previous.readAsString());
    }
    return const LibraryBackup(works: [], collections: []);
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
