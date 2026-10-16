import 'local_visual_index.dart';
import 'number_extractor.dart';
import 'online_search.dart';
import 'work.dart';

enum VisualEvidenceKind { directCode, localImage, onlineMetadata }

/// One tentative candidate. A successful ID lookup does not prove that
/// an illustration actually belongs to the returned work.
class VisualCandidate {
  final String workId, title, author, evidence;
  final int score;
  final VisualEvidenceKind kind;
  const VisualCandidate({required this.workId, required this.title,
    required this.author, required this.score, required this.kind,
    required this.evidence});
}

abstract final class VisualCandidateRanker {
  static String cleanForCodeExtraction(String raw) {
    // Never combine "2,329 likes, 51 comments" into an artwork ID.
    return raw.split(RegExp(r'\r?\n')).where((line) {
      final lower = line.toLowerCase().trim();
      if (RegExp(r'\b(likes?|comments?|views?|조회수|좋아요)\b')
          .hasMatch(lower) && RegExp(r'\d').hasMatch(lower)) {
        return false;
      }
      return true;
    }).join('\n');
  }

  static List<VisualCandidate> rank({
    required String extractedText,
    List<LocalVisualMatch> imageMatches = const [],
    List<OnlineSearchWork> onlineWorks = const [],
    List<WorkEntry> savedWorks = const [],
  }) {
    final found = <String, VisualCandidate>{};
    void add(VisualCandidate item) {
      if (!RegExp(r'^\d{6,9}$').hasMatch(item.workId)) return;
      final old = found[item.workId];
      if (old == null || old.score < item.score) found[item.workId] = item;
    }
    for (final item in NumberExtractor.extract(
        cleanForCodeExtraction(extractedText), source: 'social')) {
      add(VisualCandidate(workId: item.code, title: '', author: '',
        evidence: item.evidence, score: 70 + item.score ~/ 10,
        kind: VisualEvidenceKind.directCode));
    }
    for (final match in imageMatches) {
      add(VisualCandidate(workId: match.workId,
        title: match.title, author: match.author,
        kind: VisualEvidenceKind.localImage,
        evidence: '내 서재 ' + match.evidence + ' · 유사도 ' +
            (match.similarity * 100).round().toString() + '%',
        score: (match.similarity * 70).round()));
    }
    for (final item in onlineWorks) {
      add(VisualCandidate(workId: item.workId, title: item.title,
        author: item.artists.join(', '),
        kind: VisualEvidenceKind.onlineMetadata,
        evidence: '공개 제목·작가 검색 결과 (장면 일치 미검증)', score: 35));
    }
    for (final work in savedWorks) {
      final current = found[work.workId];
      if (current == null || current.title.isNotEmpty) continue;
      found[work.workId] = VisualCandidate(workId: current.workId,
          title: work.title, author: work.author, score: current.score,
          kind: current.kind, evidence: current.evidence);
    }
    return found.values.toList()..sort((a, b) => b.score.compareTo(a.score));
  }
}
