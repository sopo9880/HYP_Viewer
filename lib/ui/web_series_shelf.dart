import 'package:flutter/material.dart';

import '../core/web_series_library.dart';
import '../l10n/app_localizations.dart';

/// A series is one WEB library card; individual chapters remain separate CBZs.
class WebSeriesShelf extends StatelessWidget {
  final WebSeriesRecord series;
  final bool hideCompleted;
  final void Function(WebSeriesEpisodeRecord) onOpenEpisode;
  final VoidCallback onRefreshSource;
  final void Function(WebSeriesEpisodeRecord)? onOpenEpisodeSource;
  final void Function(WebSeriesEpisodeRecord)? onDeleteEpisode;

  const WebSeriesShelf({
    super.key, required this.series, required this.onOpenEpisode,
    required this.onRefreshSource, this.onOpenEpisodeSource,
    this.onDeleteEpisode, this.hideCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    final visibleEpisodes = hideCompleted
        ? series.episodes.where((chapter) => chapter.state != 'saved').toList()
        : series.episodes;
    return Scaffold(
      appBar: AppBar(title: Text(series.title)),
      body: ListView.builder(
        itemCount: visibleEpisodes.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(series.title,
                    style: Theme.of(context).textTheme.titleLarge),
                  if (series.author.isNotEmpty)
                    Text(series.author),
                  const SizedBox(height: 8),
                  Text(labels.webSeriesSaved + ': ' +
                    series.completed.toString() + ' / ' +
                    series.episodes.length.toString()),
                  Text(labels.webSeriesQueued + ': ' +
                    series.queued.toString() + ' · ' +
                    labels.webSeriesFailed + ': ' +
                    series.failures.toString()),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onRefreshSource,
                    icon: const Icon(Icons.sync),
                    label: Text(labels.webSeriesCheckUpdates),
                  ),
                  const Divider(),
                ],
              ),
            );
          }
          final episode = visibleEpisodes[i - 1];
          final done = episode.state == 'saved' && episode.workId != null;
          final status = switch (episode.state) {
            'saved' => labels.webSeriesSaved,
            'queued' || 'downloading' => labels.webSeriesQueued,
            'failed' || 'needs_browser' => labels.webSeriesFailed,
            _ => labels.webSeriesAvailable,
          };
          return ListTile(
            leading: Icon(done
                ? Icons.check_circle_outline : Icons.menu_book_outlined),
            title: Text(episode.title, maxLines: 2,
              overflow: TextOverflow.ellipsis),
            subtitle: Text([episode.date, status].where(
              (s) => s.isNotEmpty).join(' · ')),
            onTap: () => onOpenEpisode(episode),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(done ? Icons.chrome_reader_mode_outlined
                : Icons.open_in_browser),
              if (onDeleteEpisode != null || onOpenEpisodeSource != null)
                PopupMenuButton<String>(
                  tooltip: '회차 관리',
                  onSelected: (action) {
                    if (action == 'web') onOpenEpisodeSource?.call(episode);
                    if (action == 'delete') onDeleteEpisode?.call(episode);
                  },
                  itemBuilder: (_) => [
                    if (onOpenEpisodeSource != null)
                      const PopupMenuItem(value: 'web',
                        child: Text('웹으로 열기')),
                    if (onDeleteEpisode != null)
                      const PopupMenuItem(value: 'delete',
                        child: Text('회차 삭제')),
                  ],
                ),
            ]),
          );
        },
      ),
    );
  }
}
