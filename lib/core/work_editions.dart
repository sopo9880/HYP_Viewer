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
    // Only strip a translation marker when it is delimited or at the end.
    // "The English Teacher" and "Korean Love" are legitimate titles.
    final markers = RegExp(
      r'\s*[\[(](?:english|korean|japanese|chinese|translation|'
      r'translated|한국어|영어|일본어|中文|日本語|翻訳|번역판)[\])]\s*$',
      caseSensitive: false);
    s = s.replaceFirst(markers, '').trim();
    return WorkGrouping.normalizedSeries(s);
  }

  /// Canonical language identifier shared by local records and mirrors.
  /// A record labeled 'ko' is not a different edition from 'korean'.
  static String canonicalLanguage(String value) {
    switch (value.trim().toLowerCase()) {
      case 'ko': case 'kor': case 'korean': case '한국어': return 'korean';
      case 'ja': case 'jpn': case 'japanese': case '日本語': return 'japanese';
      case 'en': case 'eng': case 'english': return 'english';
      case 'zh': case 'zh-cn': case 'zh-tw': case 'zh-hans': case 'zh-hant':
      case 'chs': case 'cht':
      case 'chinese': case 'chinese (simplified)':
      case 'chinese (traditional)': case '中文': return 'chinese';
      default: return value.trim().toLowerCase();
    }
  }

  static String languageName(String value) {
    switch (canonicalLanguage(value)) {
      case 'korean': return '한국어';
      case 'japanese': return '日本語';
      case 'english': return 'English';
      case 'chinese': return '中文';
      default: return value.trim().isEmpty ? '언어 미확인' : value;
    }
  }

  static EditionMatch compare(WorkEntry a, WorkEntry b) {
    if (a.workId == b.workId) return const EditionMatch(100, '동일 ID');
    // Explicitly different user-series identities are never equivalent
    // editions, even if the creator and short title happen to match.
    if (a.groupId.isNotEmpty && b.groupId.isNotEmpty &&
        a.groupId != b.groupId) {
      return const EditionMatch(0, '서로 다른 사용자 시리즈');
    }
    if (a.sourceSeries.trim().isNotEmpty &&
        b.sourceSeries.trim().isNotEmpty &&
        a.sourceSeries.trim().toLowerCase() !=
            b.sourceSeries.trim().toLowerCase()) {
      return const EditionMatch(0, '서로 다른 원본 시리즈');
    }
    final ca = WorkGrouping.episodeNumber(a);
    final cb = WorkGrouping.episodeNumber(b);
    if (ca != null && cb != null && ca != cb) {
      return const EditionMatch(0, '서로 다른 회차');
    }
    if (ca != null && cb == null && ca > 1 ||
        cb != null && ca == null && cb > 1) {
      return const EditionMatch(0, '회차 정보 불충분');
    }
    final titleA = originalTitle(a.title);
    final titleB = originalTitle(b.title);
    bool meaningful(String title) => title.length >= 4 &&
        !RegExp(r'^(?:작품|work|gallery)\s*\d+$', caseSensitive: false)
            .hasMatch(title);
    final hasTitleEvidence = meaningful(titleA) && meaningful(titleB) ||
        a.titleAliases.isNotEmpty && b.titleAliases.isNotEmpty;
    if (!hasTitleEvidence) {
      return const EditionMatch(0, '확인 가능한 원제 또는 별칭 부족');
    }

    String normal(String text) => text.trim().toLowerCase();
    bool sameNonEmpty(String left, String right) =>
        normal(left).isNotEmpty && normal(left) == normal(right);
    final sameAuthor = sameNonEmpty(a.author, b.author);
    final sameCircle = sameNonEmpty(a.sourceGroup, b.sourceGroup);
    if (a.author.trim().isNotEmpty && b.author.trim().isNotEmpty &&
        a.sourceGroup.trim().isNotEmpty && b.sourceGroup.trim().isNotEmpty &&
        !sameAuthor && !sameCircle) {
      return const EditionMatch(0, '작가와 서클 정보 불일치');
    }
    final sameSeries = sameNonEmpty(a.sourceSeries, b.sourceSeries);
    final sameDate = sameNonEmpty(a.sourceDate, b.sourceDate);
    final hasPages = a.totalPages > 0 && b.totalPages > 0;
    final pageDifference = hasPages
        ? (a.totalPages - b.totalPages).abs() : 9999;
    // Titles can contain multiple original/translated aliases separated by
    // '|'. Any independently matching alias counts as shared title evidence.
    Set<String> aliases(WorkEntry work) => [
      work.title, ...work.titleAliases,
    ].expand((title) => title.split('|'))
        .map((name) => WorkGrouping.normalizedSeries(name))
        .where((name) => name.length >= 3).toSet();
    final sameTitle = titleA == titleB ||
        aliases(a).intersection(aliases(b)).isNotEmpty;
    if (!sameTitle) {
      // Different translations can have entirely different titles.
      // Auto-link only with independent creator, series, chapter and
      // page evidence, or especially strong standalone-publication evidence.
      if (sameSeries && (sameAuthor || sameCircle) &&
          ca != null && cb != null && ca == cb &&
          pageDifference <= 4) {
        return const EditionMatch(90, '번역 제목 상이 · 제작자/시리즈/회차/페이지 일치');
      }
      if (sameSeries && sameAuthor && sameCircle && sameDate &&
          ca == null && cb == null && pageDifference <= 2) {
        return const EditionMatch(85, '번역 제목 상이 · 제작자/발행일/페이지 일치');
      }
      return EditionMatch(
        sameAuthor || sameCircle || sameSeries ? 50 : 0,
        '번역 제목이 달라서 수동 확인 필요',
      );
    }
    var score = 60;
    if (sameAuthor) score += 20;
    if (sameCircle) score += 20;
    if (sameSeries) score += 5;
    if (ca != null && ca == cb) score += 10;
    if (hasPages) {
      if (pageDifference <= 3) score += 5;
      if (pageDifference > 25) score -= 30;
    }
    if (!sameAuthor && !sameCircle) score = score.clamp(0, 75).toInt();
    return EditionMatch(score.clamp(0, 100).toInt(),
        sameAuthor || sameCircle ? '원제 및 제작자 일치' : '원제 일치 · 확인 필요');
  }

  /// Adjust the *displayed* evidence using two available covers.
  ///
  /// Cover similarity alone never promotes a non-automatic metadata match
  /// into an automatic match. A striking visual mismatch can instead mark a
  /// potential automatic match for the reader to review manually.
  static EditionMatch withCoverEvidence(EditionMatch metadata,
      double? similarity) {
    if (similarity == null || !similarity.isFinite ||
        similarity < 0 || similarity > 1 || metadata.score <= 0) {
      return metadata;
    }
    if (similarity <= .18 && metadata.autoLink) {
      return EditionMatch(74,
          metadata.reason + ' · 표지 차이 큼, 수동 확인 필요');
    }
    if (similarity >= .9 && metadata.isCandidate) {
      final boosted = (metadata.score + 7).clamp(
          0, metadata.autoLink ? 100 : 79).toInt();
      return EditionMatch(boosted,
          metadata.reason + ' · 표지 유사도 높음 (보조 근거)');
    }
    return metadata;
  }

  /// Hide a logical chapter on the shelf when any language edition is
  /// completed. Search and each edition's underlying reading status remain
  /// independent.
  static List<WorkEntry> visibleOnShelf(
      Iterable<WorkEntry> works, bool hideCompleted) {
    final all = works.toList();
    if (!hideCompleted) return all;
    // The original v0.4.0 contract treats a logical chapter as finished as
    // soon as ANY of its language editions is finished. Individual edition
    // progress stays independent; search still uses the complete library.
    final completedGroups = all.where((entry) =>
        entry.editionGroupId.isNotEmpty && entry.completed)
        .map((entry) => entry.editionGroupId).toSet();
    return all.where((entry) =>
        !entry.completed && !completedGroups.contains(entry.editionGroupId))
        .toList();
  }

  /// Diversify a translated-title search without sending reading history.
  /// Explicit creator/series terms only come from public work metadata.
  static List<String> searchQueries(WorkEntry work, String entered) {
    final result = <String>[];
    void add(String query) {
      final cleaned = query.trim();
      if (cleaned.isNotEmpty && cleaned.length <= 150 &&
          !result.contains(cleaned)) result.add(cleaned);
    }
    add(entered);
    // Retain both sides of "original | translated": a plain search can
    // otherwise miss a differently localized title.
    for (final title in [work.title, ...work.titleAliases]) {
      for (final part in title.split('|')) add(part);
    }
    final creator = work.author.split(',').first.trim();
    if (creator.isNotEmpty) add('artist:' + creator);
    final circle = work.sourceGroup.split(',').first.trim();
    if (circle.isNotEmpty) add('group:' + circle);
    // series: is not consistently understood by provider APIs. A plain
    // keyword query is safe even on mirrors without that operator.
    if (work.sourceSeries.trim().isNotEmpty) {
      add(work.sourceSeries.trim());
    }
    return result.take(12).toList();
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
    if (language == 'recent') {
      final recent = [...editions]
        ..sort((a, b) => (b.lastOpenedAt ?? '')
            .compareTo(a.lastOpenedAt ?? ''));
      return recent.first;
    }
    if (language == 'auto') return editions.first;
    for (final work in editions) {
      if (canonicalLanguage(work.sourceLanguage) ==
          canonicalLanguage(language)) return work;
    }
    return editions.first;
  }
}
