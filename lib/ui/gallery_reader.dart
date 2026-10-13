import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/gallery.dart';
import '../core/work.dart';

/// A real page reader for a local CBZ/ZIP supplied by the user.
/// PageView supports swiping; InteractiveViewer supports pan/zoom.
class GalleryReader extends StatefulWidget {
  final WorkEntry work;
  final GalleryPageSource archive;
  final ValueChanged<int> onPageChanged;

  const GalleryReader({
    super.key,
    required this.work,
    required this.archive,
    required this.onPageChanged,
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
    final page = _currentPage - 1;
    _controller.dispose();
    _controller = PageController(initialPage: page);
    setState(() => _vertical = !_vertical);
  }

  Future<Uint8List> _bytesAt(int index) {
    _imageCache.removeWhere((key, _) => (key - index).abs() > 3);
    return _imageCache.putIfAbsent(index, () async => widget.archive.loadPage(index));
  }

  Widget _imageAt(int index) {
    return FutureBuilder<Uint8List>(
      future: _bytesAt(index),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('페이지를 읽을 수 없어: ' + snapshot.error.toString()));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
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
                  Center(child: Text('이미지를 표시하지 못했어: ' + error.toString())),
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
            )
          : null,
    );
  }
}
