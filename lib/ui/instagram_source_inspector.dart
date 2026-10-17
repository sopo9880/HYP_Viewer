import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/i18n.dart';
import '../core/number_extractor.dart';
import '../core/social_web_capture.dart';
import '../core/source_links.dart';
import 'visual_source_inspector.dart';

/// Full-page, user-controlled Instagram post/reel viewer.
/// Only previously rendered public DOM content is inspected; comments are
/// not fetched from private APIs and login/visibility limits are respected.
class InstagramSourceInspector extends StatefulWidget {
  final SourceLink source;
  final String sharedText;
  const InstagramSourceInspector({
    super.key, required this.source, this.sharedText = '',
  });

  @override
  State<InstagramSourceInspector> createState() =>
      _InstagramSourceInspectorState();
}

class _InstagramSourceInspectorState extends State<InstagramSourceInspector> {
  InAppWebViewController? _web;
  Timer? _poll;
  final SocialCommentAccumulator _collected = SocialCommentAccumulator();
  final TextEditingController _manual = TextEditingController();
  String _status = '페이지를 불러오는 중';
  bool _reading = false;
  bool _loaded = false;

  String get _text => [
    widget.sharedText,
    _collected.combinedText,
    _manual.text,
  ].where((part) => part.trim().isNotEmpty).toSet().join('\n\n');

  void _deliver() => Navigator.of(context).pop(VisualInspectionResult(
    text: _text, sourceUrl: widget.source.url));

  Future<void> _read() async {
    if (!_loaded || _web == null || _reading || !mounted) return;
    _reading = true;
    try {
      final raw = await _web!.evaluateJavascript(
        source: SocialWebCapture.javascript);
      final snapshot = SocialWebCapture.parse(raw);
      if (!mounted) return;
      setState(() {
        if (snapshot == null) {
          _status = '본문 구조 확인 실패 · 다시 읽거나 직접 붙여넣기';
          return;
        }
        final newCount = _collected.add(snapshot);
        if (_collected.loginRequired) {
          _status = 'Instagram 로그인 필요';
        } else if (_collected.count > 0) {
          _status = newCount > 0
              ? '공개 화면 댓글 수집 완료'
              : '기존 댓글을 유지하면서 새 댓글을 기다리는 중';
        } else if (_collected.commentAreaPresent) {
          _status = '댓글 영역 감지 · 댓글을 펼친 후 다시 읽어줘';
        } else if (_collected.description.isNotEmpty) {
          _status = '본문 확인 · 댓글 미로딩';
        } else {
          _status = '본문·댓글 미로딩 또는 접근 제한';
        }
      });
    } catch (_) {
      if (mounted) setState(() =>
        _status = '페이지 읽기 오류 · 수동 입력 가능');
    } finally {
      _reading = false;
    }
  }

  Widget _browser() {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const Center(
        child: HypText('현재 플랫폼에서는 웹뷰를 지원하지 않아.'));
    }
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.source.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: true,
      ),
      onWebViewCreated: (controller) => _web = controller,
      shouldOverrideUrlLoading: (_, action) async {
        final target = Uri.tryParse(action.request.url.toString());
        final host = target?.host.toLowerCase() ?? '';
        return target != null && target.scheme == 'https' &&
            target.userInfo.isEmpty && !target.hasPort &&
            (host == 'instagram.com' || host.endsWith('.instagram.com'))
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onLoadStart: (_, __) {
        _loaded = false;
        _poll?.cancel();
      },
      onLoadStop: (controller, __) async {
        try {
          await controller.evaluateJavascript(
            source: SocialWebCapture.observerJavascript);
        } catch (_) {
          // Some public pages restrict injected JS; manual paste remains.
        }
        if (!mounted) return;
        _loaded = true;
        _poll?.cancel();
        _poll = Timer.periodic(const Duration(seconds: 3),
            (_) => unawaited(_read()));
        unawaited(_read());
      },
    );
  }

  Widget _results({ScrollController? controller, bool mobile = false}) {
    final ids = NumberExtractor.extract(_text, source: widget.source.url)
        .map((candidate) => candidate.code).toSet().toList();
    final strings = _collected.comments;
    final pinned = _collected.pinnedComments.toSet();
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        if (mobile) Center(child: Container(
          width: 42, height: 5,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        )),
        const HypText('수집된 내용',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        HypText(_status),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loaded && !_reading ? () => unawaited(_read()) : null,
          icon: const Icon(Icons.refresh),
          label: const HypText('화면에서 보이는 본문·댓글 다시 읽기'),
        ),
        const SizedBox(height: 8),
        const HypText('게시글 본문',
          style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        SelectableText(_collected.description.isEmpty
            ? HypI18n.t(context, '읽은 본문이 없어.')
            : _collected.description),
        const SizedBox(height: 12),
        Text(HypI18n.t(context, '누적 수집된 댓글') + ': ' +
            _collected.count.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        if (strings.isEmpty) const HypText(
          '인스타그램 화면에서 댓글을 직접 펼치고 스크롤한 뒤 다시 읽어줘.'),
        for (final comment in strings)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: pinned.contains(comment)
              ? const Icon(Icons.push_pin_outlined, size: 18)
              : const Icon(Icons.chat_bubble_outline, size: 18),
            title: SelectableText(comment),
          ),
        const SizedBox(height: 8),
        Text(HypI18n.t(context, '번호 후보') + ': ' +
            (ids.isEmpty ? '-' : ids.join(', '))),
        const SizedBox(height: 10),
        TextField(
          controller: _manual,
          minLines: 2, maxLines: 5,
          maxLength: 12000,
          decoration: InputDecoration(
            labelText: HypI18n.t(context, '본문·댓글 직접 붙여넣기'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const HypText(
          '비공개 게시물이나 로드되지 않은 댓글은 자동으로 수집하지 않아.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _deliver,
          icon: const Icon(Icons.arrow_forward),
          label: const HypText('후보를 Finder로 전달'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const HypText('Instagram 게시물·릴스 분석'),
      actions: [
        IconButton(
          tooltip: HypI18n.t(context, '화면에서 보이는 본문·댓글 다시 읽기'),
          onPressed: _loaded && !_reading ? () => unawaited(_read()) : null,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: LayoutBuilder(builder: (context, dimensions) {
      if (Platform.isWindows && dimensions.maxWidth >= 860) {
        return Row(children: [
          Expanded(flex: 7, child: _browser()),
          const VerticalDivider(width: 1),
          Expanded(flex: 3, child: _results()),
        ]);
      }
      // On phones the WebView gets the full usable screen. The adjustable
      // results sheet floats above it and never competes for scroll gestures.
      return Stack(children: [
        Positioned.fill(child: _browser()),
        DraggableScrollableSheet(
          initialChildSize: 0.22,
          minChildSize: 0.12,
          maxChildSize: 0.92,
          snap: true,
          snapSizes: const [0.12, 0.22, 0.65],
          builder: (context, scrollController) => Material(
            elevation: 12,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: _results(controller: scrollController, mobile: true),
          ),
        ),
      ]);
    }),
  );
}
