import 'online_search.dart';
import 'work.dart';
import 'work_editions.dart';

/// Conservative search-result presentation only. These inferred groupings
/// never edit users' editionGroupId, collections or saved library records.
abstract final class OnlineEditionGroups {
  static WorkEntry _candidate(OnlineSearchWork work) =>
      WorkEntry.create(
        workId: work.workId,
        title: work.title,
        author: work.artists.join(', '),
      ).copyWith(
        sourceLanguage: work.language,
        sourceGroup: work.groups.join(', '),
        sourceSeries: work.series.join(', '),
      );

  static List<List<OnlineSearchWork>> cluster(
      Iterable<OnlineSearchWork> searchResults) {
    final groups = <List<OnlineSearchWork>>[];
    final seen = <String>{};
    for (final item in searchResults) {
      if (!seen.add(item.workId)) continue;
      final candidate = _candidate(item);
      List<OnlineSearchWork>? target;
      final code = item.language.trim().toLowerCase();
      if (code.isNotEmpty) {
        for (final group in groups) {
          // Every edition must agree with EVERY member, not just the first;
          // this avoids accidentally grouping a chain of different chapters.
          if (group.every((other) {
            final otherCode = other.language.trim().toLowerCase();
            return otherCode.isNotEmpty && otherCode != code &&
                WorkEditions.compare(candidate, _candidate(other)).autoLink;
          })) {
            target = group;
            break;
          }
        }
      }
      if (target == null) {
        groups.add([item]);
      } else {
        target.add(item);
      }
    }
    return groups;
  }
}
