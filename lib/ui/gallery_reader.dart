import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/gallery.dart';
import '../core/work.dart';

/// Page reader for local CBZ/ZIP archives and remote galleries.
/// PageView supports swiping; InteractiveViewer supports pan/zoom.
class GalleryReader extends StatefulWidget {
  final WorkEntry work;
  final GalleryPageSource archive;
  final ValueChanged<int> onPageChanged;
  /// Optional browser fallback for online galleries when image requests fail.
  final Future<void> Function(int page)? onOpenInBrowser;

  const GalleryReader({
    super.key,
    required this.work,
    required this.archive,
    required this.onPageChanged,
    this.onOpenInBrowser,
  });

  @override
  State<GalleryReader> createState() => _GalleryReaderState();
}

class _GalleryReaderState extends State<GalleryReader> {
  late PageController _controller;
  late int _currentPage;
  bool _vertical = false;
  bool _controlsVisible = true;
  final Map<int, Future<Uint8List>> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _currentPage = widget.work.currentPage.clamp(1, widget.archive.pageCount).toInt();
    _controller = PageController(initialPage: _currentPage - 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleDirection() {
    final previous = _controller;
    setState(() {
      _controller = PageController(initialPage: _currentPage - 1);
      _vertical = !_vertical;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  Future<Uint8List> _bytesAt(int index) {
    _imageCache.removeWhere((key, _) => (key - index).abs() > 3);
    return _imageCache.putIfAbsent(index, () async => widget.archive.loadPage(index));
  }

  void _retryPage(int index) {
    setState(() { _imageCache.remove(index); });
  }

  Widget _failedImage(int index, Object error) {
    final raw = error.toString();
    final reason = raw.length <= 450 ? raw : raw.substring(0, 450) + '…';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 14),
              Text('${index + 1}페이지 이미지를 불러오지 못했어.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const Key('reader-retry-page'),
                    onPressed: () => _retryPage(index),
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 시도'),
                  ),
                  if (widget.onOpenInBrowser != null)
                    FilledButton.icon(
                      key: const Key('reader-web-fallback'),
                      onPressed: () { widget.onOpenInBrowser?.call(index + 1); },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('웹 리더로 열기'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageAt(int index) {
    return FutureBuilder<Uint8List>(
      future: _bytesAt(index),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _failedImage(index, snapshot.error!);
        }
        if (!snapshot.hasData) {
          return const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('이미지를 불러오는 중…',
                  style: TextStyle(color: Colors.white70)),
            ]),
          );
        }
        return Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) =>
                  _failedImage(index, error),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.archive.pageCount;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _controlsVisible
          ? AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(widget.work.title.isEmpty
                  ? widget.work.workId
                  : widget.work.title, maxLines: 1),
              actions: [
                if (widget.onOpenInBrowser != null)
                  IconButton(
                    tooltip: '현재 페이지를 웹 리더로 열기',
                    onPressed: () { widget.onOpenInBrowser?.call(_currentPage); },
                    icon: const Icon(Icons.open_in_browser),
                  ),
                IconButton(
                  tooltip: _vertical ? '가로 넘기기' : '세로 넘기기',
                  icon: Icon(_vertical ? Icons.swap_horiz : Icons.swap_vert),
                  onPressed: _toggleDirection,
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onDoubleTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: PageView.builder(
          key: ValueKey(_vertical),
          controller: _controller,
          scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
          itemCount: total,
          onPageChanged: (index) {
            setState(() => _currentPage = index + 1);
            widget.onPageChanged(index + 1);
          },
          itemBuilder: (context, index) => _imageAt(index),
        ),
      ),
      bottomNavigationBar: _controlsVisible
          ? SafeArea(
              top: false,
              // A Row containing Slider can otherwise expand to the entire
              // Scaffold height, covering the pages and intercepting taps.
              child: SizedBox(
                height: 64,
                child: ColoredBox(
                  color: Colors.black,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text('$_currentPage / $total',
                            style: const TextStyle(color: Colors.white)),
                        Expanded(
                          child: Slider(
                            value: _currentPage.toDouble(),
                            min: 1,
                            max: total.toDouble(),
                            divisions: total > 1 ? total - 1 : null,
                            onChanged: (value) {
                              final page = value.round().clamp(1, total).toInt();
                              _controller.jumpToPage(page - 1);
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: '다음 페이지',
                          color: Colors.white,
                          onPressed: _currentPage < total
                              ? () => _controller.nextPage(
                                  duration: const Duration(milliseconds: 170),
                                  curve: Curves.easeOut)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
