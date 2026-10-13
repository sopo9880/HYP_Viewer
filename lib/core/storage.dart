import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'work.dart';

class LibraryStorage {
  Future<File> get file async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(dir.path + Platform.pathSeparator + 'hyp_library.json');
  }

  Future<LibraryBackup> load() async {
    final f = await file;
    if (!await f.exists()) {
      return const LibraryBackup(works: [], collections: []);
    }
    return LibraryBackup.decode(await f.readAsString());
  }

  Future<void> save(LibraryBackup backup) async {
    final f = await file;
    final tmp = File(f.path + '.tmp');
    await tmp.writeAsString(backup.encode(), flush: true);
    if (await f.exists()) await f.copy(f.path + '.previous');
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
  }
}
