import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/hero_artwork_store.dart';

void main() {
  test('custom home hero artwork persists independently and can be removed',
      () async {
    final dir = await Directory.systemTemp.createTemp('hyp-hero-');
    addTearDown(() => dir.delete(recursive: true));
    const pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLytQAAAABJRU5ErkJggg==';
    final png = base64Decode(pixel);
    final store = HeroArtworkStore(baseDirectory: dir);
    expect(await store.read(), isNull);
    await store.save(png);
    expect(await HeroArtworkStore(baseDirectory: dir).read(), png);
    await store.clear();
    expect(await store.read(), isNull);
    await expectLater(store.save(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });
}
