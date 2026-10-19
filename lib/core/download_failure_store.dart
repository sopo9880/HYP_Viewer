import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Terminal failures are separate from pending jobs. Failed works must NOT be
/// restored on app resume/restart, and are retried only by an explicit tap.
class FailedDownload {
  final String workId;
  final String source;
  final String code;
  const FailedDownload(this.workId, this.source, this.code);
}

class DownloadFailureStore {
  final Directory? baseDirectory;
  DownloadFailureStore({this.baseDirectory});

  Future<Map<String, FailedDownload>>? _loaded;
  Future<void> _pendingWrite = Future<void>.value();

  Future<File> get _file async {
    final root = baseDirectory ?? await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return File(root.path + Platform.pathSeparator + 'hyp_download_failures.json');
  }

  Future<Map<String, FailedDownload>> load() async =>
      Map<String, FailedDownload>.from(await (_loaded ??= _read()));

  Future<Map<String, FailedDownload>> _read() async {
    final file = await _file;
    Object? lastError;
    var found = false;
    for (final path in [file.path, file.path + '.previous']) {
      final candidate = File(path);
      if (!await candidate.exists()) continue;
      found = true;
      try {
        final raw = jsonDecode(await candidate.readAsString());
        if (raw is! Map || raw['version'] != 1 || raw['failed'] is! List) {
          throw const FormatException('실패한 다운로드 목록이 손상됐어.');
        }
        final failures = <String, FailedDownload>{};
        for (final item in (raw['failed'] as List).take(5000)) {
          if (item is! Map) continue;
          final id = item['id'];
          final source = item['source'];
          final code = item['code'];
          if (id is String && RegExp(r'^\d{1,12}$').hasMatch(id) &&
              (source == 'hitomi' || source == 'json') &&
              code is String && RegExp(r'^[A-Z0-9_]{3,80}$').hasMatch(code)) {
            failures[id] = FailedDownload(id, source as String, code);
          }
        }
        return failures;
      } catch (error) {
        lastError = error;
      }
    }
    if (found) {
      throw StateError('실패한 다운로드 목록 복구 실패: $lastError');
    }
    return <String, FailedDownload>{};
  }

  Future<void> record(String workId, {
    required String source, required String code,
  }) {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('잘못된 작품 번호야.');
    }
    if (source != 'hitomi' && source != 'json') {
      throw ArgumentError.value(source, 'source');
    }
    if (!RegExp(r'^[A-Z0-9_]{3,80}$').hasMatch(code)) {
      throw ArgumentError.value(code, 'code');
    }
    return _mutate((items) =>
        items[workId] = FailedDownload(workId, source, code));
  }

  Future<void> remove(String workId) {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      throw const FormatException('잘못된 작품 번호야.');
    }
    return _mutate((items) => items.remove(workId));
  }

  /// Dismiss only the terminal-failure journal entries. The approved
  /// download queue, library, saved CBZ files and reading history are not
  /// modified. Reuses the existing serialized, atomic file writer.
  Future<void> clear() => _mutate((items) => items.clear());

  Future<void> _mutate(void Function(Map<String, FailedDownload>) edit) {
    final write = _pendingWrite.then((_) async {
      final current = await (_loaded ??= _read());
      final updated = Map<String, FailedDownload>.from(current);
      edit(updated);
      final file = await _file;
      final staged = File(file.path + '.tmp');
      final previous = File(file.path + '.previous');
      await staged.writeAsString(jsonEncode({
        'version': 1,
        'failed': [
          for (final entry in updated.values)
            {'id': entry.workId, 'source': entry.source, 'code': entry.code}
        ],
      }), flush: true);
      var moved = false;
      try {
        if (await file.exists()) {
          if (await previous.exists()) await previous.delete();
          await file.rename(previous.path);
          moved = true;
        }
        await staged.rename(file.path);
      } catch (_) {
        if (moved && !await file.exists() && await previous.exists()) {
          await previous.rename(file.path);
        }
        rethrow;
      } finally {
        if (await staged.exists()) await staged.delete();
      }
      _loaded = Future.value(updated);
    });
    _pendingWrite = write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }
}

/// Show the automatic-retry-stopped notice only once per unchanged set of
/// blocked works. A newly blocked set can be reported, and explicit removal
/// of failure records resets the gate.
class TerminalFailureNoticePolicy {
  String? _lastBlockedSignature;

  bool shouldNotify(Iterable<String> workIds) {
    final ids = workIds.toSet().toList()..sort();
    if (ids.isEmpty) return false;
    final signature = ids.join(',');
    if (signature == _lastBlockedSignature) return false;
    _lastBlockedSignature = signature;
    return true;
  }

  void reset() => _lastBlockedSignature = null;
}
