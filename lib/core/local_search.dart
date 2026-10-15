import 'work.dart';

/// Pure, offline-first library search. Mirrors the supported online field
/// syntax while never sending private collection names or reading history.
abstract final class LocalWorkSearch {
  static const fields = <String>{
    'artist', 'group', 'series', 'tag', 'female', 'male', 'language',
    'title', 'id', 'type',
  };

  static String normalize(String s) => s.trim().toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  static bool matchesLanguage(WorkEntry work, String selected) {
    if (selected.isEmpty) return true;
    final code = normalize(work.sourceLanguage);
    const aliases = <String, Set<String>>{
      'korean': {'korean','ko'},
      'japanese': {'japanese','ja'},
      'english': {'english','en'},
      'chinese': {'chinese','zh','zh-cn','zh-tw','chinese (simplified)',
                  'chinese (traditional)'},
    };
    return aliases.entries.any((entry) =>
        (entry.key == selected || entry.value.contains(selected)) &&
        (entry.key == code || entry.value.contains(code))) ||
        code == selected;
  }

  /// A query matching one saved translation should surface the entire
  /// known logical work. Language filters still apply to each displayed
  /// edition, and unrelated works are never added.
  static List<WorkEntry> queryLibrary(Iterable<WorkEntry> works, String raw,
      {String language = ''}) {
    final all = works.toList();
    final hits = all.where((work) =>
        matches(work, raw, language: language)).toList();
    if (raw.trim().isEmpty) return hits;
    final hitIds = hits.map((entry) => entry.workId).toSet();
    final knownGroups = hits.where((entry) =>
        entry.editionGroupId.isNotEmpty).map((entry) =>
        entry.editionGroupId).toSet();
    return all.where((entry) => hitIds.contains(entry.workId) ||
        entry.editionGroupId.isNotEmpty &&
        knownGroups.contains(entry.editionGroupId) &&
        matchesLanguage(entry, language)).toList();
  }

  static bool matches(WorkEntry work, String raw, {String language = ''}) {
    if (!matchesLanguage(work, language)) return false;
    final term = normalize(raw);
    if (term.isEmpty) return true;
    // Translation-title alternatives separated by | are OR, not one
    // impossible literal phrase. Explicit field filters remain precise.
    final segments = term.split('|').map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    return segments.any((s) => _matchesOne(work, s));
  }

  static bool _matchesOne(WorkEntry work, String text) {
    final delimiter = text.indexOf(':');
    if (delimiter > 0) {
      final key = text.substring(0, delimiter);
      final value = text.substring(delimiter + 1).trim();
      if (fields.contains(key) && value.isNotEmpty) {
        return _fieldMatches(work, key, value);
      }
    }
    final corpus = [
      work.title, work.author, work.workId, work.sourceGroup,
      work.sourceSeries, work.sourceType, work.sourceLanguage,
      ...work.tags, ...work.collections,
    ];
    return corpus.any((item) => normalize(item).contains(text));
  }

  static bool _fieldMatches(WorkEntry work, String key, String term) {
    bool contains(String text) => normalize(text).contains(term);
    switch (key) {
      case 'artist': return contains(work.author);
      case 'group': return contains(work.sourceGroup);
      case 'series': return contains(work.sourceSeries) ||
          contains(work.groupTitle);
      case 'title': return contains(work.title);
      case 'id': return contains(work.workId);
      case 'language': return matchesLanguage(work, term);
      case 'type': return contains(work.sourceType);
      case 'tag': return work.tags.any(contains);
      case 'male':
      case 'female':
        return work.tags.any((tag) {
          final t = normalize(tag);
          return t.startsWith('$key:') && t.substring(key.length + 1)
              .contains(term);
        });
    }
    return false;
  }
}
