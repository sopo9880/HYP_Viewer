import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/hitomi_web_search.dart';
import '../core/web_search_ad_block.dart';
import '../core/web_search_ad_rule_store.dart';
import '../core/windows_web_search.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

/// User-controlled Hitomi search browser. Only gallery links from the
/// currently rendered page are read, and only when the user taps Collect.
class HitomiWebSearchPage extends StatefulWidget {
  final String query;
  final String adBlockMode;

  const HitomiWebSearchPage({super.key, required this.query,
      this.adBlockMode = 'standard'});

  @override
  State<HitomiWebSearchPage> createState() => _HitomiWebSearchPageState();
}

class _HitomiWebSearchPageState extends State<HitomiWebSearchPage> {
  InAppWebViewController? _web;
  final Map<String, HitomiWebGallery> _collected = {};
  bool _loaded = false;
  bool _busy = false;
  bool _adsTemporarilyOff = false;
  Future<WebViewEnvironment?>? _environment;
  Timer? _loadTimer;
  int _viewGeneration = 0;
  String? _error;
  String? _currentUrl;
  final ValueNotifier<int> _blockedCount = ValueNotifier(0);
  bool get _adBlockingEnabled =>
      widget.adBlockMode != 'off' && !_adsTemporarilyOff;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) _environment = WindowsWebSearchRuntime.environment;
    // The Windows cosmetic-only fallback never needs network filter lists.
    if (widget.adBlockMode != 'off' && !Platform.isWindows) {
      WebSearchAdRuleStore.instance.ensureStarted();
    }
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _blockedCount.dispose();
    super.dispose();
  }

  Future<void> _collect() async {
    final web = _web;
    if (web == null || !_loaded || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final url = await web.getUrl();
      if (!HitomiWebSearch.allowedOrigin(
          Uri.tryParse(url?.toString() ?? ''))) {
        throw const FormatException('The current page is not Hitomi');
      }
      final raw = await web.evaluateJavascript(
          source: HitomiWebSearch.captureJavaScript);
      final items = HitomiWebSearch.parseCapture(raw);
      if (!mounted) return;
      setState(() {
        for (final item in items) {
          _collected.putIfAbsent(item.workId, () => item);
        }
        if (items.isEmpty) {
          _error = AppLocalizations.of(context)!.webSearchNoLinks;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            AppLocalizations.of(context)!.webSearchCaptureFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Widget _windowsWebViewError(String details) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Windows WebView2 검색 화면을 시작하지 못했어요.'),
        const SizedBox(height: 8),
        SelectableText(details, maxLines: 4),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          OutlinedButton(
            onPressed: () {
              WindowsWebSearchRuntime.retryFailedInitialization();
              setState(() {
                _environment = WindowsWebSearchRuntime.environment;
                _viewGeneration++;
              });
            },
            child: const Text('다시 시도'),
          ),
          TextButton(
            onPressed: _openExternalSearch,
            child: const Text('외부 브라우저에서 열기'),
          ),
        ]),
      ]),
    ),
  );

  Future<void> _openExternalSearch() async {
    final target = HitomiWebSearch.searchUri(widget.query);
    await launchUrl(target, mode: LaunchMode.externalApplication);
  }

  Widget _buildWebView(
      BuildContext context, WebViewEnvironment? environment) {
    final labels = AppLocalizations.of(context)!;
    return InAppWebView(
                key: ValueKey('hitomi-ad-block-$_adBlockingEnabled-$_viewGeneration'),
                webViewEnvironment: environment,
                initialUserScripts: UnmodifiableListView<UserScript>(
                  _adBlockingEnabled && !Platform.isWindows
                      ? [UserScript(
                          source: WebSearchAdBlock.cleanPageJavaScript,
                          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START)]
                      : <UserScript>[],
                ),
                initialUrlRequest: URLRequest(
                  url: WebUri(_currentUrl ??
                      HitomiWebSearch.searchUri(widget.query).toString()),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  useShouldInterceptRequest: !Platform.isWindows && _adBlockingEnabled,
                  supportMultipleWindows: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  // Windows compatibility mode avoids WebView2 native interception
                  // at creation; apply cosmetic filtering after load instead.
                  contentBlockers: Platform.isWindows ? const <ContentBlocker>[]
                      : WebSearchAdBlock.contentBlockers(
                          _adBlockingEnabled ? widget.adBlockMode : 'off'),
                ),
                onWebViewCreated: (controller) => _web = controller,
                shouldInterceptRequest: Platform.isWindows ? null : (controller, request) async =>
                    WebSearchAdBlock.intercept(request,
                        _adBlockingEnabled ? widget.adBlockMode : 'off',
                        onBlocked: () {
                          if (mounted) _blockedCount.value++;
                        }),
                onCreateWindow: (controller, action) async {
                  final target = Uri.tryParse(
                      action.request.url?.toString() ?? '');
                  if (action.hasGesture == true &&
                      HitomiWebSearch.allowedOrigin(target)) {
                    await controller.loadUrl(urlRequest:
                        URLRequest(url: WebUri(target.toString())));
                  }
                  return false;
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  final target = Uri.tryParse(
                      action.request.url?.toString() ?? '');
                  return HitomiWebSearch.allowedOrigin(target)
                      ? NavigationActionPolicy.ALLOW
                      : NavigationActionPolicy.CANCEL;
                },
                onLoadStart: (controller, url) {
                  _loadTimer?.cancel();
                  _loadTimer = Timer(const Duration(seconds: 15), () {
                    if (mounted && !_loaded) {
                      setState(() => _error =
                          '웹 검색 화면 로딩이 지연되고 있어요. 다시 시도하거나 외부 브라우저로 열어 주세요.');
                    }
                  });
                  if (mounted) setState(() { _loaded = false; _error = null; });
                },
                onLoadStop: (controller, url) {
                  _loadTimer?.cancel();
                  if (mounted) setState(() { _loaded = true; _error = null; });
                  if (HitomiWebSearch.allowedOrigin(
                      Uri.tryParse(url?.toString() ?? ''))) {
                    _currentUrl = url.toString();
                  }
                  if (_adBlockingEnabled) {
                    unawaited(controller.evaluateJavascript(
                        source: WebSearchAdBlock.cleanPageJavaScript));
                  }
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == true) _loadTimer?.cancel();
                  if (mounted && request.isForMainFrame == true) {
                    setState(() => _error = labels.webSearchLoadFailed);
                  }
                },
              );
  }

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    final browserSupported = Platform.isWindows || Platform.isAndroid;
    return Scaffold(
      appBar: AppBar(title: Text(labels.webSearchTitle), actions: [
        ValueListenableBuilder<int>(
          valueListenable: _blockedCount,
          builder: (context, count, child) => Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('${labels.webAdBlockBlockedLabel} $count',
                  style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
        ),
        IconButton(
          key: const Key('web-search-toggle-adblock'),
          tooltip: _adBlockingEnabled
              ? labels.webAdBlockPause : labels.webAdBlockResume,
          icon: Icon(_adBlockingEnabled ? Icons.shield : Icons.shield_outlined),
          onPressed: widget.adBlockMode == 'off' ? null : () {
            // Rebuild the native view so document-start script and network
            // interception switch together, including on Windows.
            setState(() {
              _adsTemporarilyOff = !_adsTemporarilyOff;
              _loaded = false;
              _web = null;
              _error = null;
              _blockedCount.value = 0;
              _viewGeneration++;
            });
          },
        ),
      ]),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Text(labels.webSearchHelp,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: browserSupported
            ? (Platform.isWindows
                ? FutureBuilder<WebViewEnvironment?>(
                    future: _environment,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _windowsWebViewError(snapshot.error.toString());
                      }
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _buildWebView(context, snapshot.data);
                    },
                  )
                : _buildWebView(context, null))
            : Center(child: Text(labels.webSearchUnsupported))),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_error != null) Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(children: [
                Text(_error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
                if (Platform.isWindows)
                  Wrap(spacing: 8, children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _error = null;
                        _loaded = false;
                        _viewGeneration++;
                      }),
                      child: const Text('검색 다시 시도'),
                    ),
                    TextButton(
                      onPressed: _openExternalSearch,
                      child: const Text('외부 브라우저에서 열기'),
                    ),
                  ]),
              ])),
            Text(labels.webSearchCollected(_collected.length),
                key: const Key('web-search-collected-count')),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('web-search-capture-links'),
                  onPressed: browserSupported && _loaded && !_busy
                      ? _collect : null,
                  icon: const Icon(Icons.travel_explore_outlined),
                  label: Text(labels.webSearchCollect),
                ),
                FilledButton.icon(
                  key: const Key('web-search-apply-results'),
                  onPressed: _collected.isNotEmpty
                      ? () => Navigator.of(context)
                          .pop(_collected.values.toList(growable: false))
                      : null,
                  icon: const Icon(Icons.playlist_add_check),
                  label: Text(labels.webSearchApply),
                ),
              ],
            ),
          ]),
        ),
      ])),
    );
  }
}
