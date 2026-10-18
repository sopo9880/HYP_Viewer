import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../core/i18n.dart';
import 'hyp_animated_title.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/gallery.dart';
import '../core/android_controls.dart';
import '../core/reader_settings.dart';
import '../core/reader_disk_cache.dart';
import '../l10n/app_localizations.dart';
import '../core/reader_tap_zones.dart';
import '../core/work.dart';

/// Common offline and online reader with adjacent prefetch and shortcuts.
class GalleryReader extends StatefulWidget {
  final WorkEntry work;
  final GalleryPageSource archive;
  final ValueChanged<int> onPageChanged;
  final ReaderSettings settings;
  // Test seam: production always uses the on-disk reader cache.
  final bool diskCacheEnabled;
  final Directory? persistentCacheDirectory;
  final Future<void> Function(int page)? onOpenInBrowser;
  final Future<void> Function()? onDownloadOffline;
  final void Function(int page, Uint8List bytes)? onPageLoaded;
  final Future<void> Function(int page, Uint8List bytes)? onChooseCover;
  final ValueChanged<bool>? onVerticalScrollingChanged;
  final ValueChanged<bool>? onTwoPageSpreadChanged;
  final ValueChanged<int>? onFinishedReading;
  final bool previewMode;
  final Future<bool> Function()? onSavePreview;
  final Future<void> Function()? onBlockPreview;

  const GalleryReader({
    super.key,
    required this.work,
    required this.archive,
    required this.onPageChanged,
    this.settings = const ReaderSettings(),
    this.diskCacheEnabled = true,
    this.persistentCacheDirectory,
    this.onOpenInBrowser,
    this.onDownloadOffline,
    this.onPageLoaded,
    this.onChooseCover,
    this.onVerticalScrollingChanged,
    this.onTwoPageSpreadChanged,
    this.onFinishedReading,
    this.previewMode = false,
    this.onSavePreview,
    this.onBlockPreview,
  });

  @override
  State<GalleryReader> createState() => _GalleryReaderState();
}

class _GalleryReaderState extends State<GalleryReader> with WidgetsBindingObserver {
  late PageController _controller;
  late int _currentUnit;
  bool _vertical = false;
  bool get _verticalReading => _vertical || widget.settings.webtoonMode;
  bool _controlsVisible = true;
  bool _previewSaving = false;
  bool _previewSaved = false;
  bool _twoPageSpread = false;
  bool _completionReported = false;
  bool _completionPromptOpen = false;
  bool _lastPageRendered = false;
  final TransformationController _webtoonTransform = TransformationController();
  bool _webtoonZoomed = false;
  bool _controlHeld = false;
  final Map<int, TransformationController> _pageTransforms = {};
  TransformationController _zoomController(int page) =>
      _pageTransforms.putIfAbsent(page, TransformationController.new);
  bool get _zoomed {
    final begin = _currentUnit * _step;
    for (var index = begin; index < begin + _step; index++) {
      if ((_pageTransforms[index]?.value.getMaxScaleOnAxis() ?? 1) > 1.02) {
        return true;
      }
    }
    return false;
  }
  void _resetZoom() {
    for (final controller in _pageTransforms.values) {
      controller.value = Matrix4.identity();
    }
  }
  void _reportLastFrame(int index) {
    if (index != widget.archive.pageCount - 1) return;
    _lastPageRendered = true;
    _completeWhenVisible();
  }

  void _completeWhenVisible() {
    if (widget.previewMode || widget.settings.confirmCompleteOnNext) return;
    if (_completionReported || !_lastPageRendered ||
        _currentUnit != _units - 1) return;
    _completionReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_currentUnit == _units - 1) {
        widget.onFinishedReading?.call(widget.archive.pageCount);
      } else {
        _completionReported = false;
      }
    });
  }
  /// Confirmation only happens after an explicit NEXT at the last page.
  /// Arrival at the final image, preloading or a held volume key never
  /// silently marks a work as completed.
  Future<void> _askToFinish() async {
    if (widget.previewMode) return;
    if (_completionPromptOpen || _completionReported || !_lastPageRendered ||
        !mounted) return;
    _completionPromptOpen = true;
    final labels = AppLocalizations.of(context)!;
    String? answer;
    try {
      answer = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('reader-finish-dialog'),
          scrollable: true,
          title: Text(labels.readerFinishTitle),
          // Keep actions vertically ordered even on wide desktop windows.
          // Restart is intentionally first, above "Keep Reading".
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(labels.readerFinishBody),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('reader-restart-from-first'),
                onPressed: () => Navigator.of(dialogContext).pop('restart'),
                icon: const Icon(Icons.first_page),
                label: Text(labels.readerBackToStart),
              ),
              TextButton(
                key: const Key('reader-keep-reading'),
                onPressed: () => Navigator.of(dialogContext).pop('stay'),
                child: Text(labels.readerContinueReading),
              ),
              TextButton(
                key: const Key('reader-exit-incomplete'),
                onPressed: () => Navigator.of(dialogContext).pop('exit'),
                child: Text(labels.readerExitWithoutFinishing),
              ),
              FilledButton(
                key: const Key('reader-finish-and-exit'),
                onPressed: () => Navigator.of(dialogContext).pop('complete'),
                child: Text(labels.readerFinishAndExit),
              ),
            ],
          ),
        ),
      );
    } finally {
      _completionPromptOpen = false;
    }
    if (!mounted) return;
    if (answer == 'restart') {
      // Rewind without marking complete or dismissing the reader. _jumpTo
      // updates the resume position and handles spreads and webtoon scroll.
      _jumpTo(0);
    } else if (answer == 'complete') {
      _completionReported = true;
      widget.onFinishedReading?.call(widget.archive.pageCount);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } else if (answer == 'exit') {
      // Preserve previous completion flags and reading position on exit.
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  void _pauseHeldVolumeIfAtBoundary() {
    if (_currentUnit == _units - 1) {
      unawaited(AndroidReaderControls.pauseRepeats());
    }
  }

  void _toggleChrome() => setState(() => _controlsVisible = !_controlsVisible);
  int _reloadGeneration = 0;
  final Map<int, Future<Uint8List>> _imageCache = {};
  GalleryDiskCache? _diskCache;
  int? _pendingWebtoonJump;
  double? _scrubTarget;
  Timer? _jumpReleaseTimer;
  final ItemScrollController _webtoonController = ItemScrollController();
  final ItemPositionsListener _webtoonPositions = ItemPositionsListener.create();

  int get _step => widget.settings.webtoonMode ? 1 :
      _twoPageSpread ? 2 : 1;
  int get _units => (widget.archive.pageCount + _step - 1) ~/ _step;
  int get _currentPage => _currentUnit * _step + 1;

  @override
  void initState() {
    super.initState();
    _twoPageSpread = widget.settings.twoPageSpread;
    _vertical = _twoPageSpread ? false : widget.settings.verticalScrolling;
    _controlsVisible = widget.previewMode || !widget.settings.hideReaderUiOnOpen;
    // ALL visible and background requests share this same bounded queue.
    // Data saver uses one request at a time, regardless of preload setting.
    _diskCache = GalleryDiskCache(widget.archive,
        concurrency: widget.settings.dataSaverMode ? 1 : 2,
        cacheToDisk: widget.diskCacheEnabled,
        persistentDirectory: widget.persistentCacheDirectory);
    _webtoonPositions.itemPositions.addListener(_onWebtoonPosition);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAndroidControls();
    });
    final initial = widget.work.currentPage
        .clamp(1, widget.archive.pageCount).toInt();
    _currentUnit = (initial - 1) ~/ _step;
    _controller = PageController(initialPage: _currentUnit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchAround(_currentUnit);
    });
  }

  @override
  void didUpdateWidget(covariant GalleryReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.volumeKeyNavigation != widget.settings.volumeKeyNavigation ||
        oldWidget.settings.volumeHoldIntervalMs != widget.settings.volumeHoldIntervalMs ||
        oldWidget.settings.forceLandscapeForSpreads != widget.settings.forceLandscapeForSpreads ||
        oldWidget.settings.twoPageSpread != widget.settings.twoPageSpread) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncAndroidControls();
      });
    }
    if (oldWidget.archive != widget.archive) {
      _lastPageRendered = false;
      _completionReported = false;
    }
    if (oldWidget.archive != widget.archive ||
        oldWidget.settings.dataSaverMode != widget.settings.dataSaverMode ||
        oldWidget.diskCacheEnabled != widget.diskCacheEnabled ||
        oldWidget.persistentCacheDirectory?.path !=
            widget.persistentCacheDirectory?.path) {
      final oldDisk = _diskCache;
      _diskCache = GalleryDiskCache(widget.archive,
          concurrency: widget.settings.dataSaverMode ? 1 : 2,
        cacheToDisk: widget.diskCacheEnabled,
        persistentDirectory: widget.persistentCacheDirectory);
      _imageCache.clear();
      if (oldDisk != null) unawaited(oldDisk.dispose());
    }
    if (oldWidget.settings.webtoonMode != widget.settings.webtoonMode ||
        (oldWidget.settings.twoPageSpread != widget.settings.twoPageSpread &&
            _twoPageSpread != widget.settings.twoPageSpread)) {
      final page = _currentPage;
      final previous = _controller;
      _twoPageSpread = widget.settings.twoPageSpread;
      _vertical = _twoPageSpread ? false : widget.settings.verticalScrolling;
      _currentUnit = (page - 1) ~/ _step;
      _controller = PageController(initialPage: _currentUnit);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous.dispose();
        if (mounted) _prefetchAround(_currentUnit);
      });
    } else if (!_twoPageSpread && oldWidget.settings.verticalScrolling !=
        widget.settings.verticalScrolling) {
      final previous = _controller;
      _vertical = widget.settings.verticalScrolling;
      _controller = PageController(initialPage: _currentUnit);
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    } else if (oldWidget.settings.preloadPages !=
        widget.settings.preloadPages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prefetchAround(_currentUnit);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webtoonPositions.itemPositions.removeListener(_onWebtoonPosition);
    _jumpReleaseTimer?.cancel();
    if (_diskCache != null) unawaited(_diskCache!.dispose());
    unawaited(AndroidReaderControls.deactivate());
    _controller.dispose();
    for (final controller in _pageTransforms.values) {
      controller.dispose();
    }
    _webtoonTransform.dispose();
    super.dispose();
  }

  void _syncAndroidControls() {
    unawaited(AndroidReaderControls.activate(
      volumeNavigation: widget.settings.volumeKeyNavigation,
      repeatIntervalMs: widget.settings.volumeHoldIntervalMs,
      forceLandscape: !widget.settings.webtoonMode &&
          _twoPageSpread &&
          widget.settings.forceLandscapeForSpreads,
      onTurn: (next, repeating) {
        if (mounted) _turn(next ? 1 : -1, fromVolumeRepeat: repeating);
      },
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncAndroidControls();
  }

  Future<Uint8List> _bytesAt(int index) =>
      _imageCache.putIfAbsent(index, () {
        final result = (_diskCache ?? widget.archive).loadPage(index).then((bytes) {
          widget.onPageLoaded?.call(index + 1, bytes);
          return bytes;
        });
        // Prevent unhandled errors from speculative prefetch; the visible
        // FutureBuilder will still display the original failed Future.
        unawaited(result.then<void>((_) {},
            onError: (Object _, StackTrace __) {}));
        return result;
      });

  void _prefetchAround(int unit) {
    if (!mounted || widget.archive.pageCount == 0) return;
    final begin = (unit * _step).clamp(0, widget.archive.pageCount - 1)
        .toInt();
    final configured = widget.settings.preloadPages;
    final saving = widget.settings.dataSaverMode;
    // A user-requested jump MUST have higher priority than full-cache work.
    _bytesAt(begin);
    if (_step == 2 && begin + 1 < widget.archive.pageCount) {
      _bytesAt(begin + 1);
    }
    if (!saving && configured != 0) {
      // Prioritize the next few pages in memory and pre-decode their images.
      // Waiting for disk/network alone is insufficient to avoid a loading
      // indicator on the next page: codecs also need to warm up.
      final visibleAndNext = <int>[
        begin,
        if (_step == 2 && begin + 1 < widget.archive.pageCount) begin + 1,
        for (var i = begin + _step;
             i < begin + _step + 3 && i < widget.archive.pageCount;
             i++) i,
      ];
      for (final index in visibleAndNext) {
        unawaited(_bytesAt(index).then<void>((bytes) async {
          if (!mounted) return;
          try {
            await precacheImage(MemoryImage(bytes), context,
                onError: (exception, stack) {});
          } catch (_) {
            // A corrupt/deleted image still surfaces normally in the reader.
          }
        }, onError: (Object error, StackTrace stack) {}));
      }
    }
    if (saving) {
      // Data saver overrides -1 without changing the user's saved setting.
      _diskCache?.warmAround(begin + _step, 0);
    } else if (configured == -1) {
      _diskCache?.warmAll(startingAt: begin);
    } else if (configured > 0) {
      _diskCache?.warmAround(begin, configured);
    }
    final memoryRadius = saving ? 1 :
        configured == -1 ? 4 : configured == 0 ? 0 : configured.clamp(3, 6).toInt();
    final first = (begin - memoryRadius).clamp(0, widget.archive.pageCount)
        .toInt();
    final last = (begin + _step + memoryRadius)
        .clamp(0, widget.archive.pageCount).toInt();
    // Avoid eagerly requesting all of the surrounding pages from the
    // widget tree. Only a few prioritized visible pages enter _imageCache.
    _imageCache.removeWhere((index, _) => index < first || index >= last);
  }

  Future<void> _retryPage(int index) async {
    // A corrupted image may have been successfully downloaded and cached.
    // Delete ONLY this page before fetching it again, not the whole book.
    await _diskCache?.invalidate(index);
    if (!mounted) return;
    setState(() {
      _imageCache.remove(index);
      _reloadGeneration++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchAround(_currentUnit);
    });
  }

  void _turn(int delta, {bool fromVolumeRepeat = false}) {
    final target = (_currentUnit + delta).clamp(0, _units - 1).toInt();
    if (target == _currentUnit) {
      if (fromVolumeRepeat) {
        unawaited(AndroidReaderControls.pauseRepeats());
      } else if (delta > 0 && widget.settings.confirmCompleteOnNext &&
          _currentUnit == _units - 1) {
        unawaited(_askToFinish());
      }
      return;
    }
    _resetZoom();
    if (widget.settings.webtoonMode) {
      _jumpTo(target);
      return;
    }
    if (!_controller.hasClients) return;
    _controller.animateToPage(target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut);
  }

  void _jumpTo(int unit) {
    final target = unit.clamp(0, _units - 1).toInt();
    // A jump is navigation, not an image-loading outcome. Persist the
    // destination before asynchronous image layout or decoding begins.
    _resetZoom();
    setState(() => _currentUnit = target);
    _pauseHeldVolumeIfAtBoundary();
    widget.onPageChanged(_currentPage);
    _completeWhenVisible();
    _prefetchAround(target);
    if (widget.settings.webtoonMode) {
      _pendingWebtoonJump = target;
      _jumpReleaseTimer?.cancel();
      _jumpReleaseTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _pendingWebtoonJump = null;
      });
      if (_webtoonController.isAttached) {
        _webtoonController.jumpTo(index: target);
      }
      return;
    }
    if (_controller.hasClients) _controller.jumpToPage(target);
  }

  void _onWebtoonPosition() {
    if (!mounted || !widget.settings.webtoonMode) return;
    final visible = _webtoonPositions.itemPositions.value
        .where((position) => position.itemTrailingEdge > 0 &&
            position.itemLeadingEdge < 1).toList();
    if (visible.isEmpty) return;
    // Large jumps may briefly report stale/placeholder item positions.
    // Never replace the requested target with a fabricated first page.
    if (_pendingWebtoonJump != null) {
      if (visible.any((p) => p.index == _pendingWebtoonJump)) {
        _pendingWebtoonJump = null;
        _jumpReleaseTimer?.cancel();
      }
      return;
    }
    visible.sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    final index = visible.first.index;
    if (index == _currentUnit) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.settings.webtoonMode ||
          index == _currentUnit) return;
      setState(() => _currentUnit = index);
      _pauseHeldVolumeIfAtBoundary();
      _completeWhenVisible();
      widget.onPageChanged(index + 1);
      _prefetchAround(index);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight) {
      if (event is KeyDownEvent && !_controlHeld) {
        setState(() => _controlHeld = true);
      } else if (event is KeyUpEvent && _controlHeld) {
        setState(() => _controlHeld = false);
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent && _currentUnit == _units - 1 &&
        widget.settings.confirmCompleteOnNext) {
      // Held keyboard keys cannot repeatedly reopen a finish dialog.
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _toggleChrome();
      return KeyEventResult.handled;
    }
    if (_verticalReading && key == LogicalKeyboardKey.arrowUp) {
      _turn(-1);
    } else if (_verticalReading && key == LogicalKeyboardKey.arrowDown) {
      _turn(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _turn(!_verticalReading && widget.settings.reverse ? 1 : -1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _turn(!_verticalReading && widget.settings.reverse ? -1 : 1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _turn(1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _turn(-1);
    } else if (key == LogicalKeyboardKey.home) {
      _jumpTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      _jumpTo(_units - 1);
    } else if (key == LogicalKeyboardKey.escape) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _useAsCover() async {
    final choose = widget.onChooseCover;
    if (choose == null) return;
    final page = _currentPage;
    try {
      final bytes = await _bytesAt(page - 1);
      await choose(page, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: HypText(page.toString() + '페이지를 서재 표지로 지정했어.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: HypText('표지 저장 실패: ' + error.toString())),
        );
      }
    }
  }

  void _toggleTwoPageSpread() {
    if (widget.settings.webtoonMode) return;
    final page = _currentPage;
    final previous = _controller;
    setState(() {
      _twoPageSpread = !_twoPageSpread;
      _vertical = _twoPageSpread ? false : widget.settings.verticalScrolling;
      _currentUnit = (page - 1) ~/ _step;
      _controller = PageController(initialPage: _currentUnit);
      _scrubTarget = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previous.dispose();
      if (mounted) {
        _syncAndroidControls();
        _prefetchAround(_currentUnit);
      }
    });
    widget.onTwoPageSpreadChanged?.call(_twoPageSpread);
  }

  void _toggleVertical() {
    final previous = _controller;
    setState(() {
      _vertical = !_vertical;
      _controller = PageController(initialPage: _currentUnit);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    widget.onVerticalScrollingChanged?.call(_vertical);
  }

  Widget _failedImage(int index, Object error) {
    final raw = error.toString();
    final l = AppLocalizations.of(context)!;
    final reason = RegExp(r'\b(429|502|503|504)\b').hasMatch(raw)
        ? l.readerFailureHttp
        : raw.length <= 280 ? raw : raw.substring(0, 280) + '…';
    return Center(child: Padding(
      padding: const EdgeInsets.all(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                color: Colors.white70, size: 42),
            const SizedBox(height: 10),
            Text(l.readerFailedPage(index + 1),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(reason,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center,
                spacing: 8, runSpacing: 7, children: [
              OutlinedButton.icon(
                key: const Key('reader-retry-page'),
                onPressed: () => _retryPage(index),
                icon: const Icon(Icons.refresh),
                label: const HypText('다시 시도'),
              ),
              if (widget.settings.showWebReaderAction &&
                widget.onOpenInBrowser != null)
                FilledButton.icon(
                  key: const Key('reader-web-fallback'),
                  onPressed: () { widget.onOpenInBrowser?.call(index + 1); },
                  icon: const Icon(Icons.open_in_new),
                  label: const HypText('웹 리더로 열기'),
                ),
            ]),
          ],
        )),
      ),
    ));
  }

  Widget _pageAt(int index, {bool webtoon = false}) =>
      FutureBuilder<Uint8List>(
    future: _bytesAt(index),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return webtoon
            ? AspectRatio(aspectRatio: 0.72,
                child: _failedImage(index, snapshot.error!))
            : _failedImage(index, snapshot.error!);
      }
      if (!snapshot.hasData) {
        final loading = const Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            HypText('이미지를 불러오는 중…',
                style: TextStyle(color: Colors.white70)),
          ],
        ));
        // Give unloaded webtoon pages a stable nonzero measured height.
        // Zero-height placeholders previously materialized whole galleries.
        return webtoon ? AspectRatio(aspectRatio: 0.72,
            child: loading) : loading;
      }
      if (webtoon) {
        return Image.memory(
          snapshot.data!,
          key: Key('webtoon-image-$index'),
          width: double.infinity,
          fit: BoxFit.fitWidth,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, synchronous) {
            if (frame != null || synchronous) _reportLastFrame(index);
            return child;
          },
          errorBuilder: (context, error, stack) => _failedImage(index, error),
        );
      }
      return Center(child: InteractiveViewer(
        transformationController: _zoomController(index),
        minScale: 1,
        maxScale: 5,
        scaleFactor: 200,
        onInteractionEnd: (_) { if (mounted) setState(() {}); },
        child: Image.memory(
          snapshot.data!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, synchronous) {
            if (frame != null || synchronous) _reportLastFrame(index);
            return child;
          },
          errorBuilder: (context, error, stack) =>
              _failedImage(index, error),
        ),
      ));
    },
  );

  Widget _spreadAt(int unit) {
    final first = unit * _step;
    if (_step == 1) return _pageAt(first);
    final second = first + 1;
    final order = widget.settings.reverse
        ? <int>[second, first]
        : <int>[first, second];
    return Row(children: [
      for (final index in order) ...[
        Expanded(child: index < widget.archive.pageCount
            ? _pageAt(index)
            : const ColoredBox(color: Colors.black)),
        if (index == order.first)
          const VerticalDivider(width: 3, color: Color(0xFF343440)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.archive.pageCount;
    Widget previousButton() => IconButton(
      key: const Key('reader-previous'),
      tooltip: AppLocalizations.of(context)!.readerTooltipPrevious,
      color: Colors.white,
      onPressed: _currentUnit > 0 ? () => _turn(-1) : null,
      icon: Icon(_verticalReading
          ? Icons.keyboard_arrow_up : widget.settings.reverse
          ? Icons.chevron_right : Icons.chevron_left),
    );
    Widget nextButton() => IconButton(
      key: const Key('reader-next'),
      tooltip: AppLocalizations.of(context)!.readerTooltipNext,
      color: Colors.white,
      onPressed: _currentUnit < _units - 1 ||
          widget.settings.confirmCompleteOnNext ? () => _turn(1) : null,
      icon: Icon(_verticalReading
          ? Icons.keyboard_arrow_down : widget.settings.reverse
          ? Icons.chevron_left : Icons.chevron_right),
    );
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _controlsVisible ? AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: HypAnimatedTitle(
            key: const Key('reader-title'),
            title: (widget.previewMode ? '[미리보기] ' : '') +
                (widget.work.title.isEmpty
                    ? widget.work.workId : widget.work.title),
          ),
          actions: [
            if (widget.previewMode && widget.onSavePreview != null)
              IconButton(
                key: const Key('preview-save-to-library'),
                tooltip: HypI18n.t(context, _previewSaved
                    ? '서재에 저장됨' : '서재에 저장'),
                onPressed: _previewSaving || _previewSaved ? null : () async {
                  setState(() => _previewSaving = true);
                  try {
                    final saved = await widget.onSavePreview!();
                    if (mounted) setState(() => _previewSaved = saved);
                  } catch (error) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error.toString())));
                  } finally {
                    if (mounted) setState(() => _previewSaving = false);
                  }
                },
                icon: Icon(_previewSaved ? Icons.bookmark_added :
                    Icons.bookmark_add_outlined),
              ),
            if (widget.previewMode && widget.onBlockPreview != null)
              IconButton(
                key: const Key('preview-blacklist'),
                tooltip: HypI18n.t(context, '블랙리스트에 추가'),
                onPressed: _previewSaving ? null :
                    () => widget.onBlockPreview?.call(),
                icon: const Icon(Icons.block_outlined),
              ),
            if (widget.settings.showDownloadAction &&
                widget.onDownloadOffline != null)
              IconButton(
                key: const Key('reader-download-offline'),
                tooltip: AppLocalizations.of(context)!.readerTooltipSaveOffline,
                onPressed: () { widget.onDownloadOffline?.call(); },
                icon: const Icon(Icons.download_for_offline_outlined),
              ),
            if (widget.settings.showCoverAction &&
                widget.onChooseCover != null)
              IconButton(
                tooltip: AppLocalizations.of(context)!.readerTooltipSetCover,
                onPressed: _useAsCover,
                icon: const Icon(Icons.photo_library_outlined),
              ),
            if (widget.settings.showPageControlsAction &&
                !widget.settings.webtoonMode) IconButton(
              key: const Key('reader-toggle-spread'),
              tooltip: _twoPageSpread
                  ? AppLocalizations.of(context)!.readerTooltipSinglePage
                  : AppLocalizations.of(context)!.readerTooltipTwoPage,
              onPressed: _toggleTwoPageSpread,
              icon: Icon(_twoPageSpread
                  ? Icons.crop_portrait : Icons.menu_book_outlined),
            ),
            if (widget.onOpenInBrowser != null)
              IconButton(
                tooltip: AppLocalizations.of(context)!.readerTooltipOpenWeb,
                onPressed: () { widget.onOpenInBrowser?.call(_currentPage); },
                icon: const Icon(Icons.open_in_browser),
              ),
            if (widget.settings.showOrientationAction &&
                !_twoPageSpread &&
                !widget.settings.webtoonMode)
              IconButton(
                tooltip: _vertical ? AppLocalizations.of(context)!.readerTooltipHorizontal : AppLocalizations.of(context)!.readerTooltipVertical,
                icon: Icon(_vertical ? Icons.swap_horiz : Icons.swap_vert),
                onPressed: _toggleVertical,
              ),
          ],
        ) : null,
        body: widget.settings.webtoonMode
          ? GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (event) {
                final width = MediaQuery.sizeOf(context).width;
                if (_webtoonZoomed) return;
                if (!widget.settings.tapNavigation) {
                  _toggleChrome();
                  return;
                }
                final delta = readerTapDelta(
                  pointX: event.localPosition.dx,
                  pointY: event.localPosition.dy,
                  width: width,
                  height: MediaQuery.sizeOf(context).height,
                  vertical: true,
                  reverse: widget.settings.reverse,
                );
                if (delta == 0) {
                  _toggleChrome();
                } else {
                  _turn(delta);
                }
              },
              child: InteractiveViewer(
                transformationController: _webtoonTransform,
                minScale: 1, maxScale: 5, scaleFactor: 200,
                panEnabled: _webtoonZoomed,
                // Keep normal desktop wheel scrolling; Ctrl+wheel zooms.
                scaleEnabled: _controlHeld ||
                    Theme.of(context).platform == TargetPlatform.android ||
                    Theme.of(context).platform == TargetPlatform.iOS,
                onInteractionEnd: (_) {
                  final scaled = _webtoonTransform.value
                      .getMaxScaleOnAxis() > 1.02;
                  if (mounted) setState(() => _webtoonZoomed = scaled);
                },
                child: ScrollablePositionedList.builder(
              key: const Key('webtoon-continuous-reader'),
              itemCount: widget.archive.pageCount,
              initialScrollIndex: _currentUnit,
              itemScrollController: _webtoonController,
              itemPositionsListener: _webtoonPositions,
              scrollDirection: Axis.vertical,
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) =>
                  _pageAt(index, webtoon: true),
                ),
              ))
          : LayoutBuilder(builder: (context, constraints) => GestureDetector(
              key: const Key('reader-tap-zones'),
              behavior: HitTestBehavior.translucent,
              onTapUp: (event) {
                      if (_zoomed) return;
                      if (!widget.settings.tapNavigation) {
                        _toggleChrome();
                        return;
                      }
                      final delta = readerTapDelta(
                        pointX: event.localPosition.dx,
                        pointY: event.localPosition.dy,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        vertical: _vertical,
                        reverse: !_verticalReading && widget.settings.reverse,
                      );
                      if (delta == 0) _toggleChrome();
                      else _turn(delta);
                    },
              child: PageView.builder(
                key: ValueKey(_vertical.toString() + '-' +
                  widget.settings.reverse.toString() + '-' +
                  _reloadGeneration.toString() + '-' +
                  _twoPageSpread.toString()),
                controller: _controller,
                reverse: !_verticalReading && widget.settings.reverse,
                scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
                itemCount: _units,
                onPageChanged: (unit) {
                  _resetZoom();
                  setState(() => _currentUnit = unit);
                  _pauseHeldVolumeIfAtBoundary();
                  _completeWhenVisible();
                  widget.onPageChanged(_currentPage);
                  _prefetchAround(unit);
                },
                itemBuilder: (context, unit) => _spreadAt(unit),
              ),
            )),
        bottomNavigationBar: _controlsVisible
            ? SafeArea(top: false, child: SizedBox(
                height: 64,
                child: ColoredBox(
                  color: Colors.black,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Row(children: [
                      // In RTL books the NEXT action starts on the left.
                      !_verticalReading && widget.settings.reverse
                          ? nextButton() : previousButton(),
                      HypText('$_currentPage / $total',
                          style: const TextStyle(color: Colors.white)),
                      Expanded(child: Directionality(
                        textDirection: !_verticalReading && widget.settings.reverse
                            ? TextDirection.rtl : TextDirection.ltr,
                        child: Slider(
                          value: (_scrubTarget ?? (_currentUnit + 1).toDouble())
                              .clamp(1, _units.toDouble()).toDouble(),
                          min: 1,
                          max: _units.toDouble(),
                          divisions: _units > 1 ? _units - 1 : null,
                          onChanged: _units > 1 ? (value) =>
                              setState(() => _scrubTarget = value) : null,
                          // Dragging through 100+ positions must NOT
                          // enqueue 100 HTTP downloads or record stale pages.
                          onChangeEnd: _units > 1 ? (value) {
                            setState(() => _scrubTarget = null);
                            _jumpTo(value.round() - 1);
                          } : null,
                        ),
                      )),
                      !_verticalReading && widget.settings.reverse
                          ? previousButton() : nextButton(),
                    ]),
                  ),
                ),
              ))
            : null,
      ),
    );
  }
}
