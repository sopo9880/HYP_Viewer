import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/local_search.dart';
import 'package:hyp_viewer/core/work.dart';

void main() {
  final source = WorkEntry.create(
    workId: '1234567',
    title: 'Original Title | 한국어 제목',
    author: 'Pochi, Other Artist',
  ).copyWith(
    sourceLanguage: 'japanese',
    sourceGroup: 'Pochi circle',
    sourceSeries: 'Episode Universe',
    sourceType: 'manga',
    tags: ['female:glasses','tag:full_color','male:solo'],
  );

  test('plain Pochi finds artist and circle while preserving translated titles', () {
    expect(LocalWorkSearch.matches(source,'Pochi'), true);
    expect(LocalWorkSearch.matches(source,'한국어 제목'), true);
    expect(LocalWorkSearch.matches(source,'Original Title | 한국어 제목'), true);
    expect(LocalWorkSearch.matches(source,'unrelated'), false);
  });

  test('advanced selectors constrain local fields', () {
    expect(LocalWorkSearch.matches(source,'artist:Pochi'), true);
    expect(LocalWorkSearch.matches(source,'group:Pochi'), true);
    expect(LocalWorkSearch.matches(source,'series:Episode'), true);
    expect(LocalWorkSearch.matches(source,'tag:full_color'), true);
    expect(LocalWorkSearch.matches(source,'female:glasses'), true);
    expect(LocalWorkSearch.matches(source,'male:solo'), true);
    expect(LocalWorkSearch.matches(source,'artist:full_color'), false);
    expect(LocalWorkSearch.matches(source,'id:1234567'), true);
  });

  test('search expands a matching saved translation to its linked siblings', () {
    final jp = source.copyWith(
      workId: '1234567', editionGroupId: 'edition_1234567',
      title: '日本語の物語', sourceLanguage: 'japanese');
    final ko = source.copyWith(
      workId: '2345678', editionGroupId: 'edition_1234567',
      title: '한국어 이야기', sourceLanguage: 'korean');
    final unrelated = source.copyWith(
      workId: '3456789', editionGroupId: '',
      title: 'Another Story', sourceLanguage: 'english');
    final all = [jp, ko, unrelated];
    expect(LocalWorkSearch.queryLibrary(all, '日本語の物語')
        .map((w) => w.workId), ['1234567', '2345678']);
    expect(LocalWorkSearch.queryLibrary(all, '日本語の物語',
        language: 'korean'), isEmpty);
    expect(LocalWorkSearch.queryLibrary(all, '한국어 이야기',
        language: 'korean').map((w) => w.workId), ['2345678']);
  });

  test('language aliases work even when query is blank', () {
    expect(LocalWorkSearch.matches(source,'',language:'japanese'), true);
    expect(LocalWorkSearch.matches(source,'',language:'korean'), false);
    expect(LocalWorkSearch.matches(source,'language:ja'), true);
  });
}
