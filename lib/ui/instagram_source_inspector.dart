import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../core/number_extractor.dart';
import '../core/social_web_capture.dart';
import '../core/source_links.dart';
import 'visual_source_inspector.dart';

/// Instagram-only text reader. No frame capture, reverse image search or
/// network endpoints other than the user-opened Instagram page.
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
  SocialWebCapture? _snapshot;
  final TextEditingController _manual = TextEditingController();
  String _status = '페이지를 불러오는 중';
  bool _reading = false;
  bool _loaded = false;

  String get _text => [
    widget.sharedText, _snapshot?.combinedText ?? '', _manual.text,
  ].where((s) => s.trim().isNotEmpty).toSet().join('\n\n');

  Future<void> _read() async {
    if (!_loaded || _web == null || _reading) return;
    _reading = true;
    try {
      final raw = await _web!.evaluateJavascript(
        source: SocialWebCapture.javascript);
      final result = SocialWebCapture.parse(raw);
      if (!mounted) return;
      setState(() {
        if (result == null) {
          _status = '본문 구조 확인 실패 · 다시 읽거나 직접 붙여넣기';
        } else {
          _snapshot = result;
          _status = result.loginRequired ? 'Instagram 로그인 필요' :
            result.description.isEmpty && result.comments.isEmpty ?
              '본문·댓글 미로딩 또는 접근 제한' :
            result.comments.isEmpty ? '본문 확인 · 댓글 미로딩' :
              '공개 화면에 표시된 댓글 ${result.comments.length}개 수집';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _status = '페이지 읽기 오류 · 수동 입력 가능');
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ids = NumberExtractor.extract(_text, source: widget.source.url)
      .map((c) => c.code).toSet().toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.article_outlined),
                const SizedBox(width: 10),
                const Expanded(child: Text('Instagram 게시물·릴스 분석',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 8),
              Text(_status),
              const SizedBox(height: 8),
              Expanded(child: ListView(children: [
                if (Platform.isAndroid || Platform.isWindows)
                  SizedBox(height: 345, child: InAppWebView(
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
                          (host == 'instagram.com' ||
                          host.endsWith('.instagram.com'))
                          ? NavigationActionPolicy.ALLOW
                          : NavigationActionPolicy.CANCEL;
                    },
                    onLoadStop: (_, __) {
                      _loaded = true;
                      _poll?.cancel();
                      _poll = Timer.periodic(const Duration(seconds: 3),
                          (_) => unawaited(_read()));
                      unawaited(_read());
                    },
                  ))
                else const Text('현재 플랫폼에서는 웹뷰를 지원하지 않아.'),
                const SizedBox(height: 10),
                OutlinedButton.icon(onPressed: () => unawaited(_read()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('화면에서 보이는 본문·댓글 다시 읽기')),
                const SizedBox(height: 10),
                const Text('게시글 본문',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(_snapshot?.description.isNotEmpty == true
                  ? _snapshot!.description : '읽은 본문이 없어.'),
                const SizedBox(height: 12),
                Text('댓글 (화면에서 확인된 ${_snapshot?.comments.length ?? 0}개)',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                for (final comment in _snapshot?.comments ?? <String>[])
                  ListTile(dense: true, title: SelectableText(comment)),
                if (_snapshot?.comments.isEmpty != false)
                  const Text('댓글이 없는 것으로 단정할 수 없어. 직접 스크롤 후 다시 읽어줘.'),
                const SizedBox(height: 12),
                Text('번호 후보: ${ids.join(', ')}'),
                const SizedBox(height: 10),
                TextField(controller: _manual, maxLines: 4, minLines: 2,
                  maxLength: 12000,
                  decoration: const InputDecoration(
                    labelText: '본문·댓글 직접 붙여넣기',
                    border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {})),
                const Text('비공개 게시물이나 로드되지 않은 댓글은 자동으로 수집하지 않아.'),
              ])),
              const SizedBox(height: 9),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context),
                    child: const Text('취소')),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => Navigator.pop(context,
                  VisualInspectionResult(text: _text,
                    sourceUrl: widget.source.url)),
                  child: const Text('후보를 Finder로 전달')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
