import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'gallery.dart';

/// Prioritized bounded queue shared by webtoon visible pages and preloads.
/// No direct foreground request can bypass the concurrency limit.
/// Duplicate requests coalesce; 429/503 trigger a shared cooldown.
class GalleryDiskCache implements GalleryPageSource {
  final GalleryPageSource source;
  final Directory? parent;
  final Directory? persistentDirectory;
  final int maxBytes;
  final int concurrency;
  // Allows deterministic in-memory widget tests without asynchronous dart:io.
  // Production readers retain the bounded on-disk cache by default.
  final bool cacheToDisk;
  final Map<int, Completer<Uint8List>> _requests = {};
  final Queue<int> _foreground = Queue<int>();
  final Queue<int> _background = Queue<int>();
  final Set<int> _finishedOnDisk = {};
  Future<Directory>? _directory;
  final List<Future<void>> _running = [];
  int _runningWorkers = 0;
  int _activeBackground = 0;
  int _writtenBytes = 0;
  bool _disposed = false;
  bool _capacityReached = false;
  DateTime? _cooldownUntil;
  DateTime? _backgroundPausedUntil;

  GalleryDiskCache(this.source, {
    this.parent,
    this.persistentDirectory,
    this.maxBytes = 750 * 1024 * 1024,
    this.concurrency = 2,
    this.cacheToDisk = true,
  }) : assert(concurrency > 0 && concurrency <= 4);

  @override int get pageCount => source.pageCount;
  @override String filename(int index) => source.filename(index);
  bool get capacityReached => _capacityReached;
  int get pendingCount => _background.length + _foreground.length;
  int get activeCount => _runningWorkers;

  Future<Directory> _getDir() => _directory ??=
      persistentDirectory != null
          ? persistentDirectory!.create(recursive: true)
          : (parent ?? Directory.systemTemp).createTemp('hyp_reader_cache_');

  @override
  Future<Uint8List> loadPage(int index) => _enqueue(index, urgent: true);

  Future<Uint8List> _enqueue(int index, {required bool urgent}) {
    if (index < 0 || index >= pageCount) {
      return Future.error(RangeError.index(index, List.filled(pageCount, 0)));
    }
    if (_disposed) return Future.error(StateError('Reader cache closed'));
    final existing = _requests[index];
    if (existing != null) {
      if (urgent && _background.remove(index)) {
        _foreground.addFirst(index);
        _drain(); // immediately reserve an urgent slot for a promoted request
      }
      return existing.future;
    }
    final completer = Completer<Uint8List>();
    _requests[index] = completer;
    if (urgent) {
      _foreground.addFirst(index);
    } else {
      _background.addLast(index);
      // Prefetch errors should not become unhandled async exceptions.
      unawaited(completer.future.then<void>((_) {},
          onError: (Object _, StackTrace __) {}));
    }
    _drain();
    return completer.future;
  }

  /// Foreground requests may use all concurrency slots. Background
  /// prefetch uses at most one slot so a long full-work download cannot
  /// occupy every connection while the reader waits for its next page.
  void _drain() {
    if (_disposed) return;
    while (_runningWorkers < concurrency &&
        (_foreground.isNotEmpty || _background.isNotEmpty)) {
      final urgent = _foreground.isNotEmpty;
      if (!urgent && _activeBackground >= 1) break;
      final index = urgent ? _foreground.removeFirst()
          : _background.removeFirst();
      final completer = _requests[index];
      if (completer == null || completer.isCompleted) continue;
      _runningWorkers++;
      if (!urgent) _activeBackground++;
      late final Future<void> task;
      task = _runOne(index, completer, urgent).whenComplete(() {
        _runningWorkers--;
        if (!urgent) _activeBackground--;
        _running.remove(task);
        if (!_disposed) _drain();
      });
      _running.add(task);
      unawaited(task.then<void>((_) {},
          onError: (Object _, StackTrace __) {}));
    }
  }

  Future<void> _runOne(
      int index, Completer<Uint8List> completer, bool urgent) async {
    try {
      if (!urgent && _capacityReached) {
        throw StateError('Reader prefetch disk budget reached');
      }
      if (!urgent && _backgroundPausedUntil != null &&
          DateTime.now().isBefore(_backgroundPausedUntil!)) {
        throw StateError('Reader prefetch paused after server errors');
      }
      final bytes = await _fetch(index);
      if (!completer.isCompleted) completer.complete(bytes);
    } catch (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    } finally {
      _requests.remove(index);
    }
  }

  Future<Uint8List> _fetch(int index) async {
    File? file;
    if (cacheToDisk) {
      final dir = await _getDir();
      file = File(dir.path + Platform.pathSeparator +
          'page_' + index.toString() + '.bin');
      if (await file.exists()) {
        final size = await file.length();
        if (size > 0 && size <= GalleryArchive.maxSingleImageBytes) {
          _finishedOnDisk.add(index);
          return file.readAsBytes();
        }
        await file.delete();
      }
    }

    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (_disposed) throw StateError('Reader cache closed');
      final delay = _cooldownUntil?.difference(DateTime.now()) ??
          Duration.zero;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      try {
        final bytes = await source.loadPage(index);
        if (!cacheToDisk) {
          // The reader's own Future cache retains these bytes in tests.
          _finishedOnDisk.add(index);
        } else if (!_disposed && !_capacityReached && bytes.isNotEmpty &&
            _writtenBytes + bytes.length <= maxBytes) {
          try {
            await file!.writeAsBytes(bytes);
            _writtenBytes += bytes.length;
            _finishedOnDisk.add(index);
          } on FileSystemException {
            _capacityReached = true;
          }
        } else if (_writtenBytes + bytes.length > maxBytes) {
          _capacityReached = true;
        }
        return bytes;
      } catch (error) {
        lastError = error;
        if (!_isTransient(error)) rethrow;
        if (attempt == 3) {
          // A gallery-wide outage must not cause a queued full download to
          // hammer every remaining image. Visible pages may still retry.
          _backgroundPausedUntil =
              DateTime.now().add(const Duration(minutes: 2));
          rethrow;
        }
        final pause = Duration(milliseconds: 700 * (1 << attempt));
        final until = DateTime.now().add(pause);
        if (_cooldownUntil == null || _cooldownUntil!.isBefore(until)) {
          _cooldownUntil = until;
        }
      }
    }
    throw StateError('Could not load page $index: $lastError');
  }

  static bool _isTransient(Object error) =>
      RegExp(r'(?:HTTP[ :]?\s*|응답하지 않았어:\s*)(429|502|503|504)\b')
          .hasMatch(error.toString()) ||
      error is TimeoutException ||
      error.toString().contains('Connection reset by peer');

  void warmAround(int page, int radius) {
    if (_disposed || _capacityReached ||
        (_backgroundPausedUntil != null &&
            DateTime.now().isBefore(_backgroundPausedUntil!))) return;
    final first = (page - radius).clamp(0, pageCount).toInt();
    final last = (page + radius + 1).clamp(0, pageCount).toInt();
    for (var i = first; i < last; i++) {
      if (!_finishedOnDisk.contains(i) && !_requests.containsKey(i)) {
        _enqueue(i, urgent: false);
      }
    }
  }

  void warmAll({int startingAt = 0}) {
    if (_disposed || _capacityReached ||
        (_backgroundPausedUntil != null &&
            DateTime.now().isBefore(_backgroundPausedUntil!))) return;
    final start = startingAt.clamp(0, pageCount).toInt();
    for (var i = start; i < pageCount; i++) {
      if (!_finishedOnDisk.contains(i) && !_requests.containsKey(i)) {
        _enqueue(i, urgent: false);
      }
    }
    for (var i = 0; i < start; i++) {
      if (!_finishedOnDisk.contains(i) && !_requests.containsKey(i)) {
        _enqueue(i, urgent: false);
      }
    }
  }

  /// Remove a failed/corrupt cached page so a manual retry really requests
  /// fresh bytes. Every other downloaded page and offline CBZ is untouched.
  Future<void> invalidate(int index) async {
    if (_disposed || index < 0 || index >= pageCount) return;
    _finishedOnDisk.remove(index);
    if (!cacheToDisk) return;
    try {
      final folder = await _getDir();
      final page = File(folder.path + Platform.pathSeparator +
          'page_' + index.toString() + '.bin');
      if (!await page.exists()) return;
      final size = await page.length();
      await page.delete();
      _writtenBytes = (_writtenBytes - size).clamp(0, maxBytes).toInt();
      if (_writtenBytes < maxBytes) _capacityReached = false;
    } on FileSystemException {
      // A disk failure should not prevent retrying a visible online page.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _foreground.clear();
    _background.clear();
    for (final pending in _requests.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Reader cache closed'));
      }
    }
    await Future.wait(_running.toList().map((f) =>
        f.then<void>((_) {}, onError: (Object _, StackTrace __) {})));
    final dir = await _directory;
    if (persistentDirectory == null && dir != null && await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
