import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/web_series_library.dart';
import '../core/web_viewer_store.dart';
import '../l10n/app_localizations.dart';
import 'hero_banner.dart';
import 'hyp_theme.dart';
import 'web_library_visuals.dart';

/// Four dedicated SERIES screens backed by the same WEB store and CBZs.
/// The wrapper dashboard owns the store, so mode changes never copy data.
class SeriesViewerPages extends StatelessWidget {
  final WebViewerStore store;
  final String section;
  final void Function(WebSeriesRecord) onOpenSeries;
  final void Function(WebSavedWork) onReadWork;
  final void Function(String) onOpenSeriesSource;
  final void Function(String) onOpenEpisodeSource;
  final void Function(Object) onError;
  final void Function(WebSeriesRecord)? onRenameSeries;
  final void Function(WebSeriesRecord)? onDeleteSeries;
  final void Function(WebSavedWork)? onDeleteChapter;
  final Future<void> Function(List<WebVisualEntry>)? onDeleteSelectedSeries;
  final Future<void> Function(List<WebVisualEntry>)? onDeleteSelectedChapters;
  final Map<String, Uint8List?> heroCovers;
  final ValueChanged<String>? onNavigate;
  final bool updating;

  const SeriesViewerPages({
    super.key, required this.store, required this.section,
    required this.onOpenSeries, required this.onReadWork,
    required this.onOpenSeriesSource, required this.onOpenEpisodeSource,
    required this.onError, this.heroCovers = const {}, this.onNavigate,
    this.onRenameSeries, this.onDeleteSeries, this.onDeleteChapter,
    this.onDeleteSelectedSeries, this.onDeleteSelectedChapters,
    this.updating = false,
  });

  List<WebVisualEntry> _seriesEntries(AppLocalizations labels) {
    return store.series.map((group) {
      String? firstSavedId;
      for (final chapter in group.episodes) {
        if (chapter.workId != null && chapter.state == 'saved') {
          firstSavedId = chapter.workId;
          break;
        }
      }
      return WebVisualEntry(
        id: 'series-' + group.url,
        title: group.title,
        subtitle: group.author.isEmpty ? group.url : group.author,
        detail: labels.webSeriesStoredCount + ': ' +
            group.completed.toString() + '/' +
            group.episodes.length.toString() + ' · ' +
            labels.webSeriesQueued + ': ' + group.queued.toString(),
        coverWorkId: firstSavedId,
        remoteCoverUrl: group.coverUrl,
        modifiedAt: group.checkedAt,
        progress: group.episodes.isEmpty
          ? 0.0 : group.completed / group.episodes.length,
        downloaded: group.completed > 0,
        icon: Icons.collections_bookmark_rounded,
        onOpen: () => onOpenSeries(group),
        actions: {
          'open': labels.webViewerRead,
          'source': labels.webSeriesCheckUpdates,
          'rename': labels.webViewerRename,
          'delete': labels.webViewerDelete,
        },
        onAction: (action) {
          if (action == 'open') onOpenSeries(group);
          if (action == 'source') onOpenSeriesSource(group.url);
          if (action == 'rename') onRenameSeries?.call(group);
          if (action == 'delete') onDeleteSeries?.call(group);
        },
      );
    }).toList();
  }

  List<WebVisualEntry> _chapterEntries(AppLocalizations labels) {
    return store.works.where((work) => work.seriesUrl != null).map((work) {
      String parent = work.author;
      for (final group in store.series) {
        if (group.url == work.seriesUrl) {
          parent = group.title;
          break;
        }
      }
      final progress = work.pages <= 1
        ? 0.0 : ((work.currentPage - 1) / (work.pages - 1))
          .clamp(0.0, 1.0).toDouble();
      return WebVisualEntry(
        id: 'chapter-' + work.id,
        title: work.title,
        subtitle: parent,
        detail: work.currentPage.toString() + ' / ' +
          work.pages.toString(),
        coverWorkId: work.id,
        modifiedAt: work.savedAt,
        progress: progress, downloaded: true,
        icon: Icons.menu_book_rounded,
        onOpen: () => onReadWork(work),
        actions: {
          'read': labels.webViewerRead,
          'source': labels.webViewerSource,
          'delete': labels.webViewerDelete,
        },
        onAction: (action) {
          if (action == 'read') onReadWork(work);
          if (action == 'source') onOpenEpisodeSource(work.sourceUrl);
          if (action == 'delete') onDeleteChapter?.call(work);
        },
      );
    }).toList();
  }

  Widget _home(BuildContext context, AppLocalizations labels) {
    final groups = _seriesEntries(labels)
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    final chapters = _chapterEntries(labels)
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    final ids = chapters.take(3).map((e) => e.coverWorkId).toList();
    final art = List<Uint8List?>.generate(3,
      (i) => i < ids.length ? heroCovers[ids[i]] : null);
    final artworkKeys = List<String?>.generate(3,
      (i) => i < ids.length ? ids[i] : null);
    final saved = store.series.fold<int>(
      0, (sum, group) => sum + group.completed);
    final pending = store.series.fold<int>(
      0, (sum, group) => sum + group.queued);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HypHeroBanner(
        viewerLabel: 'SERIES Viewer',
        bannerIcon: Icons.collections_bookmark_rounded,
        slideTitles: [
          labels.seriesVisualHeroTitle1,
          labels.seriesVisualHeroTitle2,
          labels.seriesVisualHeroTitle3,
        ],
        slideDescriptions: [
          labels.seriesVisualHeroDesc1,
          labels.seriesVisualHeroDesc2,
          labels.seriesVisualHeroDesc3,
        ],
        rotatingArtworks: art,
        rotatingArtworkKeys: artworkKeys,
        onOpenArtwork: (id) {
          for (final work in store.works) {
            if (work.id == id) { onReadWork(work); break; }
          }
        },
        onOpenLibrary: () => onNavigate?.call('library'),
        onOpenDownloads: () => onNavigate?.call('downloads'),
      ),
      const SizedBox(height: 15),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Chip(label: Text(labels.seriesViewerCount + ': ' +
          groups.length.toString())),
        Chip(label: Text(labels.webSeriesSaved + ': ' + saved.toString())),
        Chip(label: Text(labels.webSeriesQueued + ': ' + pending.toString())),
      ]),
      const SizedBox(height: 19),
      if (chapters.isNotEmpty) ...[
        WebVisualLibrary(
          key: const Key('series-continue-cover-grid'),
          store: store,
          title: labels.seriesViewerContinueReading,
          subtitle: labels.seriesVisualContinueDescription,
          icon: Icons.menu_book_rounded,
          searchable: false, initialVisible: 4,
          onViewAll: () => onNavigate?.call('library'),
          items: chapters,
          emptyMessage: labels.seriesViewerNoWorks,
        ),
        const SizedBox(height: 19),
      ],
      WebVisualLibrary(
        key: const Key('series-home-cover-grid'),
        store: store,
        title: labels.seriesVisualRecent,
        subtitle: labels.seriesVisualLibraryDescription,
        icon: Icons.collections_bookmark_rounded,
        searchable: false, initialVisible: 8,
        onViewAll: () => onNavigate?.call('library'),
        items: groups,
        emptyMessage: labels.seriesViewerNoWorks,
      ),
    ]);
  }

  Widget _library(BuildContext context, AppLocalizations labels) =>
    WebVisualLibrary(
      key: const Key('series-full-cover-library'),
      store: store,
      title: labels.seriesViewerLibrary,
      subtitle: labels.seriesVisualLibraryDescription,
      icon: Icons.collections_bookmark_rounded,
      items: _seriesEntries(labels),
      onDeleteSelected: onDeleteSelectedSeries,
      emptyMessage: labels.seriesViewerNoWorks,
    );

  Widget _downloads(BuildContext context, AppLocalizations l) {
    final groups = store.series.where((s) =>
      s.queued > 0 || s.failures > 0 ||
      s.episodes.any((e) => e.state == 'downloading')).toList();
    final active = store.activeId;
    final jobs = store.pending.where(store.isSeriesDownload).toList();
    final errors = store.errors.entries
      .where((entry) => store.isSeriesFailure(entry.key)).toList();
    final downloadedChapters = _chapterEntries(l);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HypSectionTitle(icon: Icons.download_rounded,
        title: l.seriesViewerDownloads,
        subtitle: l.webVisualDownloadsDescription),
      const SizedBox(height: 12),
      // When the download shelf is empty it already shows this message.
      // Avoid two identical placeholders for a completely empty library.
      if (groups.isEmpty && jobs.isEmpty && errors.isEmpty &&
          downloadedChapters.isNotEmpty)
        Text(l.seriesViewerNoDownloads),
      for (final group in groups)
        Card(child: ListTile(
          leading: const Icon(Icons.dynamic_feed_outlined),
          title: Text(group.title, maxLines: 2,
            overflow: TextOverflow.ellipsis),
          subtitle: Text(l.webSeriesQueued + ': ' +
            group.queued.toString() + ' · ' + l.webSeriesSaved + ': ' +
            group.completed.toString() + ' · ' + l.webSeriesFailed + ': ' +
            group.failures.toString()),
          onTap: () => onOpenSeries(group),
          trailing: IconButton(
            tooltip: l.webSeriesResume,
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => onOpenSeriesSource(group.url),
          ),
        )),
      if (jobs.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(l.seriesViewerActiveChapter,
          style: Theme.of(context).textTheme.titleMedium),
      ],
      for (final id in jobs)
        Card(child: ListTile(
          title: Text(store.captures[id]?.title ?? id,
            maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: LinearProgressIndicator(
            value: store.captures[id]?.images.isNotEmpty == true
              ? (store.progress[id] ?? 0) /
                store.captures[id]!.images.length : 0.0,
          ),
          trailing: id == active
            ? IconButton(
                tooltip: store.paused
                  ? l.webViewerResume : l.webViewerPause,
                onPressed: store.togglePause,
                icon: Icon(store.paused ? Icons.play_arrow : Icons.pause))
            : const Icon(Icons.hourglass_bottom),
        )),
      if (active != null && store.isSeriesDownload(active))
        OutlinedButton.icon(
          onPressed: store.cancelCurrent,
          icon: const Icon(Icons.cancel_outlined),
          label: Text(l.webViewerCancel),
        ),
      if (errors.isNotEmpty)
        Align(alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              for (final error in errors) {
                store.clearFailedDownload(error.key);
              }
            },
            icon: const Icon(Icons.delete_sweep),
            label: Text(l.webViewerClearFailed),
          ),
        ),
      for (final error in errors)
        Card(child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(store.failureTitles[error.key] ?? error.key),
          subtitle: Text(error.value, maxLines: 2,
            overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: l.webViewerClearError,
            icon: const Icon(Icons.close),
            onPressed: () => store.clearFailedDownload(error.key),
          ),
        )),
      for (final group in groups)
        for (final chapter in group.episodes.where((e) =>
            e.state == 'failed' || e.state == 'needs_browser'))
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(chapter.title, maxLines: 1,
              overflow: TextOverflow.ellipsis),
            subtitle: Text(chapter.error ?? l.webSeriesFailed,
              maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: l.seriesViewerOpenSource,
              icon: const Icon(Icons.open_in_browser),
              onPressed: () => onOpenEpisodeSource(chapter.url),
            ),
          ),
      const SizedBox(height: 15),
      WebVisualLibrary(
        key: const Key('series-downloaded-cover-grid'),
        store: store,
        title: l.seriesDownloadedChapters,
        subtitle: l.webVisualDownloadsDescription,
        icon: Icons.library_books_rounded,
        items: downloadedChapters,
        onDeleteSelected: onDeleteSelectedChapters,
        emptyMessage: l.seriesViewerNoDownloads,
      ),
    ]);
  }

  Widget _settings(BuildContext context, AppLocalizations l) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HypSectionTitle(
        icon: Icons.settings_rounded,
        title: l.seriesViewerSettings,
        subtitle: l.seriesViewerInfo),
      const SizedBox(height: 12),
      HypPanel(child: Material(
        type: MaterialType.transparency,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
      SwitchListTile(
        value: store.seriesOldestFirst,
        title: Text(l.seriesViewerOldestFirst),
        subtitle: Text(l.seriesViewerOldestFirstHelp),
        onChanged: (value) async {
          try { await store.setSeriesOldestFirst(value); }
          catch (error) { onError(error); }
        },
      ),
      SwitchListTile(
        value: store.seriesSelectUnsaved,
        title: Text(l.seriesViewerSelectUnsaved),
        subtitle: Text(l.seriesViewerSelectUnsavedHelp),
        onChanged: (value) async {
          try { await store.setSeriesSelectUnsaved(value); }
          catch (error) { onError(error); }
        },
      ),
      SwitchListTile(
        value: store.seriesHideCompleted,
        title: Text(l.seriesViewerHideCompleted),
        subtitle: Text(l.seriesViewerHideCompletedHelp),
        onChanged: (value) async {
          try { await store.setSeriesHideCompleted(value); }
          catch (error) { onError(error); }
        },
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(l.seriesViewerInfo),
      ),
      ]))),
    ]);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return switch (section) {
      'series_library' => _library(context, l),
      'series_downloads' => _downloads(context, l),
      'series_settings' => _settings(context, l),
      _ => _home(context, l),
    };
  }
}
