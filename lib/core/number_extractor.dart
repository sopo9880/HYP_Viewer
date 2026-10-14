class NumberCandidate {
  final String code;
  final String evidence;
  final String source;
  final int score;

  const NumberCandidate({
    required this.code,
    required this.evidence,
    required this.source,
    required this.score,
  });
}

/// AI-free numeric extraction: candidates are not verified work identifiers.
class NumberExtractor {
  static final RegExp _groups = RegExp(r'\d+');
  static final RegExp _links = RegExp(
    r'https?://(?:www\.)?hitomi\.la/(?:reader|galleries)/(\d{6,9})(?:\.html)?',
    caseSensitive: false,
  );
  static final RegExp _hints = RegExp(
    r'(번호|품번|코드|날짜|시간|방문|갱생|시대|배경|년|월|일|만|횟수|컬렉션|작품|편|파트)',
    caseSensitive: false,
  );

  static List<NumberCandidate> extract(
    String text, {
    String source = 'manual',
    bool creatorComment = false,
  }) {
    final candidates = <String, NumberCandidate>{};
    final lines = text.split(RegExp(r'[\r\n;。]+'));

    void add(String candidate, String evidence, int extra) {
      if (!RegExp(r'^\d{6,9}$').hasMatch(candidate)) return;
      final score = extra +
          (_hints.hasMatch(evidence) ? 15 : 0) +
          (creatorComment ? 30 : 0);
      final item = NumberCandidate(
        code: candidate,
        evidence: evidence.trim(),
        source: source,
        score: score,
      );
      if (!candidates.containsKey(candidate) ||
          candidates[candidate]!.score < score) {
        candidates[candidate] = item;
      }
    }

    for (final line in lines) {
      var s = line.trim();
      if (s.isEmpty) continue;
      // URLs contain unrelated numbers; recognize gallery links explicitly
      // and remove all other links before looking for numeric phrases.
      for (final link in _links.allMatches(s)) {
        add(link.group(1)!, s, 85);
      }
      s = s.replaceAll(RegExp(r'https?://\S+'), ' ').trim();
      if (s.isEmpty) continue;
      final groups = _groups.allMatches(s).map((e) => e.group(0)!).toList();
      if (groups.isEmpty) continue;
      // A comment such as "1편 1234567, 2편 7654321" has TWO works.
      // Joining every number would manufacture an unrelated extra ID.
      if (!groups.any((g) => RegExp(r'^\d{6,9}
    }
    return candidates.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.code.compareTo(b.code);
      });
  }
}
).hasMatch(g))) {
        add(groups.join(), s, 25);
      }
      for (final group in groups) {
        add(group, s, 45);
      }

      // Support multiple "271만 59" style IDs in the same comment.
      for (final tens in RegExp(r'(\d+)\s*만\s*(\d{1,4})').allMatches(s)) {
        final major = int.tryParse(tens.group(1)!);
        final minor = int.tryParse(tens.group(2)!);
        if (major != null && minor != null) {
          add((major * 10000 + minor).toString(), s, 45);
        }
      }
    }
    return candidates.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.code.compareTo(b.code);
      });
  }
}
