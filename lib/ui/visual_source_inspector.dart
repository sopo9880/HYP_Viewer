import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../core/candidate_verifier.dart';
import '../core/cover_store.dart';
import '../core/gallery.dart';
import '../core/i18n.dart';
import '../core/local_visual_index.dart';
import '../core/media_image_fetcher.dart';
import '../core/online_search.dart';
import '../core/social_share_text.dart';
import '../core/social_web_capture.dart';
import '../core/source_links.dart';
import '../core/visual_candidate_ranker.dart';
import '../core/visual_ocr.dart';
import '../core/visual_signature.dart';
import '../core/work.dart';
import 'hyp_theme.dart';

class VisualInspectionResult {
  final String text, workId, title, author, sourceUrl;
  final bool verified;
  const VisualInspectionResult({required this.text, this.workId = '',
    this.title = '', this.author = '', this.sourceUrl = '',
    this.verified = false});
}

/// User-controlled inspector. WebView only sees the explicitly shared/opened
/// source; local-image OCR and similarity do not send image bytes externally.
class VisualSourceInspector extends StatefulWidget {
  final SourceLink? source;
  final String sharedText;
  final List<String> initialImagePaths;
  final List<WorkEntry> works;
  final CoverStore covers;
  final GalleryStore galleries;
  final Future<Map<String, CandidateVerification>> Function(List<String>)
      verifyCandidates;

  const VisualSourceInspector({super.key, this.source,
    this.sharedText = '', this.initialImagePaths = const [],
    required this.works, required this.covers, required this.galleries,
    required this.verifyCandidates});

  @override
  State<VisualSourceInspector> createState() => _VisualSourceInspectorState();
}

class _VisualSourceInspectorState extends State<VisualSourceInspector> {
  InAppWebViewController? _web;
  SocialWebCapture? _snapshot;
  final LocalVisualIndex _index = const LocalVisualIndex();
  final List<Uint8List> _images = [];
  final List<VisualSignature> _signatures = [];
  final List<String> _imageSources = [];
  final List<String> _warnings = [];
  final TextEditingController _query = TextEditingController();
  final List<VisualCandidate> _candidates = [];
  final Map<String, CandidateVerification> _verification = {};
  bool _busy = false;
  bool _webReady = false;
  int _indexed = 0;
  int _indexProgress = 0;
  int _indexTotal = 0;
  String _recognizedText = '';

  bool get _isVideo => widget.source?.kind == SourceKind.instagramReel ||
      widget.source?.kind == SourceKind.youtubeVideo;

  String get _collectedText => [
    widget.sharedText,
    _snapshot?.combinedText ?? '',
    _recognizedText,
  ].where((text) => text.trim().isNotEmpty).toSet().join('\n\n');

  @override
  void initState() {
    super.initState();
    final hint = SocialShareText.hints(widget.sharedText);
    _query.text = hint.title.isNotEmpty ? hint.title :
        hint.author.isNotEmpty ? 'artist:' + hint.author : '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.initialImagePaths.isNotEmpty) {
        unawaited(_loadInitialImages());
      }
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _warnings.add(error.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addImage(Uint8List bytes, String source) async {
    if (bytes.isEmpty || bytes.length > 12 * 1024 * 1024 ||
        _images.length >= 16) return;
    final signature = await VisualSignature.fromImage(bytes);
    if (signature == null) return;
    if (_signatures.any((other) => signature.similarity(other) > 0.985)) return;
    if (!mounted) return;
    setState(() {
      _images.add(bytes);
      _signatures.add(signature);
      _imageSources.add(source);
    });
  }

  Future<void> _loadInitialImages() async {
    await _run(() async {
      for (final path in widget.initialImagePaths.take(8)) {
        try {
          final file = File(path);
          if (!await file.exists() ||
              await file.length() > 12 * 1024 * 1024) continue;
          await _addImage(await file.readAsBytes(), '공유 이미지');
        } catch (error) {
          if (mounted) setState(() =>
              _warnings.add('공유 이미지를 읽지 못했어: $error'));
        }
      }
    });
  }

  Future<void> _pickImages() async {
    await _run(() async {
      final chosen = await FilePicker.platform.pickFiles(
          type: FileType.image, allowMultiple: true, withData: true);
      if (chosen == null) return;
      for (final file in chosen.files.take(12)) {
        final bytes = file.bytes;
        if (bytes != null) {
          await _addImage(bytes, '내 기기: ' + file.name);
        } else if (file.path != null) {
          final local = File(file.path!);
          if (await local.exists() &&
              await local.length() <= 12 * 1024 * 1024) {
            await _addImage(await local.readAsBytes(),
                '내 기기: ' + file.name);
          }
        }
      }
    });
  }

  Future<void> _readWeb() async {
    final controller = _web;
    if (controller == null || !_webReady) return;
    try {
      final value = await controller.evaluateJavascript(
          source: SocialWebCapture.javascript);
      final result = SocialWebCapture.parse(value);
      if (result == null) {
        if (mounted) setState(() => _warnings.add(
            '페이지 내용을 읽지 못했어. 원문을 복사하거나 캡처해줘.'));
        return;
      }
      if (!mounted) return;
      setState(() => _snapshot = result);
      if (_query.text.trim().isEmpty) {
        final hint = SocialShareText.hints(result.title + '\n' +
            result.description);
        if (hint.title.isNotEmpty) _query.text = hint.title;
      }
    } catch (error) {
      if (mounted) setState(() => _warnings.add(
          '접근 가능한 웹 본문을 분석하지 못했어: $error'));
    }
  }

  Future<void> _importRenderedImages() => _run(() async {
    await _readWeb();
    final links = _snapshot?.imageUrls ?? [];
    final client = http.Client();
    var accepted = 0;
    try {
      for (final url in links.take(12)) {
        if (_images.length >= 16) break;
        final bytes = await MediaImageFetcher.fetch(client, url);
        if (bytes == null) continue;
        final before = _images.length;
        await _addImage(bytes, '공개 게시물 이미지');
        if (_images.length > before) accepted++;
        if (accepted >= 8) break;
      }
    } finally {
      client.close();
    }
    if (accepted == 0 && mounted) {
      setState(() => _warnings.add(
          '공개 이미지 원본에 접근하지 못했어. 화면 캡처를 사용해줘.'));
    }
  });

  Future<void> _captureFrame() async {
    final screenshot = await _web?.takeScreenshot();
    if (screenshot == null) {
      if (mounted) setState(() => _warnings.add(
          '화면 캡처가 제한되어 있어. 갤러리 이미지 공유를 사용해줘.'));
      return;
    }
    await _addImage(screenshot, '앱 내 웹 화면 캡처');
  }

  Future<void> _captureCurrent() => _run(_captureFrame);

  Future<void> _sampleFrames() => _run(() async {
    if (!_isVideo) return;
    for (var i = 0; i < 4 && mounted && _images.length < 16; i++) {
      if (i > 0) await Future<void>.delayed(
          const Duration(milliseconds: 1100));
      await _captureFrame();
    }
    if (mounted) setState(() => _warnings.add(
        '현재 재생 가능한 프레임만 분석했어. 영상이 멈춰 있거나 보호된 경우 '
        '장면이 추가되지 않을 수 있어.'));
  });

  Future<void> _rebuildIndex() => _run(() async {
    setState(() { _indexProgress = 0; _indexTotal = 0; });
    final count = await _index.rebuild(widget.works,
      covers: widget.covers, galleries: widget.galleries,
      onProgress: (completed, total) {
        if (mounted) setState(() {
          _indexProgress = completed;
          _indexTotal = total;
        });
      },
    );
    if (mounted) setState(() => _indexed = count);
  });

  Future<void> _verify(List<VisualCandidate> candidates) async {
    final ids = candidates.map((item) => item.workId).take(24).toList();
    if (ids.isEmpty) return;
    final verified = await widget.verifyCandidates(ids);
    if (mounted) setState(() => _verification.addAll(verified));
  }

  Future<void> _analyze() => _run(() async {
    final ocr = <String>[];
    final warnings = <String>[];
    for (final image in _images.take(8)) {
      final result = await const VisualOcr().analyze(image);
      if (result.text.trim().isNotEmpty) ocr.add(result.text.trim());
      warnings.addAll(result.warnings);
    }
    if (!mounted) return;
    setState(() {
      _recognizedText = ocr.toSet().join('\n\n');
      _warnings.addAll(warnings.take(3));
    });
    final matches = await _index.search(_images);
    if (!mounted) return;
    final ranked = VisualCandidateRanker.rank(
        extractedText: _collectedText,
        imageMatches: matches, savedWorks: widget.works);
    setState(() {
      _candidates..clear()..addAll(ranked);
      _verification.clear();
    });
    await _verify(ranked);
    if (ranked.isEmpty && mounted) setState(() => _warnings.add(
        '번호 후보가 없어. 로컬 인덱스를 만들거나 제목·작가로 온라인 검색해줘.'));
  });

  Future<void> _searchOnline() => _run(() async {
    final term = _query.text.trim();
    if (term.isEmpty || term.length > 150) {
      if (mounted) setState(() =>
          _warnings.add('검색어는 1~150자로 입력해줘.'));
      return;
    }
    final client = http.Client();
    try {
      // Only the user-entered title/artist query is sent. The private
      // library, screenshots and OCR images are never sent.
      final result = await OnlineWorkSearch(client).searchUnified(term);
      if (!mounted) return;
      final ranked = VisualCandidateRanker.rank(
          extractedText: _collectedText,
          onlineWorks: result.works.take(24).toList(),
          savedWorks: widget.works);
      setState(() {
        _candidates..clear()..addAll(ranked);
        _verification.clear();
        _warnings.addAll(result.warnings.take(2));
      });
      await _verify(ranked);
    } finally {
      client.close();
    }
  });

  void _accept({VisualCandidate? selected}) {
    final checked = selected == null ? null : _verification[selected.workId];
    Navigator.of(context).pop(VisualInspectionResult(
      text: _collectedText,
      workId: selected?.workId ?? '',
      title: selected?.title ?? '',
      author: selected?.author ?? '',
      sourceUrl: widget.source?.url ?? '',
      verified: checked?.exists == true,
    ));
  }

  Widget _browser() {
    if (widget.source == null) return const SizedBox.shrink();
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const HypText('이 환경은 앱 내부 브라우저를 지원하지 않아.');
    }
    return SizedBox(height: 310, child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: InAppWebView(
        initialUrlRequest: URLRequest(
            url: WebUri(widget.source!.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useShouldOverrideUrlLoading: true,
          mediaPlaybackRequiresUserGesture: true,
        ),
        onWebViewCreated: (controller) {
          _web = controller;
        },
        shouldOverrideUrlLoading: (controller, navigation) async {
          final url = navigation.request.url?.toString();
          final target = url == null ? null : Uri.tryParse(url);
          // No navigation to unrelated origin, non-HTTPS, or userinfo URLs.
          final original = widget.source!.uri;
          if (target == null || target.scheme != 'https' ||
              target.userInfo.isNotEmpty ||
              target.host.toLowerCase() != original.host.toLowerCase()) {
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onLoadStop: (controller, url) {
          if (!mounted) return;
          setState(() => _webReady = true);
          unawaited(_readWeb());
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width > 980 ? 960.0 : size.width * .96;
    final height = size.height > 780 ? 740.0 : size.height * .94;
    final hasImages = _images.isNotEmpty;
    return Dialog(
      child: SizedBox(width: width, height: height,
        child: Padding(padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome, color: HypColors.lightPurple),
                const SizedBox(width: 9),
                Expanded(child: HypText('링크·이미지 통합 작품 분석',
                  style: Theme.of(context).textTheme.titleLarge)),
                IconButton(tooltip: HypI18n.t(context, '닫기'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close)),
              ]),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 10),
              Expanded(child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.source != null) ...[
                      HypText('앱 내부 원본 화면 · 공개되거나 표시된 정보만 읽어와',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 5),
                      _browser(),
                      const SizedBox(height: 9),
                      Wrap(spacing: 7, runSpacing: 7, children: [
                        OutlinedButton.icon(
                          onPressed: _busy || !_webReady ? null :
                              () => _run(_readWeb),
                          icon: const Icon(Icons.article_outlined),
                          label: const HypText('본문·표시된 댓글 분석')),
                        OutlinedButton.icon(
                          onPressed: _busy || !_webReady ? null :
                              _importRenderedImages,
                          icon: const Icon(Icons.image_search_outlined),
                          label: const HypText('게시물 이미지 자동 추출')),
                        OutlinedButton.icon(
                          onPressed: _busy || !_webReady ? null :
                              _captureCurrent,
                          icon: const Icon(Icons.screenshot_monitor),
                          label: const HypText('현재 화면 캡처')),
                        if (_isVideo) OutlinedButton.icon(
                          onPressed: _busy || !_webReady ? null :
                              _sampleFrames,
                          icon: const Icon(Icons.movie_filter_outlined),
                          label: const HypText('영상 주요 프레임 샘플링')),
                      ]),
                      const SizedBox(height: 12),
                    ],
                    Wrap(spacing: 7, runSpacing: 7, children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickImages,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const HypText('내 기기 이미지 선택')),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _rebuildIndex,
                        icon: const Icon(Icons.data_object_outlined),
                        label: const HypText('내 서재 이미지 인덱스 만들기')),
                      FilledButton.icon(
                        onPressed: _busy ? null : _analyze,
                        icon: const Icon(Icons.travel_explore),
                        label: const HypText('로컬 OCR·이미지 검색')),
                    ]),
                    if (_indexTotal > 0) ...[
                      const SizedBox(height: 5),
                      LinearProgressIndicator(value: _indexTotal == 0
                          ? 0 : _indexProgress / _indexTotal),
                      HypText('서재 인덱스 생성 ' +
                          _indexProgress.toString() + '/' +
                          _indexTotal.toString() + ' · 지문 ' +
                          _indexed.toString() + '개'),
                    ],
                    if (hasImages) ...[
                      const SizedBox(height: 12),
                      HypText('분석 이미지 · ' + _images.length.toString() +
                          '개', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      SizedBox(height: 88, child: ListView.separated(
                        scrollDirection: Axis.horizontal, itemCount: _images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 7),
                        itemBuilder: (_, index) => Tooltip(
                          message: _imageSources[index],
                          child: ClipRRect(borderRadius: BorderRadius.circular(8),
                            child: Image.memory(_images[index],
                                width: 88, height: 88, fit: BoxFit.cover)),
                        ),
                      )),
                    ],
                    if (_snapshot != null) ...[
                      const SizedBox(height: 8),
                      HypText('현재 페이지 본문: ' +
                          _snapshot!.description.characters.take(120).toString()),
                      HypText('현재 로딩된 댓글 ' +
                          _snapshot!.comments.length.toString() + '개 · '
                          '댓글 전체를 수집했다는 의미는 아니야'),
                    ],
                    if (_recognizedText.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      const HypText('로컬 OCR 결과'),
                      SelectableText(_recognizedText,
                          maxLines: 5),
                    ],
                    const SizedBox(height: 15),
                    TextField(
                      controller: _query, maxLength: 150,
                      decoration: InputDecoration(
                        labelText: HypI18n.t(context, '제목·작가로 온라인 검색'),
                        helperText: HypI18n.t(context,
                            '이미지는 보내지 않고 입력한 검색어만 전송해'),
                        suffixIcon: IconButton(
                          onPressed: _busy ? null : _searchOnline,
                          tooltip: HypI18n.t(context, '온라인 후보 검색'),
                          icon: const Icon(Icons.public),
                        ),
                      ),
                      onSubmitted: (_) { if (!_busy) _searchOnline(); },
                    ),
                    OutlinedButton.icon(onPressed: _busy ? null : _searchOnline,
                        icon: const Icon(Icons.search),
                        label: const HypText('온라인 제목·작가 후보 찾기')),
                    if (_candidates.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      HypText('작품 번호 후보 · ' +
                          _candidates.length.toString() + '개',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      for (final item in _candidates.take(20))
                        Card(child: ListTile(
                          dense: true,
                          title: Text((item.title.isEmpty ? '작품 ' +
                              item.workId : item.title) + ' · #' + item.workId),
                          subtitle: Text(item.evidence +
                            ' · ' + (_verification[item.workId]?.exists == true
                                ? HypI18n.t(context, '번호 존재 확인')
                                : _verification[item.workId]?.status ==
                                        CandidateCheck.notFound
                                    ? HypI18n.t(context, '번호 미발견')
                                    : HypI18n.t(context, '번호 미검증'))),
                          trailing: TextButton(
                            onPressed: _verification[item.workId]?.status ==
                                    CandidateCheck.notFound
                                ? null : () => _accept(selected: item),
                            child: const HypText('Finder로 가져오기'),
                          ),
                        )),
                    ],
                    if (_warnings.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final warning in _warnings.reversed.take(3))
                        Text(warning, style: Theme.of(context)
                            .textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    const HypText('이미지 일치·검색 결과만으로 작품을 확정하지 않아. '
                        '공개 댓글은 실제 화면에 로딩된 것만 분석할 수 있어.'),
                  ],
                ),
              )),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context),
                  child: const HypText('취소')),
                const SizedBox(width: 9),
                FilledButton.icon(
                  onPressed: () => _accept(),
                  icon: const Icon(Icons.playlist_add),
                  label: const HypText('분석 내용 Finder로 가져오기')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
