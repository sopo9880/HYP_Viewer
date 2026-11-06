import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/reader_settings.dart';
import '../core/web_page_capture.dart';
import '../core/web_viewer_store.dart';
import '../core/windows_web_search.dart';
import '../core/work.dart';
import '../l10n/app_localizations.dart';
import 'gallery_reader.dart';

/// WEB is independent of the HYP library, but uses the existing image reader.
class WebViewerPane extends StatefulWidget {
  final WebViewerStore store;
  final String section;
  final ReaderSettings settings;
  const WebViewerPane({super.key, required this.store,
      required this.section, required this.settings});
  @override
  State<WebViewerPane> createState() => _WebViewerPaneState();
}

class _WebViewerPaneState extends State<WebViewerPane> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
    widget.store.load().catchError((Object error) {
      if (mounted) _error(error);
    });
  }
  @override
  void didUpdateWidget(covariant WebViewerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_changed);
      widget.store.addListener(_changed);
    }
  }
  @override
  void dispose() {
    widget.store.removeListener(_changed);
    super.dispose();
  }
  void _changed() { if (mounted) setState(() {}); }
  void _error(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())));
  }

  Future<void> _addSite() => _editSite();

  Future<void> _editSite({WebSiteBookmark? editing}) async {
    final labels = AppLocalizations.of(context)!;
    final name = TextEditingController(text: editing?.name ?? '');
    final address = TextEditingController(text: editing?.url ?? 'https://');
    final confirmed = await showDialog<bool>(
      context: context, builder: (ctx) => AlertDialog(
        title: Text(editing == null
            ? labels.webViewerAddSite : labels.webViewerEditSite),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name,
              decoration: InputDecoration(labelText: labels.webViewerSiteName)),
          TextField(controller: address, keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: labels.webViewerSiteAddress)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(labels.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(labels.webViewerSave)),
        ],
      ),
    );
    final n = name.text, url = address.text;
    name.dispose(); address.dispose();
    if (confirmed != true) return;
    try {
      if (editing == null) {
        await widget.store.addSite(n, url);
      } else {
        await widget.store.updateSite(editing.url, n, url);
      }
    } catch (error) { if (mounted) _error(error); }
  }

  Future<void> _confirmRemoveSite(WebSiteBookmark site) async {
    final labels = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context, builder: (ctx) => AlertDialog(
        title: Text(labels.webViewerDeleteSiteConfirm),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(site.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(site.url, maxLines: 3, overflow: TextOverflow.ellipsis),
          ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(labels.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(labels.webViewerDelete)),
        ],
      ),
    );
    if (accepted != true) return;
    try { await widget.store.removeSite(site.url); }
    catch (error) { if (mounted) _error(error); }
  }

  Future<void> _openSite(String url) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => WebViewerBrowser(store: widget.store, initialUrl: url),
    ));
  }

  Future<void> _openWork(WebSavedWork item) async {
    try {
      final gallery = await widget.store.galleries;
      final archive = await gallery.read(item.id);
      if (!mounted) return;
      final entry = WorkEntry.create(
        workId: item.id, title: item.title,
        author: item.author, videoUrl: item.sourceUrl,
        sourceUrls: [item.sourceUrl],
      ).copyWith(totalPages: item.pages, currentPage: item.currentPage);
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => GalleryReader(
          work: entry, archive: archive, settings: widget.settings,
          diskCacheEnabled: false,
          onPageChanged: (page) => widget.store.updatePage(item.id, page),
          onOpenInBrowser: (_) => _openSite(item.sourceUrl),
        ),
      ));
    } catch (error) { if (mounted) _error(error); }
  }

  Future<void> _rename(WebSavedWork item) async {
    final labels = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: item.title);
    final result = await showDialog<String>(
      context: context, builder: (ctx) => AlertDialog(
        title: Text(labels.webViewerRename),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(labels.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(labels.webViewerSave)),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      try { await widget.store.renameWork(item.id, result); }
      catch (error) { if (mounted) _error(error); }
    }
  }

  Widget _sites(AppLocalizations labels) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: [
        Expanded(child: Text(labels.webViewerSites,
            style: Theme.of(context).textTheme.titleLarge)),
        FilledButton.icon(onPressed: _addSite, icon: const Icon(Icons.add),
            label: Text(labels.webViewerAddSite)),
      ]),
      if (widget.store.lastTab != null) ...[
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.history),
            label: Text(labels.webViewerLastTab),
            onPressed: () => _openSite(widget.store.lastTab!.url),
          ),
        ),
        Text(widget.store.lastTab!.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
      const SizedBox(height: 14),
      if (widget.store.sites.isEmpty)
        Text(labels.webViewerEmptySites)
      else
        for (final site in widget.store.sites)
          Card(child: ListTile(
            leading: const Icon(Icons.public),
            title: Text(site.name), subtitle: Text(site.url,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _openSite(site.url),
            trailing: PopupMenuButton<String>(
              tooltip: labels.webViewerEditSite,
              onSelected: (action) {
                if (action == 'edit') _editSite(editing: site);
                if (action == 'delete') _confirmRemoveSite(site);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit',
                  child: Text(labels.webViewerEditSite)),
                PopupMenuItem(value: 'delete',
                  child: Text(labels.webViewerDelete)),
              ],
            ),
          )),
    ],
  );

  Widget _works(AppLocalizations labels, {int? count}) {
    final items = count == null ? widget.store.works :
        widget.store.works.take(count).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(count == null ? labels.webViewerLibrary : labels.webViewerRecent,
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (items.isEmpty) Text(labels.webViewerNoWorks),
      for (final item in items) Card(child: ListTile(
        leading: const Icon(Icons.auto_stories),
        title: Text(item.title),
        subtitle: Text(item.author + ' · ' +
          item.currentPage.toString() + '/' + item.pages.toString()),
        onTap: () => _openWork(item),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'read') { await _openWork(item); }
            if (action == 'rename') { await _rename(item); }
            if (action == 'source') { await _openSite(item.sourceUrl); }
            if (action == 'delete') {
              try { await widget.store.removeWork(item.id); }
              catch (error) { if (mounted) _error(error); }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'read', child: Text(labels.webViewerRead)),
            PopupMenuItem(value: 'rename', child: Text(labels.webViewerRename)),
            PopupMenuItem(value: 'source', child: Text(labels.webViewerSource)),
            PopupMenuItem(value: 'delete', child: Text(labels.webViewerDelete)),
          ],
        ),
      )),
    ]);
  }

  Widget _downloads(AppLocalizations labels) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(labels.webViewerDownloads,
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (widget.store.pending.isEmpty)
        Text(labels.webViewerEmptyDownloads),
      for (final id in widget.store.pending)
        Card(child: ListTile(
          leading: const Icon(Icons.download),
          title: Text(widget.store.captures[id]?.title ?? id),
          subtitle: LinearProgressIndicator(
            value: widget.store.captures[id]?.images.isNotEmpty == true
                ? (widget.store.progress[id] ?? 0) /
                  widget.store.captures[id]!.images.length : 0.0,
          ),
          trailing: id == widget.store.activeId ?
              IconButton(
                tooltip: widget.store.paused
                    ? labels.webViewerResume : labels.webViewerPause,
                onPressed: widget.store.togglePause,
                icon: Icon(widget.store.paused ? Icons.play_arrow : Icons.pause),
              ) : null,
        )),
      if (widget.store.activeId != null)
        OutlinedButton.icon(
          onPressed: widget.store.cancelCurrent,
          icon: const Icon(Icons.cancel_outlined),
          label: Text(labels.webViewerCancel),
        ),
      if (widget.store.errors.isNotEmpty)
        Align(alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.store.clearAllFailedDownloads,
            icon: const Icon(Icons.delete_sweep),
            label: Text(labels.webViewerClearFailed),
          ),
        ),
      for (final error in widget.store.errors.entries.toList())
        Card(child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(error.key),
          subtitle: Text(error.value,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => showDialog<void>(
            context: context, builder: (ctx) => AlertDialog(
              title: Text(labels.webViewerErrorDetails),
              content: SingleChildScrollView(
                child: SelectableText(error.value)),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text(labels.cancel))],
            ),
          ),
          trailing: IconButton(
            tooltip: labels.webViewerClearError,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => widget.store.clearFailedDownload(error.key),
          ),
        )),
    ],
  );

  Widget _settings(AppLocalizations labels) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(labels.webViewerSettings,
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      SwitchListTile(
        value: widget.store.autoSelectImages,
        onChanged: (v) async {
          try { await widget.store.setAutoSelectImages(v); }
          catch (error) { if (mounted) _error(error); }
        },
        title: Text(labels.webViewerAutoSelect),
        subtitle: Text(labels.webViewerAutoSelectHelp),
      ),
      ListTile(
        leading: const Icon(Icons.shield_outlined),
        title: Text(labels.webViewerSettingsNote),
      ),
      Text(labels.webViewerSettingsInfo),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    if (!widget.store.isReady) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (widget.section) {
      'web' => _sites(labels),
      'library' => _works(labels),
      'downloads' => _downloads(labels),
      'settings' => _settings(labels),
      _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(labels.webViewerHome,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(child: ListTile(
          leading: const Icon(Icons.public),
          title: Text(labels.webViewerSites),
          subtitle: Text(widget.store.sites.length.toString()),
          onTap: _addSite,
          trailing: IconButton(onPressed: _addSite,
            icon: const Icon(Icons.add)),
        )),
        const SizedBox(height: 10),
        _works(labels, count: 8),
      ]),
    };
  }
}

/// User-controlled generic WebView, independent of Hitomi's origin restrictions.
/// Images are inspected only after an explicit button press.
class WebViewerBrowser extends StatefulWidget {
  final WebViewerStore store;
  final String initialUrl;
  const WebViewerBrowser({super.key, required this.store,
      required this.initialUrl});
  @override
  State<WebViewerBrowser> createState() => _WebViewerBrowserState();
}

class _WebViewerBrowserState extends State<WebViewerBrowser> {
  InAppWebViewController? _web;
  Future<WebViewEnvironment?>? _environment;
  bool _loaded = false, _busy = false;
  String _currentUrl = '';
  WebPageCapture? _capture;
  final Set<int> _selected = {};
  final _title = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    if (Platform.isWindows) {
      _environment = WindowsWebSearchRuntime.environment;
    }
  }
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }
  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())));
  }
  Future<void> _rememberVisit(
      InAppWebViewController controller, String? rawUrl) async {
    if (rawUrl == null || WebViewerStore.safeUrl(rawUrl) == null) return;
    try {
      final title = await controller.getTitle();
      final host = Uri.tryParse(rawUrl)?.host ?? rawUrl;
      await widget.store.recordVisitedPage(rawUrl, title ?? host);
    } catch (_) {
      // Navigation must continue even if a title is unavailable.
    }
  }

  Future<void> _saveCurrentTab() async {
    final labels = AppLocalizations.of(context)!;
    final uri = WebViewerStore.safeUrl(_currentUrl);
    if (uri == null || !_loaded || _web == null) return;
    try {
      if (widget.store.sites.any((site) => site.url == uri.toString())) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.webViewerAlreadySaved)));
        return;
      }
      final pageTitle = await _web!.getTitle();
      if (!mounted) return;
      final suggested = pageTitle?.trim().isNotEmpty == true
          ? pageTitle!.trim() : uri.host;
      final name = TextEditingController(text: suggested);
      final accepted = await showDialog<bool>(
        context: context, builder: (ctx) => AlertDialog(
          title: Text(labels.webViewerSaveCurrentTab),
          content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(uri.toString(), maxLines: 3,
                overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              TextField(controller: name,
                decoration: InputDecoration(
                  labelText: labels.webViewerSiteName)),
            ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(labels.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(labels.webViewerSave)),
          ],
        ),
      );
      final chosen = name.text;
      name.dispose();
      if (accepted != true) return;
      await widget.store.addSite(chosen, uri.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(labels.webViewerSavedCurrentTab)));
    } catch (error) { _error(error); }
  }

  Future<void> _openRecentTabs() async {
    final labels = AppLocalizations.of(context)!;
    final pages = widget.store.recentPages.toList();
    final selected = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.65,
        child: Column(children: [
          ListTile(title: Text(labels.webViewerRecentTabs)),
          if (pages.isEmpty)
            Expanded(child: Center(child: Text(labels.webViewerNoRecentTabs)))
          else
            Expanded(child: ListView.builder(
              itemCount: pages.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.history),
                title: Text(pages[i].name, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(pages[i].url, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, pages[i].url),
              ),
            )),
        ]),
      )),
    );
    if (selected == null || !mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => WebViewerBrowser(
        store: widget.store, initialUrl: selected)),
    );
  }

  Future<void> _captureImages() async {
    final web = _web;
    if (web == null || !_loaded || _busy) return;
    setState(() => _busy = true);
    try {
      final raw = await web.evaluateJavascript(
          source: WebPageCapture.captureJavaScript);
      final found = WebPageCapture.parse(raw);
      if (found == null) {
        throw const FormatException('No public article images found');
      }
      if (found.images.isEmpty) {
        throw FormatException(found.expectedImages > 0
            ? AppLocalizations.of(context)!.webViewerWaitingImages
            : 'No public article images found');
      }
      if (!mounted) return;
      setState(() {
        _capture = found;
        _title.text = found.title;
        _selected.clear();
        if (widget.store.autoSelectImages) {
          _selected.addAll(List.generate(found.images.length, (i) => i));
        }
      });
    } catch (error) { _error(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _queue() async {
    final capture = _capture;
    if (capture == null || _busy || _selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.store.enqueue(capture, _selected.toList(),
          title: _title.text.trim().isEmpty ? capture.title : _title.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (error) { _error(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Widget _browser(WebViewEnvironment? environment) => InAppWebView(
    webViewEnvironment: environment,
    initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true, useShouldOverrideUrlLoading: true,
      useShouldInterceptRequest: false, supportMultipleWindows: false,
      javaScriptCanOpenWindowsAutomatically: false,
      contentBlockers: const <ContentBlocker>[],
    ),
    onWebViewCreated: (controller) => _web = controller,
    onLoadStart: (_, __) {
      if (mounted) setState(() { _loaded = false; _capture = null; });
    },
    onLoadStop: (controller, url) {
      if (mounted) setState(() {
        _loaded = true;
        _currentUrl = url?.toString() ?? _currentUrl;
      });
      unawaited(_rememberVisit(controller, url?.toString()));
    },
    onUpdateVisitedHistory: (controller, url, __) {
      if (mounted) setState(() => _currentUrl =
          url?.toString() ?? _currentUrl);
      unawaited(_rememberVisit(controller, url?.toString()));
    },
    shouldOverrideUrlLoading: (_, action) async {
      final url = action.request.url?.toString() ?? '';
      return WebViewerStore.safeUrl(url) == null
          ? NavigationActionPolicy.CANCEL
          : NavigationActionPolicy.ALLOW;
    },
  );

  Widget _preview(AppLocalizations labels) {
    final capture = _capture!;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(
        controller: _title,
        decoration: InputDecoration(labelText: labels.webViewerPageTitle),
      )),
      if (capture.expectedImages > capture.images.length)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(labels.webViewerMissingImages,
            style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Row(children: [
        const SizedBox(width: 10),
        Expanded(child: Text(
          labels.webViewerDetectedOfTotal + ': ' +
          capture.images.length.toString() + ' / ' +
          capture.expectedImages.toString())),
        TextButton(onPressed: () => setState(() {
          _selected..clear()..addAll(List.generate(capture.images.length, (i) => i));
        }), child: Text(labels.webViewerSelectAll)),
        TextButton(onPressed: () => setState(_selected.clear),
            child: Text(labels.webViewerDeselectAll)),
      ]),
      TextButton.icon(
        onPressed: () => setState(() => _capture = null),
        icon: const Icon(Icons.arrow_back),
        label: Text(labels.webViewerBackToBrowser),
      ),
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 155, childAspectRatio: 0.7,
          crossAxisSpacing: 7, mainAxisSpacing: 7),
        itemCount: capture.images.length,
        itemBuilder: (_, i) {
          final selected = _selected.contains(i);
          return InkWell(
            onTap: () => setState(() =>
              selected ? _selected.remove(i) : _selected.add(i)),
            child: Stack(children: [
              Positioned.fill(child: Image.network(
                capture.images[i].url.toString(), fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))),
              Positioned(top: 2, right: 2,
                child: Checkbox(value: selected, onChanged: (value) =>
                  setState(() => value == true
                      ? _selected.add(i) : _selected.remove(i)))),
              Positioned(left: 3, bottom: 2,
                child: Text(capture.images[i].order.toString())),
            ]),
          );
        },
      )),
      Padding(padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: _busy || _selected.isEmpty ? null : _queue,
          icon: const Icon(Icons.download),
          label: Text(labels.webViewerQueued +
              ' (' + _selected.length.toString() + ')'),
        )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(_currentUrl,
          maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(onPressed: () async => _web?.goBack(),
            icon: const Icon(Icons.arrow_back), tooltip: labels.webViewerBack),
          IconButton(onPressed: () => _web?.reload(),
            icon: const Icon(Icons.refresh), tooltip: labels.webViewerRefresh),
          IconButton(
            onPressed: _busy || !_loaded ? null : _saveCurrentTab,
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: labels.webViewerSaveCurrentTab),
          IconButton(
            onPressed: _openRecentTabs,
            icon: const Icon(Icons.history),
            tooltip: labels.webViewerRecentTabs),
          IconButton(
            onPressed: _busy || !_loaded ? null : _captureImages,
            icon: const Icon(Icons.image_search),
            tooltip: labels.webViewerDetect),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(
          child: Platform.isWindows
            ? FutureBuilder<WebViewEnvironment?>(
              future: _environment,
              builder: (_, state) {
                if (state.hasError) {
                  return Center(child: Column(mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(state.error.toString()),
                      TextButton(
                        onPressed: () {
                          WindowsWebSearchRuntime.retryFailedInitialization();
                          setState(() => _environment =
                              WindowsWebSearchRuntime.environment);
                        },
                        child: Text(labels.webViewerRetry),
                      ),
                      TextButton(onPressed: () =>
                          launchUrl(Uri.parse(widget.initialUrl),
                              mode: LaunchMode.externalApplication),
                        child: Text(labels.webViewerOpenExternal)),
                    ],
                  ));
                }
                if (state.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _browser(state.data);
              },
            ) : _browser(null),
        ),
        if (_capture != null)
          Positioned.fill(child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: _preview(labels),
          )),
      ]),
    );
  }
}
