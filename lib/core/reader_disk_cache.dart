import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'gallery.dart';

/// Disk-backed, bounded-concurrency gallery preloading for mobile readers.
/// Only pages from the current opened work are written to an ephemeral cache.
/// The cache is removed on reader close, including interrupted warm-ups.
class GalleryDiskCache implements GalleryPageSource {
  final GalleryPageSource source;
  final Directory? parent;
  final int maxBytes;
  final int concurrency;
  final Map<int, Future<Uint8List>> _loading = {};
  final Set<int> _pending = {};
  Future<Directory>? _directory;
  Future<void>? _pump;
  int _writtenBytes = 0;
  bool _disposed = false;
  bool _capacityReached = false;

  GalleryDiskCache(this.source, {
    this.parent,
    this.maxBytes = 750 * 1024 * 1024,
    this.concurrency = 2,
  });

  @override int get pageCount => source.pageCount;
  @override String filename(int index) => source.filename(index);

  bool get capacityReached => _capacityReached;

  Future<Directory> _getDir() =>
      _directory ??= (parent ?? Directory.systemTemp)
          .createTemp('hyp_reader_cache_');

  @override
  Future<Uint8List> loadPage(int index) {
    if (index < 0 || index >= pageCount) {
      return Future.error(RangeError.index(index, List.filled(pageCount, 0)));
    }
    if (_disposed) {
      return Future.error(StateError('Reader cache already closed'));
    }
    return _loading.putIfAbsent(index, () async {
      try {
        final dir = await _getDir();
        final file = File('${dir.path}${Platform.pathSeparator}page_$index.bin');
        if (await file.exists()) {
          final size = await file.length();
          if (size > 0 && size <= GalleryArchive.maxSingleImageBytes) {
            return await file.readAsBytes();
          }
          await file.delete();
        }
        final bytes = await source.loadPage(index);
        if (!_disposed && !_capacityReached && bytes.isNotEmpty &&
            _writtenBytes + bytes.length <= maxBytes) {
          try {
            await file.writeAsBytes(bytes, flush: true);
            _writtenBytes += bytes.length;
          } on FileSystemException {
            // Low storage should degrade to ordinary on-demand loading.
            _capacityReached = true;
          }
        } else if (_writtenBytes + bytes.length > maxBytes) {
          _capacityReached = true;
        }
        return bytes;
      } finally {
        _loading.remove(index);
      }
    });
  }

  void warmAround(int page, int radius) {
    if (_disposed) return;
    final first = (page - radius).clamp(0, pageCount);
    final last = (page + radius + 1).clamp(0, pageCount);
    _pending.addAll(List.generate(last - first, (i) => first + i));
    _ensurePump();
  }

  void warmAll({int startingAt = 0}) {
    if (_disposed) return;
    final start = startingAt.clamp(0, pageCount);
    for (var i = start; i < pageCount; i++) _pending.add(i);
    for (var i = 0; i < start; i++) _pending.add(i);
    _ensurePump();
  }

  void _ensurePump() {
    if (_pump != null || _disposed) return;
    _pump = Future.wait(List.generate(concurrency, (_) async {
      while (_pending.isNotEmpty && !_disposed && !_capacityReached) {
        final index = _pending.first;
        _pending.remove(index);
        try {
          await loadPage(index);
        } catch (_) {
          // The visible page retains a retry affordance.
        }
      }
    })).then<void>((_) {
      _pump = null;
      if (_pending.isNotEmpty && !_disposed && !_capacityReached) _ensurePump();
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _pending.clear();
    try {
      await _pump;
    } catch (_) {}
    // User-initiated page loads may outlive warm-up workers.
    await Future.wait(_loading.values.toList().map(
      (future) => future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    ));
    final dir = await _directory;
    if (dir != null && await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
