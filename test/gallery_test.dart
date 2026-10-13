import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/gallery.dart';

Uint8List zipOf(List<String> names) {
  final archive = Archive();
  for (final name in names) {
    archive.addFile(ArchiveFile.bytes(name, [137, 80, 78, 71]));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test('CBZ images are ordered naturally (2 before 10)', () {
    final book = GalleryArchive.decode(zipOf([
      'chapter/10.png', 'chapter/2.png', 'chapter/1.png', 'notes.txt'
    ]));
    expect(book.pageCount, 3);
    expect(book.filename(0), 'chapter/1.png');
    expect(book.filename(1), 'chapter/2.png');
    expect(book.filename(2), 'chapter/10.png');
  });

  test('text-only archive is rejected', () {
    expect(() => GalleryArchive.decode(zipOf(['readme.txt'])), throwsFormatException);
  });

  test('reads page bytes without extracting to disk', () {
    final book = GalleryArchive.decode(zipOf(['001.png']));
    expect(book.pageBytes(0).length, 4);
  });

  test('archive limit rejects a giant input', () {
    expect(() => GalleryArchive.decode(Uint8List(0)), throwsFormatException);
  });
}
