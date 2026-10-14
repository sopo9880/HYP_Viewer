class NumberCandidate {
  final String code;
  final String evidence;
  final String source;
  final int score;
  final String episode;
  final String rule;

  const NumberCandidate({
    required this.code,
    required this.evidence,
    required this.source,
    required this.score,
    this.episode = '',
    this.rule = '',
  });
}

/// Deterministic, AI-free candidate generation. A candidate is NOT verified:
/// the metadata verifier must confirm existence independently.
class NumberExtractor {
  static final RegExp _groups = RegExp(r'\d+');
  static final RegExp _complete = RegExp(r'(?<!\d)\d{6,9}(?!\d)');
  static final RegExp _links = RegExp(
    r'https?://(?:www\.)?hitomi\.la/(?:reader|galleries)/(\d{6,9})(?:\.html)?',
    caseSensitive: false,
  );
  static final RegExp _episode = RegExp(
    r'(\d{1,3})\s*(편|화|부|권|part|episode|ep)\s*(?:[-–—:=：]\s*)?',
    caseSensitive: false,
  );
  static final RegExp _tenThousands =
      RegExp(r'(\d{1,4})\s*만\s*(\d{1,4})');
  static final RegExp _hint = RegExp(
    r'(번호|품번|코드|날짜|시간|방문|갱생|년|월|일|만|컬렉션|작품|편|파트)',
    caseSensitive: false,
  );
  static final RegExp _background = RegExp(
    r'(시대적\s*배경|시대\s*배경|작품\s*배경|배경\s*(?:은|:|：))',
    caseSensitive: false,
  );

  static List<NumberCandidate> extract(
    String text, {
    String source = 'manual',
    bool creatorComment = false,
  }) {
    final found = <String, NumberCandidate>{};
    final lines = text.split(RegExp(r'[\r\n;。]+'));

    void add(String code, String evidence, String episode, String rule,
        int points) {
      if (!RegExp(r'^\d{6,9}$').hasMatch(code)) return;
      final score = points + (episode.isNotEmpty ? 30 : 0) +
          (_hint.hasMatch(evidence) ? 12 : 0) +
          (creatorComment ? 30 : 0);
      final result = NumberCandidate(
        code: code, evidence: evidence.trim(), episode: episode,
        source: source, score: score, rule: rule,
      );
      if (!found.containsKey(code) || found[code]!.score < score) {
        found[code] = result;
      }
    }

    void parseSegment(String segment, String original, String episode) {
      var s = segment.trim();
      if (s.isEmpty) return;
      // All URLs are removed before joining digit groups. Only known
      // gallery links can contribute an ID.
      for (final link in _links.allMatches(s)) {
        add(link.group(1)!, original, episode, 'gallery-url', 95);
      }
      s = s.replaceAll(RegExp(r'https?://\S+'), ' ').trim();
      if (s.isEmpty) return;
      final direct = _complete.allMatches(s).map((m) => m.group(0)!).toList();
      for (final code in direct) {
        add(code, original, episode, 'complete-id', 65);
      }
      // Standalone complete IDs should not be rejoined with a timestamp,
      // episode number, or an unrelated account/year.
      if (direct.isNotEmpty) return;

      final groups = _groups.allMatches(s).map((m) => m.group(0)!).toList();
      if (groups.length < 2 || groups.length > 5) return;
      if (_background.hasMatch(original) && episode.isEmpty) return;
      final hasUnits = RegExp(r'(년|월|일|시간|분|초|만|[/／])').hasMatch(s);
      final hasHint = RegExp(r'(번호|품번|코드|날짜|교제|시간)').hasMatch(original);
      if (episode.isEmpty && !hasUnits && !hasHint) return;
      final joined = groups.join();
      add(joined, original, episode, 'split-number', 50);

      // Korean '만' has two common readings: concatenated groups and
      // place-value spelling. Retain both for existence verification.
      for (final match in _tenThousands.allMatches(s)) {
        final major = int.tryParse(match.group(1)!);
        final minor = int.tryParse(match.group(2)!);
        if (major == null || minor == null) continue;
        add((major * 10000 + minor).toString(),
            original, episode, 'ten-thousands', 46);
      }
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final episodeMatches = _episode.allMatches(line).toList();
      if (episodeMatches.isEmpty) {
        parseSegment(line, line, '');
        continue;
      }

      // Prefix text still may contain a standalone ID or a gallery URL.
      if (episodeMatches.first.start > 0) {
        parseSegment(line.substring(0, episodeMatches.first.start), line, '');
      }
      for (var i = 0; i < episodeMatches.length; i++) {
        final marker = episodeMatches[i];
        final end = i + 1 < episodeMatches.length
            ? episodeMatches[i + 1].start : line.length;
        final part = marker.group(1)! + marker.group(2)!;
        parseSegment(line.substring(marker.end, end), line, part);
      }
    }
    return (found.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.code.compareTo(b.code);
      })).take(30).toList();
  }
}
