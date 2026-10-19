import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/hitomi_web_search.dart';

/// One-shot, bounded public website search. It is created only after the
/// user stops typing; no browser runs while search is empty or disabled.
/// The code reads only gallery links in the rendered public Hitomi DOM.
/// Login/cookies are never exported and there is no off-site navigation.
class AutoHitomiWebSearch extends StatefulWidget {
  final String query;
  final void Function(String query, List<HitomiWebGallery> results,
      String? failure) onFinished;

  const AutoHitomiWebSearch({
    super.key, required this.query, required this.onFinished,
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

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const SizedBox.shrink();
    }
    // Non-zero layout allows the native WebView to render its DOM; it is not
    // an always-running background service. Disposed at success or timeout.
    return SizedBox(
      key: const Key('automatic-web-search'),
      width: 2,
      height: 2,
      child: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(HitomiWebSearch.searchUri(widget.query).toString()),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true, useShouldOverrideUrlLoading: true,
        ),
        onWebViewCreated: (controller) => _controller = controller,
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
