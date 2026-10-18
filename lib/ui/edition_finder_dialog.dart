import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/cover_similarity.dart';
import '../core/hitomi_gallery.dart';
import '../core/online_search.dart';
import '../core/title_alias_index.dart';
import '../core/work.dart';
import '../core/work_editions.dart';
import '../core/work_grouping.dart';
import '../l10n/app_localizations.dart';
import 'hyp_animated_title.dart';

typedef EditionPageLookup = Future<OnlineSearchResult> Function(
    String query, int page);

/// Opens immediately, streams page results, and disposes network clients when
/// Back/Cancel closes the popup. Nothing is saved until the user confirms.
class EditionFinderDialog extends StatefulWidget {
  final WorkEntry anchor;
  final List<WorkEntry> library;
  final Map<String, Uint8List> coverImages;
  final Future<void> Function(
      List<String> localIds, List<OnlineSearchWork> remoteWorks) onLinkSelected;
  final EditionPageLookup? searchPage;

  const EditionFinderDialog({
    super.key,
    required this.anchor,
    required this.library,
    required this.coverImages,
    required this.onLinkSelected,
    this.searchPage,
  });

  @override
  State<EditionFinderDialog> createState() => _EditionFinderDialogState();
}

class _EditionCandidate {
  final String id;
  final String title;
  final String language;
  final WorkEntry? local;
  final OnlineSearchWork? remote;
  final EditionMatch match;

  const _EditionCandidate(this.id, this.title, this.language, this.match,
      {this.local, this.remote});
}

class _EditionFinderDialogState extends State<EditionFinderDialog> {
  late final TextEditingController _query;
  late http.Client _searchClient;
  late http.Client _coverClient;
  final Map<String, _EditionCandidate> _candidates = {};
  final Map<String, double> _coverScores = {};
  final Set<String> _selected = {};
  final List<String> _warnings = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _generation = 0;
  int _completed = 0;
  int _total = 0;
  int _remoteCoverChecks = 0;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(
        text: WorkEditions.originalTitle(widget.anchor.title));
    _searchClient = http.Client();
    _coverClient = http.Client();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _beginSearch();
    });
  }

  @override
  void dispose() {
    _generation++;
    _searchClient.close();
    _coverClient.close();
    _query.dispose();
    super.dispose();
  }

  bool _validCandidate(WorkEntry candidate) {
    if (candidate.workId == widget.anchor.workId) return false;
    final left = WorkGrouping.episodeNumber(widget.anchor);
    final right = WorkGrouping.episodeNumber(candidate);
    if (left != null && right != null && left != right) return false;
    if (candidate.sourceLanguage.isNotEmpty &&
        widget.anchor.sourceLanguage.isNotEmpty &&
        WorkEditions.canonicalLanguage(candidate.sourceLanguage) ==
            WorkEditions.canonicalLanguage(widget.anchor.sourceLanguage)) {
      return false;
    }
    return true;
  }

  void _beginSearch() {
    if (_saving) return;
    _searchClient.close();
    _coverClient.close();
    _searchClient = http.Client();
    _coverClient = http.Client();
    final epoch = ++_generation;
    final input = _query.text.trim();
    _candidates.clear();
    _selected.clear();
    _coverScores.clear();
    _warnings.clear();
    _remoteCoverChecks = 0;
    _completed = 0;
    _total = 0;
    _error = null;

    for (final entry in widget.library) {
      if (!_validCandidate(entry)) continue;
      final match = WorkEditions.compare(widget.anchor, entry);
      if (match.score < 45 &&
          !entry.title.toLowerCase().contains(input.toLowerCase())) continue;
      final candidate = _EditionCandidate(entry.workId, entry.title,
          entry.sourceLanguage, match, local: entry);
      _candidates[entry.workId] = candidate;
      unawaited(_compareCover(candidate, epoch));
    }
    setState(() => _loading = input.isNotEmpty);
    if (input.isNotEmpty) unawaited(_fetchCandidates(epoch, input));
  }

  Future<void> _compareCover(_EditionCandidate candidate, int epoch) async {
    final known = widget.coverImages[widget.anchor.key];
    if (known == null) return;
    Uint8List? other;
    if (candidate.local != null) {
      other = widget.coverImages[candidate.local!.key];
    } else {
      if (candidate.match.score < 45 || _remoteCoverChecks >= 3) return;
      _remoteCoverChecks++;
      try {
        final gallery = await HitomiGalleryProvider(_coverClient)
            .load(candidate.id, dataSaver: true);
        if (gallery.pageCount > 0) other = await gallery.loadPage(0);
      } catch (_) {
        return; // Unavailable covers are neutral evidence.
      }
    }
    if (other == null || !mounted || epoch != _generation) return;
    try {
      final score = await CoverSimilarity.compare(known, other);
      if (score != null && mounted && epoch == _generation) {
        setState(() => _coverScores[candidate.id] = score);
      }
    } catch (_) {
      // Image codecs may reject a damaged cover without affecting discovery.
    }
  }

  void _receive(List<OnlineSearchWork> works, int epoch, String query) {
    if (!mounted || epoch != _generation) return;
    final additions = <_EditionCandidate>[];
    for (final remote in works) {
      if (_candidates.containsKey(remote.workId)) continue;
      final entry = WorkEntry.create(
        workId: remote.workId, title: remote.title,
        titleAliases: remote.titleAliases,
        author: remote.artists.join(', '),
      ).copyWith(
        sourceLanguage: remote.language,
        sourceSeries: remote.series.join(', '),
        sourceGroup: remote.groups.join(', '),
        sourceDate: remote.date,
      );
      if (!_validCandidate(entry)) continue;
      final match = WorkEditions.compare(widget.anchor, entry);
      if (match.score < 45 &&
          !entry.title.toLowerCase().contains(query.toLowerCase())) continue;
      additions.add(_EditionCandidate(remote.workId, remote.title,
          remote.language, match, remote: remote));
    }
    if (additions.isEmpty) return;
    setState(() {
      for (final item in additions) {
        _candidates.putIfAbsent(item.id, () => item);
      }
    });
    for (final item in additions) {
      unawaited(_compareCover(item, epoch));
    }
  }

  Future<void> _fetchCandidates(int epoch, String input) async {
    final queries = TitleAliasIndex.fromLibrary(widget.library)
        .queriesFor(widget.anchor, entered: input, limit: 14);
    _total = queries.length;
    final search = widget.searchPage ??
        (String term, int page) =>
            OnlineWorkSearch(_searchClient).search(term, page: page);
    for (var offset = 0; offset < queries.length; offset += 2) {
      if (!mounted || epoch != _generation) return;
      await Future.wait(queries.skip(offset).take(2).map((term) async {
        try {
          var page = 1;
          while (page <= 3 && mounted && epoch == _generation) {
            final result = await search(term, page);
            if (!mounted || epoch != _generation) return;
            _receive(result.works, epoch, input);
            if (result.works.isEmpty ||
                result.total <= page * 25 ||
                result.works.length < 25) break;
            page++;
          }
        } catch (error) {
          if (mounted && epoch == _generation) {
            _warnings.add(term + ': ' + error.toString());
          }
        } finally {
          if (mounted && epoch == _generation) {
            setState(() => _completed++);
          }
        }
      }));
    }
    if (mounted && epoch == _generation) {
      setState(() => _loading = false);
    }
  }

  Future<void> _linkSelected() async {
    final picked = _selected.map((id) => _candidates[id])
        .whereType<_EditionCandidate>().toList();
    if (picked.isEmpty || _saving) return;
    final labels = AppLocalizations.of(context)!;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(labels.editionLinkConfirmTitle),
        content: Text(labels.editionConfirmWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: Text(labels.cancel)),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: Text(labels.editionLinkAction)),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onLinkSelected(
        picked.where((item) => item.local != null)
            .map((item) => item.id).toList(),
        picked.map((item) => item.remote)
            .whereType<OnlineSearchWork>().toList(),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = AppLocalizations.of(context)!;
    final items = _candidates.values.toList()
      ..sort((a, b) {
        final ae = WorkEditions.withCoverEvidence(a.match,
            _coverScores[a.id]);
        final be = WorkEditions.withCoverEvidence(b.match,
            _coverScores[b.id]);
        final order = be.score.compareTo(ae.score);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    return AlertDialog(
      title: Text(labels.findOtherEditions),
      content: SizedBox(
        width: 640,
        height: MediaQuery.sizeOf(context).height * 0.57,
        child: Column(children: [
          Row(children: [
            Expanded(child: TextField(
              key: const Key('edition-finder-query'),
              controller: _query,
              enabled: !_saving,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _beginSearch(),
              decoration: InputDecoration(
                labelText: labels.editionSearchLabel,
                helperText: labels.editionSearchHint,
              ),
            )),
            IconButton(
              key: const Key('edition-finder-retry'),
              tooltip: labels.editionFinderRetry,
              onPressed: _saving ? null : _beginSearch,
              icon: const Icon(Icons.search),
            ),
          ]),
          const SizedBox(height: 9),
          if (_loading) ...[
            const LinearProgressIndicator(),
            Text(labels.editionFinderProgress(
                _completed, _total)),
          ],
          if (_warnings.isNotEmpty)
            ExpansionTile(
              title: Text(labels.editionSearchPartial),
              children: [
                for (final message in _warnings.take(8))
                  ListTile(dense: true, title: SelectableText(message)),
              ],
            ),
          if (_error != null)
            Text(labels.editionFinderSaveError(_error!),
                style: const TextStyle(color: Colors.orangeAccent)),
          Expanded(child: items.isEmpty
            ? Center(child: Text(_loading
                ? labels.editionFinderLoading
                : labels.editionNoCandidates))
            : ListView.builder(
                key: const Key('edition-finder-results'),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final evidence = WorkEditions.withCoverEvidence(
                      item.match, _coverScores[item.id]);
                  return CheckboxListTile(
                    key: Key('edition-found-' + item.id),
                    value: _selected.contains(item.id),
                    onChanged: _saving ? null : (value) => setState(() {
                      if (value == true) {
                        _selected.add(item.id);
                      } else {
                        _selected.remove(item.id);
                      }
                    }),
                    title: HypAnimatedTitle(title: item.title),
                    subtitle: Text(
                      '#' + item.id + ' · ' +
                      WorkEditions.languageName(item.language) + ' · ' +
                      (evidence.autoLink ? labels.editionLikelyMatch :
                          labels.editionManualReview) +
                      ' · ' + evidence.score.toString() + '/100' +
                      ' · ' + evidence.reason,
                    ),
                    secondary: Icon(item.local != null
                        ? Icons.bookmark : Icons.cloud_outlined),
                  );
                },
              )),
        ]),
      ),
      actions: [
        TextButton(
          key: const Key('edition-finder-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(labels.cancel),
        ),
        FilledButton(
          key: const Key('edition-finder-link'),
          onPressed: _saving || _selected.isEmpty ? null : _linkSelected,
          child: Text(labels.editionFinderLinkSelected(_selected.length)),
        ),
      ],
    );
  }
}
