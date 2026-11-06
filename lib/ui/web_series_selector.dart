import 'package:flutter/material.dart';

import '../core/web_series_library.dart';
import '../l10n/app_localizations.dart';

/// Explicit selection before any multi-episode request. All referenced
/// pages originate from the user-opened series detail DOM.
class WebSeriesSelector extends StatefulWidget {
  final WebSeriesRecord series;
  final bool selectUnsavedByDefault;
  final Future<void> Function(List<String>) onQueue;
  final VoidCallback onResume;
  final VoidCallback onClose;

  const WebSeriesSelector({
    super.key, required this.series, required this.onQueue,
    required this.onResume, required this.onClose,
    this.selectUnsavedByDefault = true,
  });

  @override
  State<WebSeriesSelector> createState() => _WebSeriesSelectorState();
}

class _WebSeriesSelectorState extends State<WebSeriesSelector> {
  final selected = <String>{};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectUnsavedByDefault) {
      selected.addAll(widget.series.episodes.where((episode) =>
          episode.state != 'saved' && episode.state != 'downloading' &&
          episode.state != 'queued').map((episode) => episode.url));
    }
  }

  void _selectMissing() {
    setState(() {
      selected
        ..clear()
        ..addAll(widget.series.episodes.where((e) =>
            e.state != 'saved' && e.state != 'downloading' &&
            e.state != 'queued').map((e) => e.url));
    });
  }

  Future<void> _selectRange() async {
    final labels = AppLocalizations.of(context)!;
    final first = TextEditingController();
    final last = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.webSeriesRange),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: first, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: labels.webSeriesStartNumber)),
          TextField(controller: last, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: labels.webSeriesEndNumber)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(labels.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(labels.webViewerSave)),
        ],
      ),
    );
    final a = int.tryParse(first.text);
    final b = int.tryParse(last.text);
    first.dispose();
    last.dispose();
    if (accepted != true || a == null || b == null || a > b || !mounted) return;
    setState(() {
      selected
        ..clear()
        ..addAll(widget.series.episodes.where((e) =>
          e.number != null && e.number! >= a && e.number! <= b &&
          e.state != 'saved' && e.state != 'downloading' &&
          e.state != 'queued').map((e) => e.url));
    });
  }

  Future<void> _queue() async {
    if (busy || selected.isEmpty) return;
    setState(() => busy = true);
    try {
      await widget.onQueue(selected.toList());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    final series = widget.series;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
        child: Row(children: [
          IconButton(onPressed: widget.onClose,
            icon: const Icon(Icons.arrow_back),
            tooltip: labels.webSeriesBack),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(series.title, maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium),
              Text(labels.webSeriesSaved + ': ' +
                  series.completed.toString() + ' / ' +
                  series.episodes.length.toString(),
                style: Theme.of(context).textTheme.bodySmall),
            ],
          )),
        ]),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 6, runSpacing: 4, children: [
          OutlinedButton(onPressed: () => setState(() {
            selected
              ..clear()
              ..addAll(series.episodes.where((e) =>
                e.state != 'saved' && e.state != 'downloading' &&
                e.state != 'queued').map((e) => e.url));
          }), child: Text(labels.webSeriesAll)),
          OutlinedButton(onPressed: _selectMissing,
            child: Text(labels.webSeriesNew)),
          OutlinedButton(onPressed: _selectRange,
            child: Text(labels.webSeriesRange)),
          TextButton(onPressed: () => setState(selected.clear),
            child: Text(labels.webViewerDeselectAll)),
        ]),
      ),
      if (series.queued > 0)
        ListTile(
          title: Text(labels.webSeriesQueued + ': ' +
            series.queued.toString()),
          trailing: OutlinedButton.icon(
            onPressed: widget.onResume,
            icon: const Icon(Icons.play_arrow),
            label: Text(labels.webSeriesResume),
          ),
        ),
      const Divider(height: 8),
      Expanded(child: ListView.builder(
        itemCount: series.episodes.length,
        itemBuilder: (_, index) {
          final episode = series.episodes[index];
          final locked = episode.state == 'saved' ||
              episode.state == 'queued' || episode.state == 'downloading';
          final status = switch (episode.state) {
            'saved' => labels.webSeriesSaved,
            'queued' || 'downloading' => labels.webSeriesQueued,
            'failed' || 'needs_browser' => labels.webSeriesFailed,
            _ => labels.webSeriesAvailable,
          };
          return CheckboxListTile(
            dense: true,
            value: episode.state == 'saved' ? true :
              episode.state == 'queued' || episode.state == 'downloading'
                ? true : selected.contains(episode.url),
            onChanged: locked ? null : (value) => setState(() {
              if (value == true) { selected.add(episode.url); }
              else { selected.remove(episode.url); }
            }),
            title: Text(episode.title, maxLines: 2,
              overflow: TextOverflow.ellipsis),
            subtitle: Text([
              if (episode.date.isNotEmpty) episode.date,
              status,
            ].join(' · ')),
            secondary: episode.state == 'saved'
              ? const Icon(Icons.check_circle_outline)
              : const Icon(Icons.description_outlined),
          );
        },
      )),
      SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy || selected.isEmpty ? null : _queue,
            icon: busy ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download),
            label: Text(labels.webSeriesStart + ' (' +
              selected.length.toString() + ')'),
          ),
        ),
      )),
    ]);
  }
}
