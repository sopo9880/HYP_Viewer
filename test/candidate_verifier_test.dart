import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/candidate_verifier.dart';

void main() {
  test('metadata verifies work, 404 is missing, 503 is unknown', () async {
    final calls = <Uri>[];
    final client = MockClient((request) async {
      final id = request.url.pathSegments.last.split('.').first;
      calls.add(request.url);
      if (id == '2900756') {
        return http.Response.bytes(utf8.encode(
          'var galleryinfo = {"id":2900756,"title":"Part 1"};'), 200);
      }
      return http.Response(id == '3172801' ? 'missing' : 'down',
          id == '3172801' ? 404 : 503);
    });
    final cache = <String, CandidateVerification>{};
    final service = GalleryCandidateVerifier(client, cache: cache);
    final results = await service.verifyBatch([
      '2900756', '3172801', '3419120', '2900756'
    ]);
    expect(results['2900756']!.status, CandidateCheck.verified);
    expect(results['2900756']!.title, 'Part 1');
    expect(results['3172801']!.status, CandidateCheck.notFound);
    expect(results['3419120']!.status, CandidateCheck.unavailable);
    List<String> hostsFor(String id) => calls
        .where((url) => url.pathSegments.last.split('.').first == id)
        .map((url) => url.host).toList();
    const original = 'ltn.gold-usergeneratedcontent.net';
    const firstMirror = 'heliotrope.saebasol.org';
    const secondMirror = 'inst.psec.dev';
    // Known-good metadata is not retried. Unavailable records check
    // independent mirrors before reporting a failure.
    expect(hostsFor('2900756'), [original]);
    expect(hostsFor('3172801'), [original, firstMirror, secondMirror]);
    expect(hostsFor('3419120'), [original, firstMirror, secondMirror]);
    final requestsBeforeCachedLookups = calls.length;
    expect(requestsBeforeCachedLookups, 7);
    await service.verify('2900756');
    await service.verify('3172801');
    expect(calls.length, requestsBeforeCachedLookups);
    client.close();
  });
}
