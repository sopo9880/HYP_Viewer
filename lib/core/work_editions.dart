import 'work.dart';
import 'work_grouping.dart';

/// Matching is conservative: works from the same franchise are not
/// necessarily the same chapter. The reader may manually confirm a match.
class EditionMatch {
  final int score;
  final String reason;
  const EditionMatch(this.score, this.reason);
  bool get autoLink => score >= 80;
  bool get isCandidate => score >= 45;
}

abstract final class WorkEditions {
  static String originalTitle(String title) {
    var s = title.split('|').first.trim();
    s = s.replaceAll(
      RegExp(r'\b(english|korean|japanese|chinese|translated|translation)\b',
          caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'(한국어|영어|일본어|中文|日本語|翻訳|번역판)'), ' ');
    return WorkGrouping.normalizedSeries(s);
  }

  static String languageName(String value) {
    switch (value.trim().toLowerCase()) {
      case 'korean': case 'ko': return '한국어';
      case 'japanese': case 'ja': return '日本語';
      case 'english': case 'en': return 'English';
      case 'chinese': case 'zh': return '中文';
      default: return value.trim().isEmpty ? '언어 미확인' : value;
    }
  }

  static String? _knownConflict(String first, String second) {
    if (first.trim().isNotEmpty && second.trim().isNotEmpty &&
        first.trim().toLowerCase() != second.trim().toLowerCase()) {
      return '작가/서클 정보 불일치';
    }
    return null;
  }

  static EditionMatch compare(WorkEntry a, WorkEntry b) {
    if (a.workId == b.workId) return const EditionMatch(100, '동일 ID');
    final ca = WorkGrouping.episodeNumber(a);
    final cb = WorkGrouping.episodeNumber(b);
    if (ca != null && cb != null && ca != cb) {
      return const EditionMatch(0, '서로 다른 회차');
    }
    if (ca != null && cb == null && ca > 1 ||
        cb != null && ca == null && cb > 1) {
      return const EditionMatch(0, '회차 불확실');
    }
    final titleA = originalTitle(a.title);
    final titleB = originalTitle(b.title);
    if (titleA.length < 4 || titleB.length < 4 ||
        RegExp(r'^(?:작품|work|gallery)\s*\d+$', caseSensitive: false)
            .hasMatch(titleA) ||
        RegExp(r'^(?:작품|work|gallery)\s*\d+$', caseSensitive: false)
            .hasMatch(titleB)) {
      return const EditionMatch(0, '확인 가능한 원제 부족');
    }
    if (_knownConflict(a.author, b.author) != null &&
        _knownConflict(a.sourceGroup, b.sourceGroup) != null) {
      return const EditionMatch(0, '작가와 서클 불일치');
    }
    final sameTitle = titleA == titleB;
    final sameAuthor = a.author.trim().isNotEmpty &&
        a.author.trim().toLowerCase() == b.author.trim().toLowerCase();
    final sameCircle = a.sourceGroup.trim().isNotEmpty &&
        a.sourceGroup.trim().toLowerCase() ==
            b.sourceGroup.trim().toLowerCase();
    final sameSeries = a.sourceSeries.trim().isNotEmpty &&
        a.sourceSeries.trim().toLowerCase() ==
            b.sourceSeries.trim().toLowerCase();
    if (!sameTitle) {
      // Different titles and only shared creators/franchise are insufficient
      // for automatic cross-language linking.
      return EditionMatch(sameAuthor && sameCircle && sameSeries ? 50 : 0,
          '원제 상이 · 직접 확인 필요');
    }
    var score = 60;
    if (sameAuthor) score += 20;
    if (sameCircle) score += 20;
    if (sameSeries) score += 5;
    if (ca != null && ca == cb) score += 10;
    if (a.totalPages > 0 && b.totalPages > 0) {
      final diff = (a.totalPages - b.totalPages).abs();
      if (diff <= 3) score += 5;
      if (diff > 25) score -= 30;
    }
    // Never automatically link on a bare title alone.
    if (!sameAuthor && !sameCircle) score = score.clamp(0, 75).toInt();
    return EditionMatch(score.clamp(0, 100).toInt(),
        sameAuthor || sameCircle ? '원제 및 제작자 일치' : '원제 일치 · 확인 필요');
  }

  static String groupKey(WorkEntry work) =>
      work.editionGroupId.isEmpty ? 'single:' + work.workId
          : 'edition:' + work.editionGroupId;

  static List<WorkEntry> versions(Iterable<WorkEntry> all, WorkEntry target) {
    final key = groupKey(target);
    return all.where((w) => groupKey(w) == key).toList();
  }

  static WorkEntry preferred(List<WorkEntry> editions, String language) {
    if (editions.isEmpty) throw ArgumentError('No editions');
    if (language == 'auto') return editions.first;
    for (final work in editions) {
      if (work.sourceLanguage.toLowerCase() == language) return work;
    }
    return editions.first;
  }
}
