import 'work.dart';

class WorkGroupSuggestion {
  final String title;
  /// Only ungrouped works eligible to add/create, ordered as chapters.
  final List<String> workIds;
  final String reason;
  /// Existing groups are never overwritten; candidates can be appended.
  final String existingGroupId;
  final int confidence;

  const WorkGroupSuggestion(this.title, this.workIds, this.reason,
      {this.existingGroupId = '', this.confidence = 70});
}

/// A conservative series recommender based on each work's OWN metadata.
/// Shared Shorts comments are not valid per-work episode numbers.
class WorkGrouping {

  static final _chapterRange = RegExp(
    r'(\d{1,3})\s*(?:~|～|〜|-|–|—|to)\s*(\d{1,3})\s*'
    r'(?:편|화|부|권|회|話|巻|episode|ep\.?|chapter|ch\.?)',
    caseSensitive: false);
  static final _variant = RegExp(
    r'(?:번외편|외전|특별편|후일담|에필로그|합본|합권|완전판|확장판|'
    r'개정판|수정판|재편집|총집편|통합본|추가편|보너스편|'
    r'omnibus|compilation|complete\s*edition|revised\s*edition|'
    r'after\s*story|special\s*edition|bonus|epilogue|'
    r'side\s*story|extended\s*edition|deluxe\s*edition|'
    r'bonus\s*chapter|spin[\s-]*off|uncut\s*version|'
    r'외전집|신장판|증보판|특별수록|오마케|'
    r'外伝|番外編|総集編|完全版|改訂版|特別編|増補版|おまけ)',
    caseSensitive: false);

  static ({int start, int end})? episodeRange(String title) {
    final m = _chapterRange.firstMatch(title.split('|').first);
    if (m == null) return null;
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    if (a == null || b == null || a > b || b > 999) return null;
    return (start: a, end: b);
  }

  static bool isDerivative(String title) =>
      _variant.hasMatch(title) || episodeRange(title) != null;

  static String relationLabel(WorkEntry work) {
    final range = episodeRange(work.title);
    if (range != null) {
      return range.start.toString() + '~' + range.end.toString() + '화 합본/범위';
    }
    if (_variant.hasMatch(work.title)) return '파생·확장 콘텐츠';
    final chapter = episodeNumber(work);
    return chapter == null ? '관련 작품' : chapter.toString() + '화';
  }

  static String baseTitle(String title) => normalizedSeries(title)
      .replaceAll(_variant, ' ')
      .replaceAll(RegExp(r'[\s+]+'), ' ').trim();

  static final _chapter = RegExp(
      r'(?:제\s*)?(\d{1,3})\s*(?:편|화|부|권|회|episode|ep\.?|part)(?!\d)',
      caseSensitive: false);
  static final _prefixChapter = RegExp(
      r'(?:episode|ep\.?|chapter|ch\.?|part|vol(?:ume)?\.?)\s*#?\s*(\d{1,3})(?!\d)',
      caseSensitive: false);
  // Both 第3話 and 3話 are common Japanese chapter labels.
  static final _japaneseChapter = RegExp(r'(?<!\d)(?:第\s*)?(\d{1,3})\s*[話巻部]');
  static final _trailingNumber = RegExp(r'(?:[\s\-_.#]+)(\d{1,3})\s*$');
  static final _afterStory = RegExp(
    r'(?:[\s~\-_.:：()\[\]【】]*(?:after[\s\-_]*story|epilogue|후일담|에필로그|後日談|外伝|外傳|番外編|외전)[\s~\-_.:：()\[\]【】]*)$',
    caseSensitive: false);
  static bool _isAfterStory(String title) =>
      _afterStory.hasMatch(title.split('|').first.trim());

  static int? _chapterInText(String text) {
    for (final pattern in [_chapter, _prefixChapter, _japaneseChapter]) {
      final m = pattern.firstMatch(text);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  static int? episodeNumber(WorkEntry work) {
    // A saved Shorts batch keeps the same originalComment for EVERY work.
    // Reading the first "1편" in that shared block assigns 1 to all works.
    final original = work.title.split('|').first.trim();
    if (episodeRange(original) != null) return null;
    final titleChapter = _chapterInText(original);
    if (titleChapter != null) return titleChapter;
    // Bare trailing numerals in the ORIGINAL title denote a sequel:
    // "Yarasete Yarutte Ittenno! 2 | ... 2".
    final trailing = _trailingNumber.firstMatch(original);
    if (trailing != null && normalizedSeries(original).length >= 4) {
      return int.tryParse(trailing.group(1)!);
    }
    // Only use comment evidence if the line points to this work specifically.
    for (final line in work.originalComment.split(RegExp(r'[\r\n]+'))) {
      final chapter = _chapterInText(line);
      if (chapter == null) continue;
      if (RegExp('(?<![0-9])' + RegExp.escape(work.workId) + '(?![0-9])')
          .hasMatch(line)) return chapter;
      final match = _chapter.firstMatch(line) ??
          _prefixChapter.firstMatch(line) ?? _japaneseChapter.firstMatch(line);
      if (match == null) continue;
      // Accept the number mnemonic AFTER the chapter marker on the same line.
      final encoded = RegExp(r'\d+').allMatches(line.substring(match.end))
          .map((m) => m.group(0)!).join();
      if (encoded == work.workId) return chapter;
    }
    return null;
  }

  static String normalizedSeries(String rawTitle) {
    // Multilingual titles are often "original | translated". Compare the
    // original separately: different translations must not prevent a match.
    var s = rawTitle.split('|').first.toLowerCase().trim();
    // Metadata titles often start with a circle or artist in brackets.
    s = s.replaceFirst(RegExp(r'^(?:\[[^\]]{1,75}\]\s*)+'), '');
    s = s.replaceAll(_chapterRange, ' ')
        .replaceAll(_afterStory, ' ')
        .replaceAll(_chapter, ' ')
        .replaceAll(_prefixChapter, ' ')
        .replaceAll(_japaneseChapter, ' ')
        .replaceAll(_trailingNumber, ' ')
        .replaceAll(RegExp(r'[\[\](){}【】［］「」『』\-_.:：#]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s;
  }

  static bool _usableTitle(WorkEntry work) {
    final title = normalizedSeries(work.title);
    return title.length >= 4 &&
        !RegExp(r'^(?:작품|work|gallery)\s*\d+$', caseSensitive: false)
            .hasMatch(title);
  }

  static bool _sameKnownCreator(WorkEntry a, WorkEntry b) {
    final sameAuthor = a.author.trim().isNotEmpty &&
        a.author.trim().toLowerCase() == b.author.trim().toLowerCase();
    final sameCircle = a.sourceGroup.trim().isNotEmpty &&
        a.sourceGroup.trim().toLowerCase() ==
            b.sourceGroup.trim().toLowerCase();
    return sameAuthor || sameCircle;
  }

  static bool _creatorConflict(WorkEntry a, WorkEntry b) {
    return a.author.trim().isNotEmpty && b.author.trim().isNotEmpty &&
        a.author.trim().toLowerCase() != b.author.trim().toLowerCase() &&
        a.sourceGroup.trim().isNotEmpty &&
        b.sourceGroup.trim().isNotEmpty &&
        a.sourceGroup.trim().toLowerCase() !=
            b.sourceGroup.trim().toLowerCase();
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.length > 150 || b.length > 150) return 0;
    // Character-level edit distance, bounded by plausible title lengths.
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final d = previous[j] + 1;
        final insert = current[j - 1] + 1;
        final substitute = previous[j - 1] + cost;
        current[j] = d < insert
            ? (d < substitute ? d : substitute)
            : (insert < substitute ? insert : substitute);
      }
      previous = current;
    }
    final length = a.length > b.length ? a.length : b.length;
    return 1 - previous.last / length;
  }


  /// Titles are the primary discovery signal; creator metadata is optional.
  /// Suggestions remain opt-in and are reviewed before any library changes.
  static String _compactTitle(String title) =>
      baseTitle(title).replaceAll(RegExp(r'[\s·・]+'), '');

  static bool _sharedTitleCore(String a, String b) {
    final first = baseTitle(a);
    final second = baseTitle(b);
    final one = _compactTitle(a);
    final two = _compactTitle(b);
    if (one.isEmpty || two.isEmpty) return false;
    final shorter = one.length <= two.length ? one : two;
    final longer = one.length > two.length ? one : two;
    if (shorter.length >= 6 && longer.contains(shorter) &&
        shorter.length / longer.length >= 0.40) return true;

    // More than one substantial common term is needed: "이야기" alone
    // cannot group unrelated titles.
    final firstWords = first.split(RegExp(r'\s+'))
        .where((word) => word.length >= 3).toSet();
    final secondWords = second.split(RegExp(r'\s+'))
        .where((word) => word.length >= 3).toSet();
    final common = firstWords.intersection(secondWords);
    final commonLength = common.fold<int>(0, (sum, word) => sum + word.length);
    return common.length >= 2 && commonLength >= 7 &&
        commonLength / shorter.length >= 0.52;
  }

  static double _titleMatchScore(WorkEntry a, WorkEntry b) {
    final first = _compactTitle(a.title);
    final second = _compactTitle(b.title);
    if (first.isEmpty || second.isEmpty) return 0;
    if (first == second) return 1;
    final edit = _similarity(first, second);
    final shorter = first.length <= second.length ? first : second;
    final longer = first.length > second.length ? first : second;
    if (shorter.length >= 6 && longer.contains(shorter) &&
        shorter.length / longer.length >= 0.40) {
      final contained = 0.70 + 0.26 * shorter.length / longer.length;
      return edit > contained ? edit : contained;
    }
    if (_sharedTitleCore(a.title, b.title) && edit < 0.66) return 0.66;
    return edit;
  }

  static bool _sameSeries(WorkEntry a, WorkEntry b) {
    if (!_usableTitle(a) || !_usableTitle(b)) return false;
    final score = _titleMatchScore(a, b);
    if (score < 0.60) return false;

    // Another-language copy of an unnumbered/same-numbered chapter is
    // an edition candidate, not an inferred series, even without an author.
    final aLang = a.sourceLanguage.trim().toLowerCase();
    final bLang = b.sourceLanguage.trim().toLowerCase();
    if (aLang.isNotEmpty && bLang.isNotEmpty && aLang != bLang &&
        episodeNumber(a) == episodeNumber(b) &&
        !isDerivative(a.title) && !isDerivative(b.title) &&
        score >= 0.91 &&
        (a.totalPages == 0 || b.totalPages == 0 ||
            (a.totalPages - b.totalPages).abs() <= 8)) {
      return false;
    }

    // Conflicting artist AND circle is strong negative evidence,
    // but an almost identical title remains a reviewable suggestion.
    if (_creatorConflict(a, b) && score < 0.92) return false;
    if (score >= 0.70) return true;

    // 60-70% needs extra evidence: shared creator or series metadata,
    // or a substantial shared title core. Matching creator alone is not
    // enough when titles are genuinely unrelated.
    final exactSourceSeries = a.sourceSeries.trim().isNotEmpty &&
        b.sourceSeries.trim().isNotEmpty &&
        a.sourceSeries.trim().toLowerCase() ==
            b.sourceSeries.trim().toLowerCase();
    return _sameKnownCreator(a, b) || exactSourceSeries ||
        _sharedTitleCore(a.title, b.title);
  }

  /// A majority threshold admits descriptive variants without admitting
  /// transitive A~B~C chains: 2-member clusters must match both members.
  static bool _fitsCluster(List<WorkEntry> members, WorkEntry candidate) {
    if (members.isEmpty) return false;
    final needed = (members.length * 2 + 2) ~/ 3; // ceil(2 * n / 3)
    var matching = 0;
    for (final item in members) {
      if (_sameSeries(item, candidate)) matching++;
    }
    return matching >= needed;
  }

  /// Original chapter order can still be explicitly overridden by groupOrder.
  static int compareChapters(WorkEntry a, WorkEntry b) {
    final aAfter = _isAfterStory(a.title);
    final bAfter = _isAfterStory(b.title);
    if (aAfter != bAfter) return aAfter ? 1 : -1;
    final ae = episodeNumber(a), be = episodeNumber(b);
    if (ae != null && be != null && ae != be) return ae.compareTo(be);
    if (ae != null && be == null) {
      // An unnumbered original is commonly the first installment of a series.
      if (ae > 1 && normalizedSeries(a.title) ==
          normalizedSeries(b.title)) return 1;
      return -1;
    }
    if (be != null && ae == null) {
      if (be > 1 && normalizedSeries(a.title) ==
          normalizedSeries(b.title)) return -1;
      return 1;
    }
    if (a.sourceDate.isNotEmpty && b.sourceDate.isNotEmpty &&
        a.sourceDate != b.sourceDate) {
      return a.sourceDate.compareTo(b.sourceDate);
    }
    final ai = BigInt.tryParse(a.workId), bi = BigInt.tryParse(b.workId);
    if (ai != null && bi != null) return ai.compareTo(bi);
    return a.workId.compareTo(b.workId);
  }

  static List<WorkGroupSuggestion> suggest(List<WorkEntry> works) {
    final groups = <String, List<WorkEntry>>{};
    // Multiple translations of one chapter are a single logical title.
    // Prefer its existing-series representative before any ungrouped copy.
    final all = [...works]..sort((a, b) {
      final grouped = (a.groupId.isEmpty ? 1 : 0)
          .compareTo(b.groupId.isEmpty ? 1 : 0);
      return grouped != 0 ? grouped : a.workId.compareTo(b.workId);
    });
    final seenEditions = <String>{};
    final sorted = all.where((work) => work.editionGroupId.isEmpty ||
        seenEditions.add(work.editionGroupId)).toList()
      ..sort((a, b) => a.workId.compareTo(b.workId));
    final clusters = <List<WorkEntry>>[];

    // Existing series may receive new works, but are never recreated/changed.
    for (final work in sorted.where((w) => w.groupId.isNotEmpty)) {
      groups.putIfAbsent(work.groupId, () => []).add(work);
    }
    for (final members in groups.values) {
      clusters.add([...members]);
    }
    for (final work in sorted.where((w) => w.groupId.isEmpty)) {
      if (!_usableTitle(work)) continue;
      final matches = <List<WorkEntry>>[];
      for (final group in clusters) {
        if (_fitsCluster(group, work)) {
          matches.add(group);
        }
      }
      // Do not guess between several already-existing user groups.
      if (matches.length == 1) {
        matches.single.add(work);
      } else if (matches.isEmpty) {
        clusters.add([work]);
      }
    }

    final result = <WorkGroupSuggestion>[];
    for (final cluster in clusters) {
      final newcomers = cluster.where((w) => w.groupId.isEmpty).toList()
        ..sort(compareChapters);
      final existing = cluster.where((w) => w.groupId.isNotEmpty).toList();
      if (existing.isEmpty && newcomers.length < 2) continue;
      if (existing.isNotEmpty && newcomers.isEmpty) continue;
      final base = existing.isEmpty ? newcomers.first : existing.first;
      final reference = cluster.first;
      final chapters = cluster.map(episodeNumber).whereType<int>().toList();
      final derivatives = cluster.where((w) => isDerivative(w.title)).toList();
      final uniqueChapters = chapters.toSet().length == chapters.length;
      final matchingCreators = cluster.every(
          (w) => w.workId == reference.workId ||
              _sameKnownCreator(w, reference));
      final exactNames = cluster.every((w) =>
          normalizedSeries(w.title) == normalizedSeries(reference.title));
      final hasAfterStory = cluster.any((w) => _isAfterStory(w.title));
      final scores = cluster.where((w) => w.workId != reference.workId)
          .map((w) => _titleMatchScore(reference, w)).toList();
      final weakestScore = scores.isEmpty ? 1.0 :
          scores.reduce((a, b) => a < b ? a : b);
      final confidence = derivatives.isNotEmpty && matchingCreators
          ? 94 : derivatives.isNotEmpty ? 80
          : exactNames && hasAfterStory && matchingCreators
          ? 95 : exactNames && chapters.length >= 2 && uniqueChapters
          ? 95 : exactNames && matchingCreators ? 89 : exactNames ? 77
          : weakestScore >= 0.84 && matchingCreators ? 86
          : weakestScore >= 0.84 ? 82
          : weakestScore >= 0.70 ? 74 : 64;
      final title = existing.isNotEmpty && base.groupTitle.isNotEmpty
          ? base.groupTitle : normalizedSeries(base.title);
      final reason = derivatives.isNotEmpty
          ? '동일 기본 제목과 파생 콘텐츠 후보 · ' +
              derivatives.map(relationLabel).toSet().join(', ') +
              ' · 회차와 구성 확인 필요'
          : existing.isNotEmpty
          ? '기존 시리즈와 제목·제작 정보가 일치하는 새 작품'
          : exactNames && hasAfterStory
          ? '본편과 후일담·외전의 제목 및 제작 정보 확인 필요'
          : exactNames && chapters.length >= 2 && uniqueChapters
          ? '같은 제목의 서로 다른 회차'
          : exactNames && matchingCreators
          ? '작품 제목과 제작자가 일치'
          : exactNames ? '작품 제목 일치 · 회차 정보 확인 필요'
          : matchingCreators
          ? '유사한 제목과 제작 정보 · 같은 작품인지 확인 필요'
          : '유사한 제목을 폭넓게 추천 · 다른 작품인지 직접 확인 필요';
      result.add(WorkGroupSuggestion(
        title, newcomers.map((w) => w.workId).toList(), reason,
        existingGroupId: existing.isEmpty ? '' : existing.first.groupId,
        confidence: confidence,
      ));
    }
    result.sort((a, b) {
      final byConfidence = b.confidence.compareTo(a.confidence);
      return byConfidence != 0 ? byConfidence :
          b.workIds.length.compareTo(a.workIds.length);
    });
    return result;
  }
}

enum LibrarySort { newest, published, hitomiPopular, mostRead, title, number, chapter }

class WorkSorting {
  static List<WorkEntry> sort(Iterable<WorkEntry> values, LibrarySort mode,
      {bool descending = false, Map<String, int> popularityRanks = const {}}) {
    final result = values.toList();
    int compare(WorkEntry a, WorkEntry b) {
      switch (mode) {
        case LibrarySort.newest:
          return b.addedAt.compareTo(a.addedAt);
        case LibrarySort.published:
          return b.sourceDate.compareTo(a.sourceDate);
        case LibrarySort.hitomiPopular:
          final ar = popularityRanks[a.workId];
          final br = popularityRanks[b.workId];
          if (ar == null && br == null) return 0;
          if (ar == null) return 1;
          if (br == null) return -1;
          return ar.compareTo(br);
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
        case LibrarySort.chapter:
          final n = a.groupOrder.compareTo(b.groupOrder);
          return n != 0 ? n : WorkGrouping.compareChapters(a, b);
      }
    }
    result.sort((a, b) {
      final n = compare(a, b);
      // Entries without public rank/date must always sort last.
      if (mode == LibrarySort.published &&
          (a.sourceDate.isEmpty != b.sourceDate.isEmpty)) {
        return a.sourceDate.isEmpty ? 1 : -1;
      }
      if (mode == LibrarySort.hitomiPopular &&
          ((popularityRanks[a.workId] == null) !=
              (popularityRanks[b.workId] == null))) {
        return popularityRanks[a.workId] == null ? 1 : -1;
      }
      if (n != 0) return descending ? -n : n;
      return a.workId.compareTo(b.workId);
    });
    return result;
  }
}
