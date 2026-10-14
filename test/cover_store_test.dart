import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/cover_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes scaled thumbnails to separate automatic and page files', () async {
    final dir = await Directory.systemTemp.createTemp('hyp-cover-');
    addTearDown(() => dir.delete(recursive: true));
    final images = const CoverStore().baseDirectory; // default is null
    expect(images, isNull);

    final store = CoverStore(baseDirectory: dir);
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
      'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLytQAAAABJRU5ErkJggg==',
    );
    final first = await store.save('2711759', bytes);
    final chosen = await store.save('2711759', bytes,
        mode: 'page', page: 7);
    expect(first, isNotEmpty);
    expect(chosen, isNotEmpty);
    expect(await store.read('2711759'), isNotNull);
    expect(await store.read('2711759', mode: 'page', page: 7), isNotNull);
    expect(await store.read('2711759', mode: 'page', page: 8), isNull);
    expect(await store.read('2711759', mode: 'preset'), isNull);
  });
}
