import 'package:http/http.dart' as http;

import 'hitomi_gallery.dart';

enum CandidateCheck { verified, notFound, unavailable }

class CandidateVerification {
  final CandidateCheck status;
  final String title;
  final String reason;
  final List<String> artists;
  final List<String> groups;
  final List<String> tags;

  const CandidateVerification(this.status, {this.title = '', this.reason = '',
      this.artists = const [], this.groups = const [], this.tags = const []});

  bool get exists => status == CandidateCheck.verified;
}

/// Only a definitive 404/410 is treated as a missing work. Rate limits,
/// timeouts, DNS failures and server errors are UNKNOWN, not nonexistent.
class GalleryCandidateVerifier {
  final http.Client client;
  final Map<String, CandidateVerification> cache;
  const GalleryCandidateVerifier(this.client, {required this.cache});

  Future<CandidateVerification> verify(String code) async {
    if (!RegExp(r'^\d{6,9}$').hasMatch(code)) {
      return const CandidateVerification(
        CandidateCheck.unavailable, reason: 'invalid-format');
    }
    final cached = cache[code];
    if (cached != null) return cached;
    try {
      final info = await HitomiGalleryProvider(client).fetchInfo(code);
      final result = CandidateVerification(CandidateCheck.verified,
          title: info.title,
          artists: info.author.split(',').map((e) => e.trim())
              .where((e) => e.isNotEmpty).toList(),
          groups: info.group.split(',').map((e) => e.trim())
              .where((e) => e.isNotEmpty).toList(),
          tags: info.tags);
      cache[code] = result;
      return result;
    } on FormatException catch (e) {
      final error = e.message.toString();
      if (error.contains('HTTP 404') || error.contains('HTTP 410')) {
        const notFound = CandidateVerification(CandidateCheck.notFound);
        cache[code] = notFound;
        return notFound;
      }
      return CandidateVerification(
          CandidateCheck.unavailable, reason: error);
    } catch (error) {
      return CandidateVerification(
          CandidateCheck.unavailable, reason: error.toString());
    }
  }

  /// Up to 24 unique IDs, 3 in-flight requests. No image fetches.
  Future<Map<String, CandidateVerification>> verifyBatch(
      Iterable<String> codes) async {
    final unique = codes.where((id) => RegExp(r'^\d{6,9}$').hasMatch(id))
        .toSet().take(24).toList();
    final results = <String, CandidateVerification>{};
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < unique.length) {
        final id = unique[cursor++];
        results[id] = await verify(id);
      }
    }
    await Future.wait(List.generate(
        unique.length < 3 ? unique.length : 3, (_) => worker()));
    return results;
  }
}
