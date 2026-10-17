// Image-matching implementations are kept dormant for a future release.
// ignore_for_file: unused_element, unused_field
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../core/candidate_verifier.dart';
import '../core/cover_store.dart';
import '../core/gallery.dart';
import '../core/i18n.dart';
import '../l10n/app_localizations.dart';
import '../core/local_visual_index.dart';
import '../core/media_image_fetcher.dart';
import '../core/online_search.dart';
import '../core/reverse_image_search.dart';
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
  final TextEditingController _sauceKey = TextEditingController();
  final TextEditingController _manualText = TextEditingController();
  final List<RemoteImageHit> _remoteHits = [];
  final List<LocalVisualMatch> _localMatches = [];
  final Map<String, Future<Uint8List?>> _coverPreview = {};
  bool _remoteSearched = false;
  bool _localSearched = false;
  bool _showRemote = true;
  bool _loginWarningAdded = false;
  int _selectedImage = 0;
  String _publicPreview = '';
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
    _publicPreview,
    _manualText.text,
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
    _sauceKey.dispose();
    _manualText.dispose();
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
      final loc = AppLocalizations.of(context)!;
      for (final path in widget.initialImagePaths.take(8)) {
        try {
          final file = File(path);
          if (!await file.exists() ||
              await file.length() > 12 * 1024 * 1024) continue;
          await _addImage(await file.readAsBytes(), loc.inspectorShareImageSource);
        } catch (error) {
          if (mounted) setState(() =>
              _warnings.add(loc.inspectorReadShareError(error.toString())));
        }
      }
    });
  }

  Future<void> _pickImages() async {
    await _run(() async {
      final loc = AppLocalizations.of(context)!;
      final chosen = await FilePicker.platform.pickFiles(
          type: FileType.image, allowMultiple: true, withData: true);
      if (chosen == null) return;
      for (final file in chosen.files.take(12)) {
        final bytes = file.bytes;
        if (bytes != null) {
          await _addImage(bytes, loc.inspectorDeviceFile(file.name));
        } else if (file.path != null) {
          final local = File(file.path!);
          if (await local.exists() &&
              await local.length() <= 12 * 1024 * 1024) {
            await _addImage(await local.readAsBytes(),
                loc.inspectorDeviceFile(file.name));
          }
        }
      }
    });
  }

  Future<void> _readWeb() async {
    final controller = _web;
    if (controller == null || !_webReady) return;
    final loc = AppLocalizations.of(context)!;
    try {
      final value = await controller.evaluateJavascript(
          source: SocialWebCapture.javascript);
      final capture = SocialWebCapture.parse(value);
      if (!mounted) return;
      if (capture == null) {
        setState(() => _warnings.add(loc.inspectorPageReadError));
        await _fetchPublicPreview();
        return;
      }
      setState(() {
        _snapshot = capture;
        if (capture.loginRequired && !_loginWarningAdded) {
          _loginWarningAdded = true;
          _warnings.add(loc.inspectorLoginLimited);
        }
      });
      if (_query.text.trim().isEmpty) {
        final hint = SocialShareText.hints(
            capture.title + '\n' + capture.description);
        if (hint.title.isNotEmpty) _query.text = hint.title;
      }
      if ((capture.description.isEmpty || capture.loginRequired) &&
          widget.source?.canPreview == true) {
        await _fetchPublicPreview();
      }
    } catch (error) {
      if (mounted) setState(() => _warnings.add(
          loc.inspectorPageAnalyzeError(error.toString())));
      await _fetchPublicPreview();
    }
  }

  Future<void> _readAfterLoad() async {
    // Social web apps render asynchronously after onLoadStop.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && _webReady) await _readWeb();
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (mounted && _webReady) await _readWeb();
  }

  Future<void> _fetchPublicPreview() async {
    final source = widget.source;
    if (source == null || !source.canPreview || _publicPreview.isNotEmpty) {
      return;
    }
    final client = http.Client();
    try {
      final preview = await PublicSourcePreview(client).fetchDetailed(source);
      if (!mounted) return;
      setState(() => _publicPreview = preview.text);
    } catch (_) {
      // HTTP preview may be blocked even when the WebView is accessible.
    } finally {
      client.close();
    }
  }

  Future<void> _importRenderedImages() => _run(() async {
    final loc = AppLocalizations.of(context)!;
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
        await _addImage(bytes, loc.inspectorPublicPostImage);
        if (_images.length > before) accepted++;
        if (accepted >= 8) break;
      }
    } finally {
      client.close();
    }
    if (accepted == 0 && mounted) {
      setState(() => _warnings.add(
          loc.inspectorPublicImageFetchError));
    }
  });

  Future<void> _captureFrame() async {
    final loc = AppLocalizations.of(context)!;
    final screenshot = await _web?.takeScreenshot();
    if (screenshot == null) {
      if (mounted) setState(() => _warnings.add(
          loc.inspectorCaptureRestricted));
      return;
    }
    await _addImage(screenshot, loc.inspectorWebScreenshot);
  }

  Future<void> _captureCurrent() => _run(_captureFrame);

  Future<void> _sampleFrames() => _run(() async {
    final loc = AppLocalizations.of(context)!;
    if (!_isVideo) return;
    for (var i = 0; i < 4 && mounted && _images.length < 16; i++) {
      if (i > 0) await Future<void>.delayed(
          const Duration(milliseconds: 1100));
      await _captureFrame();
    }
    if (mounted) setState(() => _warnings.add(
        loc.inspectorSampleFrameNotice));
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
    final loc = AppLocalizations.of(context)!;
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
    setState(() {
      _localMatches..clear()..addAll(matches);
      _localSearched = true;
    });
    final ranked = VisualCandidateRanker.rank(
        extractedText: _collectedText,
        imageMatches: matches, savedWorks: widget.works);
    setState(() {
      _candidates..clear()..addAll(ranked);
      _verification.clear();
    });
    await _verify(ranked);
    if (ranked.isEmpty && mounted) setState(() => _warnings.add(
        loc.inspectorNoIdCandidates));
  });

  Future<void> _searchRemote() => _run(() async {
    final loc = AppLocalizations.of(context)!;
    if (_images.isEmpty) {
      setState(() => _warnings.add(loc.inspectorImageFirst));
      return;
    }
    final client = http.Client();
    try {
      final imageIndex = _selectedImage < _images.length ? _selectedImage : 0;
      final response = await ReverseImageSearch(client).search(
          _images[imageIndex], sauceNaoKey: _sauceKey.text.trim());
      if (!mounted) return;
      setState(() {
        _showRemote = true;
        _remoteSearched = true;
        _remoteHits..clear()..addAll(response.hits);
        _candidates.clear();
        _verification.clear();
        _warnings.addAll(response.warnings.take(3));
      });
      // A source image result does not prove any unrelated gallery ID.
      // Only a direct validated gallery URL can immediately offer its number.
      if (response.hits.isNotEmpty) {
        final direct = response.hits.where((hit) =>
            hit.workId.isNotEmpty).take(5).map((hit) => VisualCandidate(
              workId: hit.workId, title: hit.title,
              author: hit.author,
              evidence: loc.inspectorDirectSourceEvidence,
              kind: VisualEvidenceKind.onlineMetadata, score: 80,
            )).toList();
        if (direct.isNotEmpty) {
          setState(() => _candidates.addAll(direct));
          await _verify(direct);
        } else {
          final best = response.hits.where((hit) =>
              hit.title.trim().length >= 3 ||
              hit.author.trim().length >= 3).firstOrNull;
          if (best != null) await _lookupRemoteTitle(best);
        }
      }
    } finally {
      client.close();
    }
  });

  Future<void> _lookupRemoteTitle(RemoteImageHit hit) async {
    final query = hit.title.trim().length >= 3
        ? hit.title.trim() : hit.author.trim().length >= 3
            ? 'artist:' + hit.author.trim() : '';
    if (query.length < 3 || query.length > 150) return;
    final client = http.Client();
    try {
      final result = await OnlineWorkSearch(client).searchUnified(query);
      if (!mounted) return;
      final ranked = VisualCandidateRanker.rank(
          extractedText: _collectedText,
          onlineWorks: result.works.take(24).toList(),
          savedWorks: widget.works);
      setState(() {
        _query.text = query;
        _candidates..clear()..addAll(ranked);
        _verification.clear();
        _warnings.addAll(result.warnings.take(2));
      });
      await _verify(ranked);
    } catch (error) {
      if (mounted) setState(() => _warnings.add(
          AppLocalizations.of(context)!
              .inspectorRemoteLookupError(error.toString())));
    } finally {
      client.close();
    }
  }

  Future<void> _findOnlineForHit(RemoteImageHit hit) =>
      _run(() => _lookupRemoteTitle(hit));

  Future<void> _openExternalUrl(String raw) async {
    if (!ReverseImageSearch.safePublicUrl(raw)) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _pasteManually() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final value = clipboard?.text?.trim() ?? '';
    if (value.isNotEmpty && value.length <= 12000) {
      setState(() => _manualText.text = value);
    }
  }

  Future<Uint8List?> _readCover(String id) async {
    WorkEntry? work;
    for (final candidate in widget.works) {
      if (candidate.workId == id) {
        work = candidate;
        break;
      }
    }
    if (work == null || work.coverMode == 'preset') return null;
    try {
      return await widget.covers.read(id, mode: work.coverMode,
          page: work.coverMode == 'page' ? work.coverPage : 1);
    } catch (_) {
      return null;
    }
  }

  Future<void> _searchOnline() => _run(() async {
    final loc = AppLocalizations.of(context)!;
    final term = _query.text.trim();
    if (term.isEmpty || term.length > 150) {
      if (mounted) setState(() =>
          _warnings.add(loc.inspectorSearchLength));
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
    final loc = AppLocalizations.of(context)!;
    if (widget.source == null) return const SizedBox.shrink();
    if (!Platform.isAndroid && !Platform.isWindows) {
      return Text(loc.inspectorUnsupportedBrowser);
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
          final host = target?.host.toLowerCase() ?? '';
          final instagram = widget.source!.kind == SourceKind.instagramPost ||
              widget.source!.kind == SourceKind.instagramReel;
          final family = instagram
              ? const {'instagram.com', 'www.instagram.com', 'm.instagram.com'}
              : const {'youtube.com', 'www.youtube.com', 'm.youtube.com'};
          if (target == null || target.scheme != 'https' ||
              target.userInfo.isNotEmpty || target.hasPort ||
              !(host == original.host.toLowerCase() ||
                  family.contains(host))) {
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onLoadStop: (controller, url) {
          if (!mounted) return;
          setState(() => _webReady = true);
          unawaited(_readAfterLoad());
        },
      ),
    ));
  }

  Widget _resultThumb(String url, {Uint8List? memory}) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder = Icon(Icons.image_not_supported_outlined,
        color: scheme.onSurfaceVariant, size: 32);
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(width: 94, height: 118,
        child: ColoredBox(color: scheme.surfaceContainerHighest,
          child: memory != null
              ? Image.memory(memory, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => placeholder)
              : url.isNotEmpty && ReverseImageSearch.safePublicUrl(url)
                  ? Image.network(url, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => placeholder)
                  : placeholder,
        ),
      ),
    );
  }

  Widget _localThumb(String workId) {
    final future = _coverPreview.putIfAbsent(
        workId, () => _readCover(workId));
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) =>
          _resultThumb('', memory: snapshot.data),
    );
  }

  Widget _remoteCard(RemoteImageHit hit, AppLocalizations loc) {
    final source = Uri.tryParse(hit.sourceUrl);
    final hint = hit.similarity == null
        ? loc.inspectorUnscoredMatch
        : loc.inspectorSimilarity(hit.similarity!.toStringAsFixed(1));
    return Card(
      key: ValueKey('online-' + hit.sourceUrl),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _resultThumb(hit.thumbnailUrl),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.provider, style: Theme.of(context)
                      .textTheme.labelSmall),
                  const SizedBox(height: 4),
                  Text(hit.title.isEmpty ? loc.inspectorUnknownTitle : hit.title,
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                  if (hit.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(hit.author, maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 5),
                  Text(hint, style: Theme.of(context).textTheme.bodySmall),
                  Text(source?.host ?? '', maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
            ]),
            if (hit.workId.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(loc.inspectorLinkedWorkId(hit.workId),
                  style: Theme.of(context).textTheme.labelMedium),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(
                    () => _openExternalUrl(hit.sourceUrl)),
                icon: const Icon(Icons.open_in_new, size: 17),
                label: Text(loc.inspectorOpenSource),
              ),
              if (hit.title.trim().length >= 3 ||
                  hit.author.trim().length >= 3)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _findOnlineForHit(hit),
                  icon: const Icon(Icons.manage_search, size: 17),
                  label: Text(loc.inspectorFindGalleryNumber),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _localCard(LocalVisualMatch match, AppLocalizations loc) {
    final validId = RegExp(r'^\d{6,9}$').hasMatch(match.workId);
    return Card(
      key: ValueKey('local-' + match.workId),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _localThumb(match.workId),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(match.title.isEmpty
                      ? loc.workCardUntitled(match.workId) : match.title,
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                  if (match.author.isNotEmpty)
                    Text(match.author, maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Text(loc.inspectorSimilarity(
                        (match.similarity * 100).toStringAsFixed(1)),
                    style: Theme.of(context).textTheme.bodySmall),
                  Text(match.evidence, maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  Text('#' + match.workId),
                ],
              )),
            ]),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _busy || !validId ? null :
                    () => _accept(selected: VisualCandidate(
                      workId: match.workId, title: match.title,
                      author: match.author,
                      evidence: match.evidence,
                      kind: VisualEvidenceKind.localImage,
                      score: (match.similarity * 70).round())),
                icon: const Icon(Icons.playlist_add, size: 18),
                label: Text(loc.inspectorImportCandidate),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidateCard(VisualCandidate item, AppLocalizations loc) {
    final status = _verification[item.workId];
    final missed = status?.status == CandidateCheck.notFound;
    final label = status?.exists == true
        ? HypI18n.t(context, '번호 존재 확인')
        : missed ? HypI18n.t(context, '번호 미발견')
        : HypI18n.t(context, '번호 미검증');
    return Card(
      key: ValueKey('candidate-' + item.workId),
      child: Padding(padding: const EdgeInsets.all(12),
        child: Row(children: [
          CircleAvatar(radius: 21,
            child: Icon(item.kind == VisualEvidenceKind.directCode
                ? Icons.numbers : Icons.library_books_outlined)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title.isEmpty
                  ? loc.workCardUntitled(item.workId) : item.title,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
              Text('#' + item.workId + ' · ' + label,
                style: Theme.of(context).textTheme.bodySmall),
              Text(item.evidence, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          )),
          const SizedBox(width: 6),
          IconButton(
            tooltip: loc.inspectorImportCandidate,
            onPressed: _busy || missed ? null :
                () => _accept(selected: item),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ]),
      ),
    );
  }

  Widget _emptyResult(IconData icon, String title, String detail) {
    final colors = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Icon(icon, size: 40, color: colors.onSurfaceVariant),
        const SizedBox(height: 9),
        Text(title, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(detail, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _resultGrid<T>(List<T> values, double width,
      Widget Function(T) builder) {
    final cardWidth = width > 800 ? (width - 66) / 2 : width - 40;
    return Wrap(spacing: 9, runSpacing: 7,
      children: [for (final item in values)
        SizedBox(width: cardWidth, child: builder(item))]);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final size = MediaQuery.sizeOf(context);
    final width = size.width > 1020 ? 1000.0 : size.width * .96;
    final height = size.height > 880 ? 830.0 : size.height * .95;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: SizedBox(width: width, height: height,
        child: Padding(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.travel_explore, color: HypColors.lightPurple),
                const SizedBox(width: 9),
                Expanded(child: HypText('링크 고급 분석',
                    style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  tooltip: HypI18n.t(context, '닫기'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Expanded(child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.source != null) ...[
                      Text(loc.inspectorOnlyPublic,
                        style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 6),
                      _browser(),
                      const SizedBox(height: 7),
                      FilledButton.tonalIcon(
                        onPressed: _busy || !_webReady ? null :
                            () => _run(_readWeb),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(loc.inspectorRereadComments),
                      ),
                      const SizedBox(height: 7),
                      Text(loc.inspectorScrollBeforeRead,
                        style: Theme.of(context).textTheme.bodySmall),
                      if (_snapshot?.loginRequired == true) ...[
                        const SizedBox(height: 6),
                        Text(loc.inspectorLoginLimited),
                      ],
                      if (_snapshot != null || _publicPreview.isNotEmpty)
                        ExpansionTile(
                          initiallyExpanded: true,
                          title: Text(loc.inspectorDisplayedComments(
                              _snapshot?.comments.length ?? 0)),
                          subtitle: Text(loc.inspectorPreviewPartial),
                          childrenPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          children: [
                            if (_snapshot?.description.isNotEmpty == true)
                              SelectableText(_snapshot!.description,
                                  maxLines: 16),
                            if (_publicPreview.isNotEmpty &&
                                _publicPreview != _snapshot?.description)
                              SelectableText(_publicPreview, maxLines: 12),
                            for (final comment in
                                (_snapshot?.comments ?? const <String>[])
                                    .take(25))
                              ListTile(dense: true,
                                leading: const Icon(Icons.comment_outlined,
                                    size: 18),
                                title: SelectableText(comment)),
                          ],
                        ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _manualText,
                        minLines: 2, maxLines: 4,
                        maxLength: 12000,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: loc.inspectorManualPasteLabel,
                          helperText: loc.inspectorManualPasteHint,
                        ),
                      ),
                      Align(alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _pasteManually,
                          icon: const Icon(Icons.content_paste),
                          label: Text(loc.inspectorPasteClipboard),
                        ),
                      ),
                    ],
                    // Image search is intentionally disabled in v0.4.7.
                    // The standalone image page explains that it is coming soon.
                    const SizedBox(height: 8),
                    const HypText(
                      '이미지 검색은 준비 중이야. 이번 버전에서는 이미지 검색을 실행하지 않아.'),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _query, maxLength: 150,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: loc.inspectorSearchByTitle,
                        helperText: loc.inspectorSearchPrivacy,
                        suffixIcon: IconButton(
                          onPressed: _busy ? null : _searchOnline,
                          tooltip: loc.inspectorSearchTooltip,
                          icon: const Icon(Icons.search),
                        ),
                      ),
                      onSubmitted: (_) {
                        if (!_busy) _searchOnline();
                      },
                    ),
                    if (_candidates.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(loc.inspectorIdCandidateCount(_candidates.length),
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(loc.inspectorCandidateNotConfirmed,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 5),
                      for (final candidate in _candidates.take(20))
                        _candidateCard(candidate, loc),
                    ],
                    if (_warnings.isNotEmpty) ...[
                      const Divider(height: 20),
                      for (final warning in _warnings.reversed.take(4))
                        Padding(padding: const EdgeInsets.only(bottom: 5),
                          child: Text(warning, style:
                              Theme.of(context).textTheme.bodySmall)),
                    ],
                    const SizedBox(height: 10),
                    Text(loc.inspectorCaution,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              )),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context),
                  child: Text(loc.cancel)),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _accept(),
                  icon: const Icon(Icons.playlist_add),
                  label: Text(loc.inspectorImportAnalysis)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
