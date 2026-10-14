import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/hitomi_gallery.dart';

void main() {
  test('galleryinfo metadata parses tags, creator, series and page count', () {
    final data = GalleryInfo.parse('3172801', {
      'id': 3172801, 'title': 'Some Work', 'artists': [{'artist': 'Artist'}],
      'groups': [{'group': 'Circle'}], 'parodys': [{'parody': 'Original'}],
      'tags': [{'tag': 'long hair', 'female': true}],
      'characters': [{'character': 'Character'}],
      'language': 'japanese', 'type': 'doujinshi', 'date': '2026-01-01',
      'files': [{'hash':'dummy'}, {'hash':'dummy2'}],
    });
    expect(data.title, 'Some Work');
    expect(data.author, 'Artist');
    expect(data.group, 'Circle');
    expect(data.series, 'Original');
    expect(data.pageCount, 2);
    expect(data.tags.single, 'female:long hair');
    expect(data.views, isNull);
  });
}
