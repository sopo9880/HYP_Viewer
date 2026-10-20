import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/hitomi_web_search.dart';
import '../core/web_search_ad_block.dart';
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
  String? _error;

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

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    final browserSupported = Platform.isWindows || Platform.isAndroid;
    return Scaffold(
      appBar: AppBar(title: Text(labels.webSearchTitle), actions: [
        IconButton(
          key: const Key('web-search-toggle-adblock'),
          tooltip: _adsTemporarilyOff ? labels.webAdBlockResume : labels.webAdBlockPause,
          icon: Icon(_adsTemporarilyOff ? Icons.shield_outlined : Icons.shield),
          onPressed: () async {
            setState(() => _adsTemporarilyOff = !_adsTemporarilyOff);
            await _web?.setSettings(settings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              contentBlockers: WebSearchAdBlock.contentBlockers(
                  _adsTemporarilyOff ? 'off' : widget.adBlockMode),
            ));
            await _web?.reload();
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
            ? InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(HitomiWebSearch.searchUri(widget.query)
                      .toString()),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  contentBlockers: WebSearchAdBlock.contentBlockers(widget.adBlockMode),
                ),
                onWebViewCreated: (controller) => _web = controller,
                shouldOverrideUrlLoading: (controller, action) async {
                  final target = Uri.tryParse(
                      action.request.url?.toString() ?? '');
                  return HitomiWebSearch.allowedOrigin(target)
                      ? NavigationActionPolicy.ALLOW
                      : NavigationActionPolicy.CANCEL;
                },
                onLoadStart: (controller, url) {
                  if (mounted) setState(() => _loaded = false);
                },
                onLoadStop: (controller, url) {
                  if (mounted) setState(() => _loaded = true);
                  if (!_adsTemporarilyOff && widget.adBlockMode != 'off') {
                    controller.evaluateJavascript(source: WebSearchAdBlock.cleanPageJavaScript);
                  }
                },
                onReceivedError: (controller, request, error) {
                  if (mounted && request.isForMainFrame == true) {
                    setState(() => _error = labels.webSearchLoadFailed);
                  }
                },
              )
            : Center(child: Text(labels.webSearchUnsupported))),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_error != null) Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_error!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error))),
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
