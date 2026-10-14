class NumberCandidate {
  final String code;
  final String evidence;
  final String source;
  final int score;
  final String episode;
  final String rule;
  const NumberCandidate({
    required this.code, required this.evidence,
    required this.source, required this.score,
    this.episode = '', this.rule = '',
  });
}

/// Deterministic, broad candidate gathering. Candidates are untrusted until
/// checked against remote gallery metadata. Never treat existence as proof
/// that the gallery is the one discussed in the video.
class NumberExtractor {
  static final RegExp _digits = RegExp(r'\d+');
  static final RegExp _complete = RegExp(r'(?<!\d)\d{6,9}(?!\d)');
  static final RegExp _links = RegExp(
    r'https?://(?:www\.)?hitomi\.la/(?:reader|galleries)/(\d{6,9})(?:\.html)?',
    caseSensitive: false,
  );
  static final RegExp _episodes = RegExp(
    r'(\d{1,3})\s*(?:편|화|부|권|part|episode|ep)\b?',
    caseSensitive: false,
  );
  static final RegExp _tenThousands =
      RegExp(r'(\d{1,4})\s*만\s*(\d{1,4})');
  static final RegExp _hints = RegExp(
    r'(번호|품번|코드|날짜|시간|년|월|일|만|컬렉션|작품|편|파트)',
    caseSensitive: false,
  );

  /// First attempt always stays on one physical line. Cross-line mode adds
  /// adjacent lines in the same paragraph ONLY for a second, explicit pass.
  /// Blank lines form comment boundaries (automatic YouTube imports use
  /// double newlines between separate comments).
  static List<NumberCandidate> extract(
    String text, {
    String source = 'manual',
    bool creatorComment = false,
    bool allowCrossLine = false,
    int maxCandidates = 160,
  }) {
    final found = <String, NumberCandidate>{};
    final cap = maxCandidates.clamp(1, 500).toInt();

    void add(String code, String evidence, String episode, String rule,
        int points) {
      if (!RegExp(r'^\d{6,9}$').hasMatch(code)) return;
      final bonus = (_hints.hasMatch(evidence) ? 8 : 0) +
          (creatorComment ? 20 : 0);
      final candidate = NumberCandidate(
        code: code, evidence: evidence.trim(), source: source,
        score: points + bonus, rule: rule, episode: episode,
      );
      if (!found.containsKey(code) || found[code]!.score < candidate.score) {
        found[code] = candidate;
      }
    }

    void parseLine(String raw, {bool crossLine = false}) {
      final line = raw.trim();
      if (line.isEmpty) return;
      final episode = _episodes.firstMatch(line)?.group(0) ?? '';

      var withoutLinks = line;
      for (final match in _links.allMatches(line)) {
        add(match.group(1)!, line, episode, 'gallery-url', 150);
      }
      withoutLinks = withoutLinks.replaceAll(RegExp(r'https?://\S+'), ' ');
      if (withoutLinks.trim().isEmpty) return;

      // A complete gallery number must never be joined to surrounding dates.
      final complete = _complete.allMatches(withoutLinks).toList();
      for (final m in complete) {
        add(m.group(0)!, line, episode,
            crossLine ? 'cross-line-complete' : 'complete-id',
            crossLine ? 65 : 125);
      }
      final withoutComplete = withoutLinks.replaceAll(_complete, ' ');
      final groups = _digits.allMatches(withoutComplete)
          .map((m) => m.group(0)!).toList();

      // Every contiguous window of numbers within the same line may encode
      // an ID. No jumping over unrelated groups and no exponential subsets.
      for (var i = 0; i < groups.length; i++) {
        var joined = '';
        for (var j = i; j < groups.length && j < i + 7; j++) {
          joined += groups[j];
          if (joined.length > 9) break;
          if (j > i && joined.length >= 6) {
            add(joined, line, episode,
                crossLine ? 'cross-line' : 'line-window',
                crossLine ? 30 : 65);
          }
        }
      }

      // Korean "271만 59" is also encoded as 2710059, not just 27159.
      for (final m in _tenThousands.allMatches(withoutComplete)) {
        final major = int.tryParse(m.group(1)!);
        final minor = int.tryParse(m.group(2)!);
        if (major == null || minor == null) continue;
        add((major * 10000 + minor).toString(), line, episode,
            crossLine ? 'cross-line-ten-thousands' : 'ten-thousands',
            crossLine ? 35 : 64);
      }
    }

    for (final rawLine in text.split(RegExp(r'\r\n|\r|\n'))) {
      parseLine(rawLine);
    }
    if (allowCrossLine) {
      // A blank line separates comments. NEVER combine two users' comments.
      final paragraphs = text.split(RegExp(r'(?:\r?\n)\s*(?:\r?\n)'));
      for (final paragraph in paragraphs) {
        final lines = paragraph.split(RegExp(r'\r\n|\r|\n'));
        for (var i = 0; i + 1 < lines.length; i++) {
          if (!_digits.hasMatch(lines[i]) || !_digits.hasMatch(lines[i + 1])) {
            continue;
          }
          parseLine(lines[i] + ' ' + lines[i + 1], crossLine: true);
        }
      }
    }
    return (found.values.toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score != 0 ? score : a.code.compareTo(b.code);
      })).take(cap).toList();
  }
}
