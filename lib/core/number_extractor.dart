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
    r'(\d{1,3})\s*(?:편|화|부|권|part|episode|ep)',
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
    bool crossLineOnly = false,
    int maxCandidates = 160,
  }) {
    final found = <String, NumberCandidate>{};
    final cap = maxCandidates.clamp(1, 500).toInt();

    void add(String code, String evidence, String episode, String rule,
        int points) {
      if (!RegExp(r'^\d{6,9}$').hasMatch(code)) return;
      final bonus = (_hints.hasMatch(evidence) ? 8 : 0) +
          (creatorComment ? 20 : 0) + (episode.isNotEmpty ? 25 : 0);
      final candidate = NumberCandidate(
        code: code, evidence: evidence.trim(), source: source,
        score: points + bonus, rule: rule, episode: episode,
      );
      if (!found.containsKey(code) || found[code]!.score < candidate.score) {
        found[code] = candidate;
      }
    }

    void parseSegment(String text, String line, String episode,
        {required bool crossLine}) {
      final complete = _complete.allMatches(text).toList();
      for (final m in complete) {
        add(m.group(0)!, line, episode,
            crossLine ? 'cross-line-complete' : 'complete-id',
            crossLine ? 65 : 125);
      }
      // A standalone full-length ID must not be contaminated with the next
      // timestamp, and one numbered episode must not join the next episode.
      final remaining = text.replaceAll(_complete, ' ');
      final groups = _digits.allMatches(remaining)
          .map((m) => m.group(0)!).toList();

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

      for (final m in _tenThousands.allMatches(remaining)) {
        final major = int.tryParse(m.group(1)!);
        final minor = int.tryParse(m.group(2)!);
        if (major == null || minor == null) continue;
        add((major * 10000 + minor).toString(), line, episode,
            crossLine ? 'cross-line-ten-thousands' : 'ten-thousands',
            crossLine ? 35 : 64);
      }
    }

    void parseLine(String raw, {bool crossLine = false}) {
      final line = raw.trim();
      if (line.isEmpty) return;
      final episode = _episodes.firstMatch(line)?.group(0) ?? '';
      for (final match in _links.allMatches(line)) {
        add(match.group(1)!, line, episode, 'gallery-url', 150);
      }
      final plain = line.replaceAll(RegExp(r'https?://\S+'), ' ');
      if (plain.trim().isEmpty) return;

      final markers = _episodes.allMatches(plain).toList();
      if (markers.isEmpty) {
        parseSegment(plain, line, '', crossLine: crossLine);
        return;
      }
      if (markers.first.start > 0) {
        parseSegment(plain.substring(0, markers.first.start), line, '',
            crossLine: crossLine);
      }
      // Numeric windows stay within one chapter. The chapter number itself
      // is a label, not part of the gallery ID (1편 + 2900년7월56일).
      for (var i = 0; i < markers.length; i++) {
        final marker = markers[i];
        final end = i + 1 < markers.length
            ? markers[i + 1].start : plain.length;
        parseSegment(plain.substring(marker.end, end), line, marker.group(0)!,
            crossLine: crossLine);
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
    return (found.values.where((candidate) =>
        !crossLineOnly || candidate.rule.startsWith('cross-line')).toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score != 0 ? score : a.code.compareTo(b.code);
      })).take(cap).toList();
  }
}
