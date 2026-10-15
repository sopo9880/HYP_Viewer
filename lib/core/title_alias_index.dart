import 'work.dart';
import 'work_grouping.dart';

/// A deterministic, offline index of original and translated titles.
/// It learns synonyms only from metadata, user-entered aliases and explicitly
/// linked edition groups. It never invents an unverified translation.
class TitleAliasIndex {
  final Map<String, Set<String>> byId;
  const TitleAliasIndex._(this.byId);

  static String normalize(String title) =>
      WorkGrouping.normalizedSeries(title)
          .replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  factory TitleAliasIndex.fromLibrary(Iterable<WorkEntry> works) {
    final records = works.toList();
    final grouped = <String, Set<String>>{};
    for (final work in records) {
      if (work.editionGroupId.isEmpty) continue;
      final aliases = grouped.putIfAbsent(
          work.editionGroupId, () => <String>{});
      aliases.addAll(_titles(work));
    }
    return TitleAliasIndex._({
      for (final work in records)
        work.workId: {
          ..._titles(work),
          if (work.editionGroupId.isNotEmpty)
            ...?grouped[work.editionGroupId],
        },
    });
  }

  static Set<String> _titles(WorkEntry work) => {
    for (final title in [work.title, ...work.titleAliases])
      for (final part in title.split('|'))
        if (part.trim().length >= 2) part.trim(),
  };

  Set<String> aliasesFor(WorkEntry work) =>
      byId[work.workId] ?? _titles(work);

  /// User titles and confirmed synonyms are the first searches. Metadata
  /// fields allow discovery even when differently translated titles have no
  /// shared words. Keep queries bounded for network and server safety.
  List<String> queriesFor(WorkEntry work, {
    String entered = '',
    int limit = 12,
  }) {
    final queries = <String>[];
    void add(String value) {
      final cleaned = value.trim();
      if (cleaned.isNotEmpty && cleaned.length <= 150 &&
          !queries.contains(cleaned)) queries.add(cleaned);
    }
    add(entered);
    for (final alias in aliasesFor(work)) {
      add(alias);
      if (queries.length >= limit - 3) break;
    }
    for (final artist in work.author.split(',')) {
      if (artist.trim().isNotEmpty) add('artist:' + artist.trim());
    }
    for (final group in work.sourceGroup.split(',')) {
      if (group.trim().isNotEmpty) add('group:' + group.trim());
    }
    if (work.sourceSeries.trim().isNotEmpty) {
      add('series:' + work.sourceSeries.trim());
      add(work.sourceSeries.trim());
    }
    return queries.take(limit).toList();
  }

  bool sharesKnownAlias(WorkEntry first, WorkEntry second) {
    final a = aliasesFor(first).map(normalize).where((x) => x.length >= 3)
        .toSet();
    final b = aliasesFor(second).map(normalize).where((x) => x.length >= 3)
        .toSet();
    return a.intersection(b).isNotEmpty;
  }
}
