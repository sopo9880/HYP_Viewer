import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/candidate_verifier.dart';

void main() {
  test('metadata verifies work, 404 is missing, 503 is unknown', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      final id = request.url.pathSegments.last.split('.').first;
      calls.add(id);
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
    expect(calls.toSet(), {'2900756', '3172801', '3419120'});
    await service.verify('2900756');
    await service.verify('3172801');
    expect(calls.length, 3);
    client.close();
  });
}
