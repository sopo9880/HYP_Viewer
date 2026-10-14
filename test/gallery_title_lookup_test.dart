import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyp_viewer/core/hitomi_gallery.dart';

void main() {
  test('blank-title lookup only fetches the matching gallery metadata', () async {
    final urls = <Uri>[];
    final client = MockClient((request) async {
      urls.add(request.url);
      return http.Response('var galleryinfo = '
          '{"id":2711759,"title":"작품 제목","files":[]};', 200);
    });
    final title = await HitomiGalleryProvider(client).fetchTitle('2711759');
    expect(title, '작품 제목');
    expect(urls.map((url) => url.path), ['/galleries/2711759.js']);
    client.close();
  });

  test('title lookup rejects mismatched IDs rather than using wrong title',
      () async {
    final client = MockClient((_) async => http.Response(
        'var galleryinfo = {"id":9999999,"title":"다른 작품"};', 200));
    await expectLater(HitomiGalleryProvider(client).fetchTitle('2711759'),
        throwsFormatException);
    await expectLater(HitomiGalleryProvider(client).fetchTitle('../bad'),
        throwsFormatException);
    client.close();
  });
}
