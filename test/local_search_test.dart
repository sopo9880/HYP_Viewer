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

  test('language aliases work even when query is blank', () {
    expect(LocalWorkSearch.matches(source,'',language:'japanese'), true);
    expect(LocalWorkSearch.matches(source,'',language:'korean'), false);
    expect(LocalWorkSearch.matches(source,'language:ja'), true);
  });
}
