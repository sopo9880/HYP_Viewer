import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/app_backup.dart';
import 'package:hyp_viewer/core/local_search.dart';
import 'package:hyp_viewer/core/online_edition_groups.dart';
import 'package:hyp_viewer/core/online_search.dart';
import 'package:hyp_viewer/core/reader_settings.dart';
import 'package:hyp_viewer/core/work.dart';
import 'package:hyp_viewer/core/work_edition_service.dart';

void main() {
  test('old 0.x schema 1 shelf adds optional evidence without losing data', () {
    final old = LibraryBackup(
      works: [WorkEntry.create(workId: '2711759', title: 'Legacy')
          .copyWith(currentPage: 24, favorite: true,
              completed: true, collections: ['Favorites'])],
      collections: const ['Favorites'],
    );
    final imported = AppBackup.decode(old.encode());
    expect(imported.library.works.single.currentPage, 24);
    expect(imported.library.works.single.completed, true);
    expect(imported.library.works.single.sourceUrls, isEmpty);
    expect(imported.library.works.single.titleAliases, isEmpty);
    final restored = AppBackup.decode(utf8.decode(
      AppBackup(library: imported.library,
        settings: const ReaderSettings(languageCode: 'ja')).encode(),
    ));
    expect(restored.settings!.languageCode, 'ja');
    expect(restored.library.works.single.collections, ['Favorites']);
  });

  test('unlink one language leaves both independent archives and evidence', () {
    final a = WorkEntry.create(
      workId: '111111',
      title: 'One Chapter 1',
      sourceUrls: ['https://youtube.com/post/Ugkx1111111111'],
    ).copyWith(sourceLanguage: 'japanese', currentPage: 19,
        editionGroupId: 'edition_chapter1');
    final b = WorkEntry.create(
      workId: '222222',
      title: 'One Chapter 1 | 한글',
      titleAliases: ['한국어 판본'],
    ).copyWith(sourceLanguage: 'korean', currentPage: 4,
        editionGroupId: 'edition_chapter1');
    final backup = LibraryBackup(works: [a, b], collections: const []);
    final separated = WorkEditionService.unlink(backup, '222222');
    expect(separated.works[0].editionGroupId, 'edition_chapter1');
    expect(separated.works[1].editionGroupId, isEmpty);
    expect(separated.works[0].currentPage, 19);
    expect(separated.works[1].currentPage, 4);
    expect(separated.works[0].sourceUrls.length, 1);
    expect(separated.works[1].titleAliases, ['한국어 판본']);
    expect(separated.works[0].key, 'work:111111');
    expect(separated.works[1].key, 'work:222222');
  });

  test('a thousand works remain searchable and edition groups stay intact', () {
    final works = [
      for (var i = 0; i < 1000; i++)
        WorkEntry.create(workId: (i + 100000).toString(),
          title: 'Sample Chapter ' + (i + 1).toString(),
          author: i % 50 == 0 ? 'Pochi' : 'Different Artist')
          .copyWith(sourceLanguage: 'japanese'),
    ];
    works[99] = works[99].copyWith(
      title: 'Wind Story', editionGroupId: 'edition_99');
    works[100] = works[100].copyWith(
      title: '바람 이야기', editionGroupId: 'edition_99',
      sourceLanguage: 'korean');
    expect(LocalWorkSearch.queryLibrary(works, 'Wind Story').length, 2);
    expect(LocalWorkSearch.queryLibrary(works, 'artist:Pochi').length, 20);
    expect(LocalWorkSearch.queryLibrary(works, '').length, 1000);
  });

  test('online translations show confirmed saved affiliation only', () {
    final local = WorkEntry.create(
      workId: '100', title: 'Sky Wind 2',
      author: 'Original Maker',
    ).copyWith(sourceLanguage: 'japanese',
      sourceSeries: 'Wind', sourceGroup: 'Artist Circle',
      totalPages: 22, editionGroupId: 'edition_sky_2');
    final remote = OnlineSearchWork(
      workId: '200', title: '하늘 바람 2화',
      artists: const ['Original Maker'],
      groups: const ['Artist Circle'],
      series: const ['Wind'],
      language: 'korean',
    );
    final notRelated = OnlineSearchWork(
      workId: '300', title: 'Unrelated Chapter 9',
      artists: const ['Different Author'],
      language: 'english',
    );
    expect(OnlineEditionGroups.savedAnchor(remote, [local])?.workId, '100');
    expect(OnlineEditionGroups.savedAnchor(notRelated, [local]), isNull);
  });
}
