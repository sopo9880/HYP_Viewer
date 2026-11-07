import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/reader_settings.dart';
import '../core/web_page_capture.dart';
import '../core/web_series_capture.dart';
import '../core/web_series_library.dart';
import '../core/web_viewer_store.dart';
import '../core/windows_web_search.dart';
import '../core/work.dart';
import '../l10n/app_localizations.dart';
import 'gallery_reader.dart';
import 'web_series_selector.dart';
import 'web_series_shelf.dart';
import 'series_viewer_pages.dart';
import 'web_library_visuals.dart';
import 'web_visit_history.dart';
import 'hero_banner.dart';
import 'hyp_theme.dart';
import 'update_apk_cleanup_panel.dart';

/// WEB is independent of the HYP library, but uses the existing image reader.
class WebViewerPane extends StatefulWidget {
  final WebViewerStore store;
  final String section;
  final ReaderSettings settings;
  final ValueChanged<String>? onNavigate;
  final bool updating;
  const WebViewerPane({super.key, required this.store,
      required this.section, required this.settings,
      this.onNavigate, this.updating = false});
  @override
  State<WebViewerPane> createState() => _WebViewerPaneState();
}

class _WebViewerPaneState extends State<WebViewerPane> {
  final _heroCovers = <String, Uint8List?>{};
  final _heroLoading = <String>{};

  void _primeHeroCovers() {
    if (!mounted || !widget.store.isReady) return;
    final seriesMode = widget.section.startsWith('series_');
    final candidates = widget.store.works.where((work) =>
        seriesMode ? work.seriesUrl != null : work.seriesUrl == null).toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    for (final work in candidates.take(3)) {
      if (_heroCovers.containsKey(work.id) || !_heroLoading.add(work.id)) {
        continue;
      }
      widget.store.coverFor(work.id).then((bytes) {
        if (mounted) setState(() => _heroCovers[work.id] = bytes);
      }).catchError((Object _) {
        if (mounted) setState(() => _heroCovers[work.id] = null);
      }).whenComplete(() => _heroLoading.remove(work.id));
    }
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
    widget.store.load().then((_) {
      _primeHeroCovers();
    }).catchError((Object error) {
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
  void _changed() {
    if (!mounted) return;
    setState(() {});
    _primeHeroCovers();
  }
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

  Future<void> _openSite(String url, {bool scanSeries = false}) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => WebViewerBrowser(store: widget.store,
        initialUrl: url, autoScanSeries: scanSeries),
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
            onPressed: () async {
              final url = await WebVisitHistorySheet.open(
                  context, widget.store);
              if (url != null && mounted) await _openSite(url);
            },
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

  Future<void> _openSeries(WebSeriesRecord group) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => WebSeriesShelf(
        series: group,
        hideCompleted: widget.store.seriesHideCompleted,
        onRefreshSource: () => _openSite(group.url, scanSeries: true),
        onOpenEpisode: (episode) {
          final savedId = episode.workId;
          WebSavedWork? work;
          if (savedId != null) {
            for (final item in widget.store.works) {
              if (item.id == savedId) { work = item; break; }
            }
          }
          if (work != null) {
            _openWork(work);
          } else {
            _openSite(episode.url);
          }
        },
      ),
    ));
  }

  Future<void> _confirmRemoveWork(WebSavedWork work) async {
    final labels = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.webViewerDelete),
        content: Text(work.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(labels.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(labels.webViewerDelete)),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await widget.store.removeWork(work.id);
    } catch (error) {
      if (mounted) _error(error);
    }
  }

  List<WebVisualEntry> _workEntries(AppLocalizations labels) {
    return widget.store.works.where((work) => work.seriesUrl == null).map(
      (work) {
        final progress = work.pages <= 1
            ? 0.0 : ((work.currentPage - 1) / (work.pages - 1))
                .clamp(0.0, 1.0).toDouble();
        return WebVisualEntry(
          id: work.id, title: work.title,
          subtitle: work.author.isEmpty ? work.sourceUrl : work.author,
          detail: work.currentPage.toString() + ' / ' + work.pages.toString(),
          coverWorkId: work.id, modifiedAt: work.savedAt,
          progress: progress, downloaded: true,
          icon: Icons.auto_stories_rounded,
          onOpen: () { _openWork(work); },
          actions: {
            'read': labels.webViewerRead,
            'rename': labels.webViewerRename,
            'source': labels.webViewerSource,
            'delete': labels.webViewerDelete,
          },
          onAction: (action) {
            if (action == 'read') _openWork(work);
            if (action == 'rename') _rename(work);
            if (action == 'source') _openSite(work.sourceUrl);
            if (action == 'delete') _confirmRemoveWork(work);
          },
        );
      },
    ).toList();
  }

  Widget _works(AppLocalizations labels) => WebVisualLibrary(
    key: const Key('web-full-cover-library'),
    store: widget.store,
    title: labels.webViewerLibrary,
    subtitle: labels.webVisualLibraryDescription,
    icon: Icons.library_books_rounded,
    items: _workEntries(labels),
    emptyMessage: labels.webViewerNoWorks,
  );

  Widget _home(AppLocalizations labels) {
    final entries = _workEntries(labels)
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    final continueEntries = entries.where((work) => work.progress > 0).toList()
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    final heroIds = entries.take(3).map((work) => work.id).toList();
    final artwork = List<Uint8List?>.generate(
      3, (index) => index < heroIds.length
        ? _heroCovers[heroIds[index]] : null);
    final keys = List<String?>.generate(
      3, (index) => index < heroIds.length ? heroIds[index] : null);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HypHeroBanner(
        viewerLabel: 'WEB Viewer',
        bannerIcon: Icons.public_rounded,
        slideTitles: [
          labels.webVisualHeroTitle1,
          labels.webVisualHeroTitle2,
          labels.webVisualHeroTitle3,
        ],
        slideDescriptions: [
          labels.webVisualHeroDesc1,
          labels.webVisualHeroDesc2,
          labels.webVisualHeroDesc3,
        ],
        rotatingArtworks: artwork,
        rotatingArtworkKeys: keys,
        onOpenArtwork: (id) {
          for (final work in widget.store.works) {
            if (work.id == id) { _openWork(work); break; }
          }
        },
        onOpenLibrary: () => widget.onNavigate?.call('library'),
        onOpenDownloads: () => widget.onNavigate?.call('downloads'),
      ),
      const SizedBox(height: 20),
      if (continueEntries.isNotEmpty) ...[
        WebVisualLibrary(
          key: const Key('web-continue-reading'),
          store: widget.store,
          title: labels.webVisualContinue,
          subtitle: labels.webVisualContinueDescription,
          icon: Icons.chrome_reader_mode_outlined,
          searchable: false, initialVisible: 4,
          onViewAll: () => widget.onNavigate?.call('library'),
          items: continueEntries,
          emptyMessage: labels.webViewerNoWorks,
        ),
        const SizedBox(height: 20),
      ],
      WebVisualLibrary(
        key: const Key('web-home-cover-grid'),
        store: widget.store,
        title: labels.webVisualRecent,
        subtitle: labels.webVisualRecentDescription,
        icon: Icons.library_books_rounded,
        searchable: false, initialVisible: 8,
        onViewAll: () => widget.onNavigate?.call('library'),
        items: entries,
        emptyMessage: labels.webViewerNoWorks,
      ),
      const SizedBox(height: 20),
      HypSectionTitle(
        icon: Icons.public_rounded,
        title: labels.webViewerSites,
        subtitle: labels.webVisualLibraryDescription,
        actionLabel: labels.webVisualViewAll,
        onAction: () => widget.onNavigate?.call('web'),
      ),
      const SizedBox(height: 10),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final site in widget.store.sites.take(6))
              ActionChip(
                avatar: const Icon(Icons.public, size: 17),
                label: Text(site.name),
                onPressed: () => _openSite(site.url),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 17),
              label: Text(labels.webViewerAddSite),
              onPressed: _addSite,
            ),
          ]),
          const SizedBox(height: 8),
          Text(labels.webVisualDownloadsDescription,
            style: Theme.of(context).textTheme.bodySmall),
          TextButton.icon(
            onPressed: () => widget.onNavigate?.call('downloads'),
            icon: const Icon(Icons.download_outlined),
            label: Text(labels.webViewerDownloads),
          ),
        ],
      )),
    ]);
  }

  Widget _downloads(AppLocalizations labels) {
    final webJobs = widget.store.pending
        .where((id) => !widget.store.isSeriesDownload(id)).toList();
    final webErrors = widget.store.errors.entries
        .where((entry) => !widget.store.isSeriesFailure(entry.key)).toList();
    final active = widget.store.activeId;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HypSectionTitle(
        icon: Icons.download_rounded,
        title: labels.webViewerDownloads,
        subtitle: labels.webVisualDownloadsDescription,
      ),
      const SizedBox(height: 12),
      if (webJobs.isEmpty && webErrors.isEmpty)
        Text(labels.webViewerEmptyDownloads),
      for (final id in webJobs)
        Card(child: ListTile(
          leading: const Icon(Icons.download),
          title: Text(widget.store.captures[id]?.title ?? id),
          subtitle: LinearProgressIndicator(
            value: widget.store.captures[id]?.images.isNotEmpty == true
                ? (widget.store.progress[id] ?? 0) /
                  widget.store.captures[id]!.images.length : 0.0,
          ),
          trailing: id == active
              ? IconButton(
                  tooltip: widget.store.paused
                      ? labels.webViewerResume : labels.webViewerPause,
                  onPressed: widget.store.togglePause,
                  icon: Icon(widget.store.paused
                    ? Icons.play_arrow : Icons.pause),
                ) : null,
        )),
      if (active != null && !widget.store.isSeriesDownload(active))
        OutlinedButton.icon(
          onPressed: widget.store.cancelCurrent,
          icon: const Icon(Icons.cancel_outlined),
          label: Text(labels.webViewerCancel),
        ),
      if (webErrors.isNotEmpty)
        Align(alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              for (final entry in webErrors) {
                widget.store.clearFailedDownload(entry.key);
              }
            },
            icon: const Icon(Icons.delete_sweep),
            label: Text(labels.webViewerClearFailed),
          ),
        ),
      for (final error in webErrors)
        Card(child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(widget.store.failureTitles[error.key] ?? error.key),
          subtitle: Text(error.value, maxLines: 2,
            overflow: TextOverflow.ellipsis),
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
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
    ]);
  }

  Widget _settings(AppLocalizations labels) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HypSectionTitle(icon: Icons.settings_rounded,
        title: labels.webViewerSettings,
        subtitle: labels.webViewerSettingsInfo),
      const SizedBox(height: 12),
      HypPanel(child: Material(
        type: MaterialType.transparency,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        ],
      ))),
      if (Platform.isAndroid) ...[
        const SizedBox(height: 14),
        UpdateApkCleanupPanel(downloadInProgress: widget.updating),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    if (!widget.store.isReady) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.section.startsWith('series_')) {
      return SeriesViewerPages(
        store: widget.store,
        section: widget.section,
        onOpenSeries: (group) { _openSeries(group); },
        onReadWork: (work) { _openWork(work); },
        onOpenSeriesSource: (url) { _openSite(url, scanSeries: true); },
        onOpenEpisodeSource: (url) { _openSite(url); },
        onError: _error,
        heroCovers: _heroCovers,
        onNavigate: widget.onNavigate,
        updating: widget.updating,
      );
    }
    return switch (widget.section) {
      'web' => _sites(labels),
      'library' => _works(labels),
      'downloads' => _downloads(labels),
      'settings' => _settings(labels),
      _ => _home(labels),
    };
  }
}

/// User-controlled generic WebView, independent of Hitomi's origin restrictions.
/// Images are inspected only after an explicit button press.
class WebViewerBrowser extends StatefulWidget {
  final WebViewerStore store;
  final String initialUrl;
  final bool autoScanSeries;
  const WebViewerBrowser({super.key, required this.store,
      required this.initialUrl, this.autoScanSeries = false});
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
  WebSeriesRecord? _seriesRecord;
  String? _batchSeriesUrl;
  bool _batchRunning = false;
  bool _batchProcessing = false;
  bool _autoScanAttempted = false;

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
    _batchRunning = false;
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
    if (rawUrl == null ||
        WebViewerStore.safeHistoryUrl(rawUrl) == null) return;
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
    final selected = await WebVisitHistorySheet.open(context, widget.store);
    if (selected == null || !mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => WebViewerBrowser(
        store: widget.store, initialUrl: selected)),
    );
  }

  Future<void> _scanSeries() async {
    final web = _web;
    if (!_loaded || web == null || _busy || _batchRunning) return;
    final labels = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final raw = await web.evaluateJavascript(
        source: WebSeriesCapture.captureJavaScript);
      final snapshot = WebSeriesCapture.parse(raw);
      if (snapshot == null) throw FormatException(labels.webSeriesNoSeries);
      final newCount = await widget.store.saveSeries(snapshot);
      final group = widget.store.getSeries(snapshot.url.toString());
      if (group == null) throw StateError(labels.webSeriesNoSeries);
      if (!mounted) return;
      setState(() {
        _seriesRecord = group;
        _capture = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(labels.webSeriesNewCount + ': ' + newCount.toString()),
      ));
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _queueSeries(List<String> selectedUrls) async {
    final group = _seriesRecord;
    if (group == null) return;
    await widget.store.queueSeriesEpisodes(group.url, selectedUrls);
    if (!mounted) return;
    await _resumeSeries(group.url);
  }

  Future<void> _resumeSeries(String url) async {
    final labels = AppLocalizations.of(context)!;
    final group = widget.store.getSeries(url);
    if (widget.store.nextSeriesEpisode(url) == null) {
      _error(labels.webSeriesNoQueued);
      return;
    }
    setState(() {
      _seriesRecord = null;
      _capture = null;
      _batchSeriesUrl = group!.url;
      _batchRunning = true;
      _batchProcessing = false;
    });
    await _advanceSeries();
  }

  Future<void> _advanceSeries() async {
    if (!mounted || !_batchRunning) return;
    final web = _web, url = _batchSeriesUrl;
    if (web == null || url == null) return;
    final episode = widget.store.nextSeriesEpisode(url);
    if (episode == null) {
      setState(() {
        _batchRunning = false;
        _batchSeriesUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.webSeriesCompleted),
      ));
      return;
    }
    final target = WebViewerStore.safeUrl(episode.url);
    if (target == null) {
      await widget.store.markEpisodeNeedsAttention(
          url, episode.url, 'Invalid public HTTPS episode URL');
      await _advanceSeries();
      return;
    }
    try {
      await web.loadUrl(urlRequest: URLRequest(url: WebUri(target.toString())));
    } catch (error) {
      await widget.store.markEpisodeNeedsAttention(
          url, episode.url, error.toString());
      if (mounted) setState(() => _batchRunning = false);
    }
  }

  Future<void> _onSeriesPageLoad(
      InAppWebViewController controller, String? url) async {
    final seriesUrl = _batchSeriesUrl;
    if (!_batchRunning || _batchProcessing ||
        seriesUrl == null || url == null || !mounted) return;
    final episode = widget.store.nextSeriesEpisode(seriesUrl);
    if (episode == null) return;
    final loaded = Uri.tryParse(url);
    final expected = Uri.tryParse(episode.url);
    if (loaded == null || expected == null ||
        loaded.replace(fragment: '').toString() !=
          expected.replace(fragment: '').toString()) return;
    _batchProcessing = true;
    final labels = AppLocalizations.of(context)!;
    try {
      // Allow site scripts and ordinary lazy image paint to settle.
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!_batchRunning || !mounted) return;
      final raw = await controller.evaluateJavascript(
          source: WebPageCapture.captureJavaScript);
      final capture = WebPageCapture.parse(raw);
      if (capture == null || capture.images.isEmpty ||
          capture.expectedImages > capture.images.length) {
        await widget.store.markEpisodeNeedsAttention(
            seriesUrl, episode.url, labels.webSeriesPageIncomplete);
        if (mounted) {
          setState(() => _batchRunning = false);
          _error(labels.webSeriesPageIncomplete);
        }
        return;
      }
      // Preserve the unique, verified episode identity instead of a
      // possibly series-level canonical URL.
      final verified = WebPageCapture(
        sourceUrl: expected, title: episode.title,
        author: capture.author, publishedAt: episode.date,
        expectedImages: capture.expectedImages, images: capture.images,
      );
      final id = await widget.store.enqueue(verified,
          List.generate(verified.images.length, (i) => i),
          title: episode.title, seriesUrl: seriesUrl,
          episodeUrl: episode.url);
      // Only one active chapter at a time; success means CBZ validated.
      await widget.store.waitForSeriesJob(id);
    } catch (error) {
      await widget.store.markEpisodeNeedsAttention(
          seriesUrl, episode.url, error.toString());
    } finally {
      _batchProcessing = false;
    }
    if (_batchRunning && mounted) await _advanceSeries();
  }

  void _stopSeries() {
    setState(() {
      _batchRunning = false;
      _batchSeriesUrl = null;
    });
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
      if (_batchRunning) {
        unawaited(_onSeriesPageLoad(controller, url?.toString()));
      } else if (widget.autoScanSeries && !_autoScanAttempted) {
        _autoScanAttempted = true;
        unawaited(_scanSeries());
      }
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
    final compact = MediaQuery.sizeOf(context).width < 560;
    return Scaffold(
      appBar: AppBar(title: Text(_currentUrl,
          maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!compact) ...[
            IconButton(onPressed: () async => _web?.goBack(),
              icon: const Icon(Icons.arrow_back), tooltip: labels.webViewerBack),
            IconButton(onPressed: () => _web?.reload(),
              icon: const Icon(Icons.refresh), tooltip: labels.webViewerRefresh),
          ],
          IconButton(
            onPressed: _busy || !_loaded ? null : _saveCurrentTab,
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: labels.webViewerSaveCurrentTab),
          IconButton(
            onPressed: _openRecentTabs,
            icon: const Icon(Icons.history),
            tooltip: labels.webViewerRecentTabs),
          IconButton(
            onPressed: _busy || !_loaded || _batchRunning ? null : _captureImages,
            icon: const Icon(Icons.image_search),
            tooltip: labels.webViewerDetect),
          IconButton(
            onPressed: _busy || !_loaded || _batchRunning ? null : _scanSeries,
            icon: const Icon(Icons.format_list_numbered),
            tooltip: labels.webSeriesCapture),
          if (_batchRunning) IconButton(
            onPressed: _stopSeries,
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: labels.webSeriesPause),
        ],
      ),
      body: Column(children: [
        if (compact) SizedBox(height: 48, child: Row(children: [
          IconButton(onPressed: () async => _web?.goBack(),
            icon: const Icon(Icons.arrow_back), tooltip: labels.webViewerBack),
          IconButton(onPressed: () async => _web?.goForward(),
            icon: const Icon(Icons.arrow_forward)),
          IconButton(onPressed: () => _web?.reload(),
            icon: const Icon(Icons.refresh), tooltip: labels.webViewerRefresh),
          Expanded(child: Text(_currentUrl, maxLines: 1,
              overflow: TextOverflow.ellipsis)),
        ])),
        Expanded(child: Stack(children: [
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
        if (_seriesRecord != null)
          Positioned.fill(child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: WebSeriesSelector(
              key: ValueKey(_seriesRecord!.url),
              series: _seriesRecord!,
              selectUnsavedByDefault: widget.store.seriesSelectUnsaved,
              onQueue: _queueSeries,
              onResume: () => _resumeSeries(_seriesRecord!.url),
              onClose: () => setState(() => _seriesRecord = null),
            ),
          )),
      ])),
      ]),
    );
  }
}
