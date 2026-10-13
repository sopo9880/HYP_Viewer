import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'work.dart';

class LibraryExport {
  static Uint8List json(LibraryBackup backup) =>
      Uint8List.fromList(utf8.encode(backup.encode()));

  static Uint8List xlsx(LibraryBackup backup) {
    final book = Excel.createExcel();
    final sheet = book['전체 작품'];
    sheet.appendRow([
      TextCellValue('번호'), TextCellValue('제목'),
      TextCellValue('작가'), TextCellValue('원본 쇼츠'),
      TextCellValue('즐겨찾기'), TextCellValue('현재 페이지'),
      TextCellValue('완독'), TextCellValue('목록')
    ]);
    for (final w in backup.works) {
      sheet.appendRow([
        TextCellValue(w.workId), TextCellValue(w.title),
        TextCellValue(w.author), TextCellValue(w.videoUrl),
        TextCellValue(w.favorite ? 'Y' : 'N'),
        IntCellValue(w.currentPage),
        TextCellValue(w.completed ? 'Y' : 'N'),
        TextCellValue(w.collections.join(', '))
      ]);
    }
    final fav = book['즐겨찾기'];
    fav.appendRow([TextCellValue('번호'), TextCellValue('제목')]);
    for (final w in backup.works.where((e) => e.favorite)) {
      fav.appendRow([TextCellValue(w.workId), TextCellValue(w.title)]);
    }
    final collections = book['사용자 목록'];
    collections.appendRow([TextCellValue('목록'), TextCellValue('번호')]);
    for (final name in backup.collections) {
      final members = backup.works.where((w) => w.collections.contains(name));
      if (members.isEmpty) {
        collections.appendRow([TextCellValue(name), TextCellValue('')]);
      } else {
        for (final w in members) {
          collections.appendRow([TextCellValue(name), TextCellValue(w.workId)]);
        }
      }
    }
    book.delete('Sheet1');
    return Uint8List.fromList(book.encode()!);
  }
}
