import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/core/work_edition_service.dart';

void main() {
  WorkEntry make(String id, String lang, {String title = 'Shared Title',
      String seriesId = '', int page = 1}) =>
    WorkEntry.create(workId: id, title: title, author: 'Maker').copyWith(
        sourceLanguage: lang, groupId: seriesId, groupTitle: 'Series',
        groupOrder: 2, currentPage: page);
  test('auto-link two different languages, preserve series and progress', () {
    final base = make('111111','japanese',seriesId:'series_1',page:10);
    final translated = make('222222','korean',page:4);
    final linked = WorkEditionService.autoLink(
      LibraryBackup(works:[base,translated],collections:const []),
      ['222222']);
    expect(linked.works[0].editionGroupId, isNotEmpty);
    expect(linked.works[1].editionGroupId, linked.works[0].editionGroupId);
    expect(linked.works[1].groupId, 'series_1');
    expect(linked.works[0].currentPage, 10);
    expect(linked.works[1].currentPage, 4);
  });
  test('different chapters are not auto-linked', () {
    final first=make('111111','japanese',title:'Title 1화');
    final second=make('222222','korean',title:'Title 2화');
    final result=WorkEditionService.autoLink(
      LibraryBackup(works:[first,second],collections:const []), ['222222']);
    expect(result.works[0].editionGroupId, isEmpty);
    expect(result.works[1].editionGroupId, isEmpty);
  });
  test('manual unlink keeps independent reading records', () {
    final a=make('111111','japanese',page:16);
    final b=make('222222','english',page:4);
    final both=WorkEditionService.link(
      LibraryBackup(works:[a,b],collections:const []), '111111','222222');
    final restored=WorkEditionService.unlink(both,'222222');
    expect(restored.works[0].editionGroupId,isNotEmpty);
    expect(restored.works[1].editionGroupId,isEmpty);
    expect(restored.works[1].currentPage,4);
  });
}
