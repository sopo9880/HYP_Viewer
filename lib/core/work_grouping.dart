import 'work.dart';

class WorkGroupSuggestion {
  final String title;
  final List<String> workIds;
  final String reason;
  const WorkGroupSuggestion(this.title, this.workIds, this.reason);
}

/// Conservative, confirmation-only recommendations for numbered episodes.
/// Works already grouped by a user are NEVER edited or proposed again.
class WorkGrouping {
  static final _episode = RegExp(
      r'(?:^|[\s\-\[_（(])(?:제\s*)?(\d{1,3})\s*(?:편|화|부|권|episode|ep\.?|part)\b',
      caseSensitive: false);
  static final _suffix = RegExp(
      r'(?:\s|[-_])(?:\d{1,3})\s*(?:편|화|부|권)?\s*$',
      caseSensitive: false);

  static int? episodeNumber(WorkEntry w) {
    for (final input in [w.originalComment, w.title]) {
      final match = _episode.firstMatch(input);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    return null;
  }

  static String normalizedSeries(String title) {
    return title.replaceAll(_episode, ' ')
        .replaceAll(_suffix, '').replaceAll(RegExp(r'\s+'), ' ')
        .trim().toLowerCase();
  }

  static List<WorkGroupSuggestion> suggest(List<WorkEntry> works) {
    final ungrouped = works.where((w) => w.groupId.isEmpty).toList();
    final buckets = <String, List<WorkEntry>>{};
    for (final work in ungrouped) {
      final ep = episodeNumber(work);
      if (ep == null) continue;
      final name = normalizedSeries(work.title);
      final id = work.videoId.trim();
      if (id.isEmpty && name.length < 5) continue;
      // A shared Shorts source (with numbered episodes) is stronger
      // evidence than a merely similar artist name.
      final key = id.isNotEmpty ? 'short:$id' : 'title:$name';
      buckets.putIfAbsent(key, () => []).add(work);
    }
    final suggestions = <WorkGroupSuggestion>[];
    for (final group in buckets.values) {
      final episodeNumbers = group.map(episodeNumber).toList();
      if (group.length < 2 ||
          episodeNumbers.any((ep) => ep == null) ||
          episodeNumbers.toSet().length != group.length) continue;
      group.sort((a, b) =>
          episodeNumber(a)!.compareTo(episodeNumber(b)!));
      final longestName = group.map((w) => normalizedSeries(w.title))
          .where((name) => name.length > 3)
          .fold<String>('', (a, name) => name.length > a.length ? name : a);
      suggestions.add(WorkGroupSuggestion(
        longestName.isEmpty ? '작품 시리즈' : longestName,
        group.map((w) => w.workId).toList(),
        group.first.videoId.isNotEmpty
            ? '같은 소개 쇼츠의 서로 다른 회차' : '번호가 다른 동일 제목의 회차',
      ));
    }
    suggestions.sort((a, b) => b.workIds.length.compareTo(a.workIds.length));
    return suggestions;
  }
}

enum LibrarySort { newest, mostRead, title, number }

class WorkSorting {
  static List<WorkEntry> sort(Iterable<WorkEntry> values, LibrarySort mode,
      {bool descending = false}) {
    final result = values.toList();
    int compare(WorkEntry a, WorkEntry b) {
      switch (mode) {
        case LibrarySort.newest:
          return b.addedAt.compareTo(a.addedAt);
        case LibrarySort.mostRead:
          final rank = b.openCount.compareTo(a.openCount);
          return rank == 0 ? b.lastOpenedAt.toString().compareTo(
              a.lastOpenedAt.toString()) : rank;
        case LibrarySort.title:
          return (a.title.isEmpty ? a.workId : a.title)
              .toLowerCase().compareTo((b.title.isEmpty ? b.workId : b.title)
                  .toLowerCase());
        case LibrarySort.number:
          return (BigInt.tryParse(a.workId) ?? BigInt.zero)
              .compareTo(BigInt.tryParse(b.workId) ?? BigInt.zero);
      }
    }
    result.sort((a, b) {
      final n = compare(a, b);
      if (n != 0) return descending ? -n : n;
      return a.workId.compareTo(b.workId);
    });
    return result;
  }
}
