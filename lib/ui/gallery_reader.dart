import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../core/i18n.dart';
import 'package:flutter/services.dart';

import '../core/gallery.dart';
import '../core/android_controls.dart';
import '../core/reader_settings.dart';
import '../core/work.dart';

/// Common offline and online reader with adjacent prefetch and shortcuts.
class GalleryReader extends StatefulWidget {
  final WorkEntry work;
  final GalleryPageSource archive;
  final ValueChanged<int> onPageChanged;
  final ReaderSettings settings;
  final Future<void> Function(int page)? onOpenInBrowser;
  final Future<void> Function()? onDownloadOffline;
  final void Function(int page, Uint8List bytes)? onPageLoaded;
  final Future<void> Function(int page, Uint8List bytes)? onChooseCover;
  final ValueChanged<bool>? onVerticalScrollingChanged;

  const GalleryReader({
    super.key,
    required this.work,
    required this.archive,
    required this.onPageChanged,
    this.settings = const ReaderSettings(),
    this.onOpenInBrowser,
    this.onDownloadOffline,
    this.onPageLoaded,
    this.onChooseCover,
    this.onVerticalScrollingChanged,
  });

  @override
  State<GalleryReader> createState() => _GalleryReaderState();
}

class _GalleryReaderState extends State<GalleryReader> with WidgetsBindingObserver {
  late PageController _controller;
  late int _currentUnit;
  bool _vertical = false;
  bool _controlsVisible = true;
  int _reloadGeneration = 0;
  final Map<int, Future<Uint8List>> _imageCache = {};

  int get _step => widget.settings.twoPageSpread ? 2 : 1;
  int get _units => (widget.archive.pageCount + _step - 1) ~/ _step;
  int get _currentPage => _currentUnit * _step + 1;

  @override
  void initState() {
    super.initState();
    _vertical = widget.settings.verticalScrolling;
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
        oldWidget.settings.forceLandscapeForSpreads != widget.settings.forceLandscapeForSpreads ||
        oldWidget.settings.twoPageSpread != widget.settings.twoPageSpread) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncAndroidControls();
      });
    }
    if (oldWidget.settings.twoPageSpread != widget.settings.twoPageSpread) {
      final page = _currentUnit *
          (oldWidget.settings.twoPageSpread ? 2 : 1) + 1;
      final previous = _controller;
      _currentUnit = (page - 1) ~/ _step;
      _controller = PageController(initialPage: _currentUnit);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous.dispose();
        if (mounted) _prefetchAround(_currentUnit);
      });
    } else if (oldWidget.settings.verticalScrolling !=
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
    unawaited(AndroidReaderControls.deactivate());
    _controller.dispose();
    super.dispose();
  }

  void _syncAndroidControls() {
    unawaited(AndroidReaderControls.activate(
      volumeNavigation: widget.settings.volumeKeyNavigation,
      forceLandscape: widget.settings.twoPageSpread &&
          widget.settings.forceLandscapeForSpreads,
      onTurn: (next) { if (mounted) _turn(next ? 1 : -1); },
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncAndroidControls();
  }

  Future<Uint8List> _bytesAt(int index) =>
      _imageCache.putIfAbsent(index, () {
        final result = widget.archive.loadPage(index).then((bytes) {
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
    final begin = unit * _step;
    final end = (begin + _step).clamp(0, widget.archive.pageCount).toInt();
    final radius = widget.settings.preloadPages;
    final first = (begin - radius).clamp(0, widget.archive.pageCount).toInt();
    final last = (end + radius).clamp(0, widget.archive.pageCount).toInt();
    for (var index = first; index < last; index++) {
      _bytesAt(index);
    }
    // Do not cache the full gallery in memory.
    _imageCache.removeWhere((index, _) => index < first || index >= last);
  }

  void _retryPage(int index) {
    setState(() {
      _imageCache.remove(index);
      _reloadGeneration++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchAround(_currentUnit);
    });
  }

  void _turn(int delta) {
    final target = (_currentUnit + delta).clamp(0, _units - 1).toInt();
    if (target == _currentUnit || !_controller.hasClients) return;
    _controller.animateToPage(target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut);
  }

  void _jumpTo(int unit) {
    if (!_controller.hasClients) return;
    _controller.jumpToPage(unit.clamp(0, _units - 1).toInt());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _turn(widget.settings.reverse ? 1 : -1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _turn(widget.settings.reverse ? -1 : 1);
    } else if (key == LogicalKeyboardKey.pageDown ||
               key == LogicalKeyboardKey.space) {
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
    final reason = raw.length <= 430 ? raw : raw.substring(0, 430) + '…';
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
            HypText((index + 1).toString() + '페이지를 불러오지 못했어.',
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

  Widget _pageAt(int index) => FutureBuilder<Uint8List>(
    future: _bytesAt(index),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _failedImage(index, snapshot.error!);
      if (!snapshot.hasData) {
        return const Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            HypText('이미지를 불러오는 중…',
                style: TextStyle(color: Colors.white70)),
          ],
        ));
      }
      return Center(child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Image.memory(
          snapshot.data!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
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
      tooltip: '이전 페이지 (PageUp)',
      color: Colors.white,
      onPressed: _currentUnit > 0 ? () => _turn(-1) : null,
      icon: Icon(widget.settings.reverse
          ? Icons.chevron_right : Icons.chevron_left),
    );
    Widget nextButton() => IconButton(
      key: const Key('reader-next'),
      tooltip: '다음 페이지 (PageDown / Space)',
      color: Colors.white,
      onPressed: _currentUnit < _units - 1 ? () => _turn(1) : null,
      icon: Icon(widget.settings.reverse
          ? Icons.chevron_left : Icons.chevron_right),
    );
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: HypText(widget.work.title.isEmpty
              ? widget.work.workId : widget.work.title,
              overflow: TextOverflow.ellipsis),
          actions: [
            if (widget.settings.showDownloadAction &&
                widget.onDownloadOffline != null)
              IconButton(
                key: const Key('reader-download-offline'),
                tooltip: '온라인 이미지를 CBZ로 저장',
                onPressed: () { widget.onDownloadOffline?.call(); },
                icon: const Icon(Icons.download_for_offline_outlined),
              ),
            if (widget.settings.showCoverAction &&
                widget.onChooseCover != null)
              IconButton(
                tooltip: '현재 페이지를 서재 표지로 지정',
                onPressed: _useAsCover,
                icon: const Icon(Icons.photo_library_outlined),
              ),
            if (widget.settings.showPageControlsAction) IconButton(
              tooltip: _controlsVisible ? '페이지 도구 숨기기' : '페이지 도구 표시',
              onPressed: () => setState(
                () => _controlsVisible = !_controlsVisible),
              icon: Icon(_controlsVisible
                  ? Icons.visibility_off : Icons.visibility),
            ),
            if (widget.onOpenInBrowser != null)
              IconButton(
                tooltip: '현재 페이지를 웹 리더로 열기',
                onPressed: () { widget.onOpenInBrowser?.call(_currentPage); },
                icon: const Icon(Icons.open_in_browser),
              ),
            if (widget.settings.showOrientationAction &&
                !widget.settings.twoPageSpread)
              IconButton(
                tooltip: _vertical ? '가로 넘기기' : '세로 넘기기',
                icon: Icon(_vertical ? Icons.swap_horiz : Icons.swap_vert),
                onPressed: _toggleVertical,
              ),
          ],
        ),
        body: PageView.builder(
          key: ValueKey(_vertical.toString() + '-' +
              widget.settings.reverse.toString() + '-' +
              _reloadGeneration.toString() + '-' +
              widget.settings.twoPageSpread.toString()),
          controller: _controller,
          reverse: widget.settings.reverse,
          scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
          itemCount: _units,
          onPageChanged: (unit) {
            setState(() => _currentUnit = unit);
            widget.onPageChanged(_currentPage);
            _prefetchAround(unit);
          },
          itemBuilder: (context, unit) => _spreadAt(unit),
        ),
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
                      widget.settings.reverse ? nextButton() : previousButton(),
                      HypText('$_currentPage / $total',
                          style: const TextStyle(color: Colors.white)),
                      Expanded(child: Directionality(
                        textDirection: widget.settings.reverse
                            ? TextDirection.rtl : TextDirection.ltr,
                        child: Slider(
                          value: (_currentUnit + 1).toDouble(),
                          min: 1,
                          max: _units.toDouble(),
                          divisions: _units > 1 ? _units - 1 : null,
                          onChanged: _units > 1
                              ? (value) => _jumpTo(value.round() - 1) : null,
                        ),
                      )),
                      widget.settings.reverse ? previousButton() : nextButton(),
                    ]),
                  ),
                ),
              ))
            : null,
      ),
    );
  }
}
