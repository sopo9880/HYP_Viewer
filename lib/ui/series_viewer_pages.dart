import 'package:flutter/material.dart';

import '../core/web_series_library.dart';
import '../core/web_viewer_store.dart';
import '../l10n/app_localizations.dart';

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

  const SeriesViewerPages({
    super.key, required this.store, required this.section,
    required this.onOpenSeries, required this.onReadWork,
    required this.onOpenSeriesSource, required this.onOpenEpisodeSource,
    required this.onError,
  });

  Widget _heading(BuildContext context, String label) =>
    Text(label, style: Theme.of(context).textTheme.titleLarge);

  Widget _seriesTile(WebSeriesRecord group, AppLocalizations l) =>
    Card(child: ListTile(
      leading: const Icon(Icons.collections_bookmark_outlined, size: 30),
      title: Text(group.title, maxLines: 2,
        overflow: TextOverflow.ellipsis),
      subtitle: Text(l.webSeriesStoredCount + ': ' +
        group.completed.toString() + '/' +
        group.episodes.length.toString() + ' · ' +
        l.webSeriesQueued + ': ' + group.queued.toString()),
      onTap: () => onOpenSeries(group),
      trailing: IconButton(
        tooltip: l.webSeriesCheckUpdates,
        icon: const Icon(Icons.sync),
        onPressed: () => onOpenSeriesSource(group.url),
      ),
    ));

  Widget _home(BuildContext context, AppLocalizations l) {
    final groups = [...store.series]
      ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
    final works = store.works.where((w) => w.seriesUrl != null).toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    final chapters = groups.fold<int>(0, (sum, group) => sum + group.completed);
    final queued = groups.fold<int>(0, (sum, group) => sum + group.queued);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(context, l.seriesViewerHome),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Chip(avatar: const Icon(Icons.library_books_outlined, size: 18),
          label: Text(l.seriesViewerCount + ': ' + groups.length.toString())),
        Chip(avatar: const Icon(Icons.check_circle_outline, size: 18),
          label: Text(l.webSeriesSaved + ': ' + chapters.toString())),
        Chip(avatar: const Icon(Icons.download_outlined, size: 18),
          label: Text(l.webSeriesQueued + ': ' + queued.toString())),
      ]),
      const SizedBox(height: 14),
      if (works.isNotEmpty) ...[
        Text(l.seriesViewerContinueReading,
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Card(child: ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(works.first.title, maxLines: 2,
            overflow: TextOverflow.ellipsis),
          subtitle: Text(works.first.currentPage.toString() + ' / ' +
            works.first.pages.toString()),
          trailing: const Icon(Icons.play_arrow),
          onTap: () => onReadWork(works.first),
        )),
        const SizedBox(height: 12),
      ],
      Text(l.seriesViewerRecentlyAdded,
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (groups.isEmpty) Text(l.seriesViewerNoWorks),
      for (final group in groups.take(6)) _seriesTile(group, l),
    ]);
  }

  Widget _library(BuildContext context, AppLocalizations l) {
    final groups = [...store.series]
      ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(context, l.seriesViewerLibrary),
      const SizedBox(height: 8),
      Text(l.seriesViewerCount + ': ' + groups.length.toString(),
        style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      if (groups.isEmpty) Text(l.seriesViewerNoWorks),
      for (final group in groups) _seriesTile(group, l),
    ]);
  }

  Widget _downloads(BuildContext context, AppLocalizations l) {
    final groups = store.series.where((s) =>
      s.queued > 0 || s.failures > 0 ||
      s.episodes.any((e) => e.state == 'downloading')).toList();
    final active = store.activeId;
    final jobs = store.pending.where(store.isSeriesDownload).toList();
    final errors = store.errors.entries
      .where((entry) => store.isSeriesFailure(entry.key)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(context, l.seriesViewerDownloads),
      const SizedBox(height: 12),
      if (groups.isEmpty && jobs.isEmpty && errors.isEmpty)
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
    ]);
  }

  Widget _settings(BuildContext context, AppLocalizations l) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading(context, l.seriesViewerSettings),
      const SizedBox(height: 12),
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
