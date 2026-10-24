import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/hitomi_web_search.dart';
import '../core/web_search_ad_block.dart';
import '../core/web_search_ad_rule_store.dart';
import '../core/windows_web_search.dart';

/// One-shot, bounded public website search. It is created only after the
/// user stops typing; no browser runs while search is empty or disabled.
/// The code reads only gallery links in the rendered public Hitomi DOM.
/// Login/cookies are never exported and there is no off-site navigation.
class AutoHitomiWebSearch extends StatefulWidget {
  final String query;
  final String adBlockMode;
  final void Function(String query, List<HitomiWebGallery> results,
      String? failure) onFinished;

  const AutoHitomiWebSearch({
    super.key, required this.query, required this.onFinished,
    this.adBlockMode = 'standard',
  });

  @override
  State<AutoHitomiWebSearch> createState() => _AutoHitomiWebSearchState();
}

class _AutoHitomiWebSearchState extends State<AutoHitomiWebSearch> {
  InAppWebViewController? _controller;
  Timer? _timeout;
  Timer? _collectTimer;
  bool _done = false;
  bool _loaded = false;
  String? _loadError;
  Future<WebViewEnvironment?>? _environment;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) _environment = WindowsWebSearchRuntime.environment;
    // The Windows cosmetic-only fallback never needs network filter lists.
    if (widget.adBlockMode != 'off' && !Platform.isWindows) {
      WebSearchAdRuleStore.instance.ensureStarted();
    }
    _timeout = Timer(const Duration(seconds: 12), () {
      _finish(const [], _loadError ?? 'web-search-timeout');
    });
  }

  @override
  void dispose() {
    _collectTimer?.cancel();
    _timeout?.cancel();
    _controller = null;
    super.dispose();
  }

  void _finish(List<HitomiWebGallery> items, String? reason) {
    if (_done || !mounted) return;
    _done = true;
    _timeout?.cancel();
    _collectTimer?.cancel();
    widget.onFinished(widget.query, items, reason);
  }

  void _scheduleCapture([Duration delay = const Duration(milliseconds: 1300)]) {
    _collectTimer?.cancel();
    _collectTimer = Timer(delay, () => unawaited(_capture()));
  }

  Future<void> _capture() async {
    final web = _controller;
    if (!mounted || _done || !_loaded || web == null) return;
    try {
      final url = Uri.tryParse((await web.getUrl())?.toString() ?? '');
      if (!HitomiWebSearch.allowedOrigin(url)) {
        _finish(const [], 'web-origin-rejected');
        return;
      }
      final response = await web.evaluateJavascript(
          source: HitomiWebSearch.captureJavaScript);
      if (!mounted || _done) return;
      final found = HitomiWebSearch.parseCapture(response);
      if (found.isNotEmpty) {
        _finish(found, null);
      } else {
        // Hitomi populates some public result elements asynchronously.
        _scheduleCapture(const Duration(seconds: 2));
      }
    } catch (_) {
      if (mounted && !_done) {
        _loadError = 'web-capture-failed';
        _scheduleCapture(const Duration(seconds: 2));
      }
    }
  }

  Widget _buildWebView(WebViewEnvironment? environment) {
    return SizedBox(
      key: const Key('automatic-web-search'),
      width: 2,
      height: 2,
      child: InAppWebView(
        webViewEnvironment: environment,
        initialUserScripts: UnmodifiableListView<UserScript>(
          widget.adBlockMode == 'off' || Platform.isWindows
              ? <UserScript>[]
              : [UserScript(
                  source: WebSearchAdBlock.cleanPageJavaScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START)],
        ),
        initialUrlRequest: URLRequest(
          url: WebUri(HitomiWebSearch.searchUri(widget.query).toString()),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true, useShouldOverrideUrlLoading: true,
          useShouldInterceptRequest: !Platform.isWindows && widget.adBlockMode != 'off',
          supportMultipleWindows: true,
          javaScriptCanOpenWindowsAutomatically: false,
          contentBlockers: Platform.isWindows ? const <ContentBlocker>[]
              : WebSearchAdBlock.contentBlockers(widget.adBlockMode),
        ),
        onWebViewCreated: (controller) => _controller = controller,
        shouldInterceptRequest: Platform.isWindows ? null : (controller, request) async =>
            WebSearchAdBlock.intercept(request, widget.adBlockMode),
        // Never let a background search create ad tabs or off-site windows.
        onCreateWindow: (controller, action) async => false,
        shouldOverrideUrlLoading: (controller, action) async {
          final url = Uri.tryParse(action.request.url?.toString() ?? '');
          return HitomiWebSearch.allowedOrigin(url)
              ? NavigationActionPolicy.ALLOW
              : NavigationActionPolicy.CANCEL;
        },
        onLoadStart: (controller, url) {
          _loaded = false;
          _collectTimer?.cancel();
        },
        onLoadStop: (controller, url) {
          if (!mounted || _done) return;
          _loaded = true;
          if (widget.adBlockMode != 'off') {
            unawaited(controller.evaluateJavascript(
                source: WebSearchAdBlock.cleanPageJavaScript));
          }
          _scheduleCapture();
        },
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame == true) {
            _loadError = 'web-load-failed';
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const SizedBox.shrink();
    }
    // Non-zero layout allows the native WebView to render its DOM; it is not
    // an always-running background service. Disposed at success or timeout.
    if (Platform.isWindows) {
      return FutureBuilder<WebViewEnvironment?>(
        future: _environment,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _finish(const [], 'webview2-initialization-failed');
            });
            return const SizedBox.shrink();
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(width: 2, height: 2);
          }
          return _buildWebView(snapshot.data);
        },
      );
    }
    return _buildWebView(null);
  }
}

/// Pure search gating and cache rules, regression-tested across platforms.
class AutoWebSearchPolicy {
  static const debounce = Duration(milliseconds: 950);
  static const cacheTtl = Duration(minutes: 10);
  static bool shouldSearch({
    required bool enabled, required String query, required String scope,
  }) => enabled && scope != 'local' && query.trim().isNotEmpty &&
      query.trim().length <= 150 &&
      (Platform.isWindows || Platform.isAndroid);
}
