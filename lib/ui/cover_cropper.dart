import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../core/i18n.dart';
import 'package:flutter/rendering.dart';

/// All editing happens in a fixed portrait preview. The exact cropped
/// viewport is rasterized into PNG so saved covers match the visible result.
Future<Uint8List?> showCoverCropper(BuildContext context, Uint8List bytes) =>
    showDialog<Uint8List>(
      context: context,
      builder: (_) => _CropCoverDialog(bytes: bytes),
    );

class _CropCoverDialog extends StatefulWidget {
  final Uint8List bytes;
  const _CropCoverDialog({required this.bytes});

  @override
  State<_CropCoverDialog> createState() => _CropCoverDialogState();
}

class _CropCoverDialogState extends State<_CropCoverDialog> {
  final _boundary = GlobalKey();
  final _transform = TransformationController();
  double _zoom = 1;
  bool _saving = false;
  String? _error;

  static const double width = 224;
  static const double height = 320;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _changeZoom(double value) {
    _zoom = value;
    // Keep the image centered when changing the zoom slider.
    _transform.value = Matrix4.identity()
      ..translate((1 - value) * width / 2, (1 - value) * height / 2)
      ..scale(value);
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _boundary.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw const FormatException('표지 편집 영역을 캡처하지 못했어.');
      }
      final image = await boundary.toImage(pixelRatio: 1.4);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const FormatException('표지를 PNG로 저장할 수 없어.');
        if (!mounted) return;
        Navigator.pop(context, data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const HypText('표지 자르기'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const HypText('사진을 드래그하거나 두 손가락으로 확대·축소해 '
            '사각형 안의 부분을 표지로 저장해.'),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70, width: 2),
          ),
          child: RepaintBoundary(
            key: _boundary,
            child: ClipRect(
              child: SizedBox(
                width: width,
                height: height,
                child: InteractiveViewer(
                  transformationController: _transform,
                  clipBehavior: Clip.hardEdge,
                  boundaryMargin: const EdgeInsets.all(500),
                  constrained: true,
                  minScale: 1,
                  maxScale: 6,
                  onInteractionEnd: (_) => setState(() {
                    _zoom = _transform.value.getMaxScaleOnAxis().clamp(1, 6).toDouble();
                  }),
                  child: Image.memory(
                    widget.bytes,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, __) =>
                        const Center(child: HypText('이미지를 열지 못했어.')),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.zoom_out, size: 19),
          Expanded(
            child: Slider(
              key: const Key('cover-crop-zoom'),
              value: _zoom.clamp(1, 6).toDouble(),
              min: 1,
              max: 6,
              onChanged: _saving ? null : _changeZoom,
            ),
          ),
          const Icon(Icons.zoom_in, size: 19),
        ]),
        TextButton.icon(
          onPressed: _saving ? null : () => _changeZoom(1),
          icon: const Icon(Icons.restart_alt),
          label: const HypText('위치 및 확대 초기화'),
        ),
        if (_error != null)
          HypText(_error!, style: const TextStyle(color: Colors.redAccent)),
      ]),
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context),
          child: const HypText('취소')),
      FilledButton.icon(
        key: const Key('cover-crop-save'),
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.crop),
        label: HypText(_saving ? '저장 중…' : '이 영역 저장'),
      ),
    ],
  );
}
