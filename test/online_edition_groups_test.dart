import 'package:flutter_test/flutter_test.dart';
import 'package:hyp_viewer/core/online_edition_groups.dart';
import 'package:hyp_viewer/core/online_search.dart';

void main() {
  OnlineSearchWork edition(String id, String title, String language, {
    String author = 'Same Creator', String series = 'Series',
  }) => OnlineSearchWork(
    workId: id,
    title: title,
    language: language,
    artists: [author],
    series: [series],
  );

  test('verified language editions share one visual online search card', () {
    final jp = edition('100', 'Chapter One | 日本語', 'japanese');
    final ko = edition('200', 'Chapter One | 한국어', 'korean');
    final en = edition('300', 'Chapter One | English', 'english');
    final groups = OnlineEditionGroups.cluster([jp, ko, en]);
    expect(groups.length, 1);
    expect(groups.single.map((item) => item.workId), ['100', '200', '300']);
  });

  test('other chapters and unrelated creators are never auto grouped', () {
    final chapter1 = edition('100','First Story 1화','korean');
    final chapter2 = edition('200','First Story 2화','japanese');
    final wrongCreator = edition('300','First Story 1화','english',
        author: 'Other Creator');
    final groups = OnlineEditionGroups.cluster([
      chapter1, chapter2, wrongCreator,
    ]);
    expect(groups.length, 3);
  });

  test('unknown language and duplicate gallery IDs remain single', () {
    final unknown = edition('100','One Chapter','');
    final japanese = edition('200','One Chapter','japanese');
    final grouped = OnlineEditionGroups.cluster([unknown,japanese,unknown]);
    expect(grouped.length, 2);
    expect(grouped.expand((e)=>e).length, 2);
  });
}
