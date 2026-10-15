import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/reader_settings.dart';
import '../core/reading_history.dart';
import '../core/work.dart';
import '../core/work_grouping.dart';
import 'hyp_theme.dart';

/// A-L: all-time library facts remain separate from date-stamped sessions.
/// No historical activity or remote view counts are fabricated.
class HypReadingInsights extends StatefulWidget {
  final List<WorkEntry> works;
  final List<ReadingSession> sessions;
  final ReaderSettings settings;
  final Future<void> Function(ReaderSettings) onSaveSettings;
  final Future<void> Function() onClearHistory;
  final ValueChanged<WorkEntry> onOpenWork;

  const HypReadingInsights({
    super.key,
    required this.works,
    required this.sessions,
    required this.settings,
    required this.onSaveSettings,
    required this.onClearHistory,
    required this.onOpenWork,
  });

  @override
  State<HypReadingInsights> createState() => _HypReadingInsightsState();
}

class _HypReadingInsightsState extends State<HypReadingInsights> {
  String _period = 'all';
  String _completion = 'all';
  String _report = 'month';
  final GlobalKey _reportKey = GlobalKey();
  bool _savingReport = false;

  List<WorkEntry> get _works => widget.works.where((w) {
    if (_completion == 'complete') return w.completed;
    if (_completion == 'incomplete') return !w.completed;
    return true;
  }).toList();

  List<ReadingSession> get _sessions {
    final cut = switch (_period) {
      '7' => DateTime.now().subtract(const Duration(days: 7)),
      '30' => DateTime.now().subtract(const Duration(days: 30)),
      '365' => DateTime.now().subtract(const Duration(days: 365)),
      _ => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    };
    final filteredIds = _works.map((w) => w.workId).toSet();
    return widget.sessions.where((s) =>
        s.startedAt.isAfter(cut) && filteredIds.contains(s.workId)).toList();
  }

  String _date(DateTime value) => value.toLocal().toIso8601String().substring(0, 10);

  Widget _section(String heading, Widget child, {IconData icon = Icons.insights}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 15),
        leading: Icon(icon, color: HypColors.lightPurple),
        title: Text(heading, style: const TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
        children: [Align(alignment: Alignment.centerLeft, child: child)],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: HypColors.raised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: HypColors.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 17, color: HypColors.lightPurple),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      ]),
      const SizedBox(height: 8),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ]),
  );

  Widget _bars(List<(String, int)> data, {int count = 8}) {
    if (data.isEmpty) return const Text('집계 가능한 정보가 아직 없어.');
    final shown = data.take(count).toList();
    final max = shown.fold<int>(1, (v, e) => e.$2 > v ? e.$2 : v);
    return Column(children: [
      for (final entry in shown) Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Row(children: [
            Expanded(child: Text(entry.$1, overflow: TextOverflow.ellipsis,
              maxLines: 1, style: const TextStyle(fontSize: 12))),
            Text(entry.$2.toString(), style: const TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            minHeight: 7, value: entry.$2 / max,
            borderRadius: BorderRadius.circular(8),
          ),
        ]),
      ),
    ]);
  }

  Widget _ranking(List<WorkEntry> works, {int max = 8}) {
    if (works.isEmpty) return const Text('조건에 맞는 작품이 없어.');
    return Column(children: [
      for (final entry in works.take(max).toList().asMap().entries)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 16, child: Text(
              (entry.key + 1).toString(), style: const TextStyle(fontSize: 12))),
          title: Text(entry.value.title.isEmpty
              ? '#' + entry.value.workId : entry.value.title,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('열람 ' + entry.value.openCount.toString() +
              '회' + (entry.value.completed ? ' · 완독' : '') +
              ' · #' + entry.value.workId),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onOpenWork(entry.value),
        ),
    ]);
  }

  static List<WorkEntry> _mostRead(List<WorkEntry> works) =>
      [...works]..sort((a,b) => b.openCount.compareTo(a.openCount));

  List<(String, int)> _tagCountsByFavorites() =>
      ReadingInsights.tagStats(_works)
          .map((tag) => (tag.name, tag.favorites)).where((e) => e.$2 > 0)
          .toList()..sort((a,b) => b.$2.compareTo(a.$2));

  List<(String, int)> _tagPairs() {
    final pairs = <String, int>{};
    for (final work in _works) {
      final tags = work.tags.map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty).toSet().toList()..sort();
      for (var i = 0; i < tags.length && i < 20; i++) {
        for (var j = i + 1; j < tags.length && j < 20; j++) {
          final pair = tags[i] + ' + ' + tags[j];
          pairs.update(pair, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    final entries = pairs.entries.toList()
      ..sort((a,b) => b.value.compareTo(a.value));
    return entries.map((e) => (e.key, e.value)).toList();
  }

  Widget _activityBars() {
    final daily = ReadingInsights.activityByDay(_sessions);
    final today = DateTime.now();
    final days = [
      for (var i = 13; i >= 0; i--)
        DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: i)),
    ];
    final max = days.fold<int>(1, (n, day) {
      final total = daily[_date(day)] ?? 0;
      return total > n ? total : n;
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('최근 14일 열람 세션 (수집 시작 이후)'),
      const SizedBox(height: 14),
      SizedBox(height: 92, child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days) Expanded(
            child: Tooltip(
              message: _date(day) + ': ' +
                  (daily[_date(day)] ?? 0).toString() + '회',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  height: 8 + 78 * (daily[_date(day)] ?? 0) / max,
                  decoration: BoxDecoration(
                    color: HypColors.primary.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      )),
    ]);
  }

  Widget _heatmap() {
    final daily = ReadingInsights.activityByDay(_sessions);
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('최근 91일 · 연속 독서 ' +
          ReadingInsights.streakDays(_sessions).toString() + '일'),
      const SizedBox(height: 10),
      Wrap(spacing: 3, runSpacing: 3, children: [
        for (var i = 90; i >= 0; i--) Builder(builder: (context) {
          final day = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: i));
          final count = daily[_date(day)] ?? 0;
          return Tooltip(
            message: _date(day) + ' · ' + count.toString() + '회',
            child: SizedBox(width: 13, height: 13, child: ColoredBox(
              color: count == 0 ? HypColors.raised
                : count == 1 ? const Color(0xFF4D467B)
                : count < 4 ? const Color(0xFF7961B7)
                : HypColors.lightPurple,
            )),
          );
        }),
      ]),
    ]);
  }

  List<(String, int)> _sessionPeriods(bool monthly) {
    final counts = <String, int>{};
    for (final session in _sessions) {
      final day = session.startedAt.toLocal();
      final key = monthly
          ? day.year.toString() + '-' + day.month.toString().padLeft(2, '0')
          : day.year.toString();
      counts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    final rows = counts.entries.toList()
      ..sort((a,b) => b.key.compareTo(a.key));
    return rows.map((e) => (e.key, e.value)).toList();
  }

  Future<void> _saveReport() async {
    if (_savingReport) return;
    setState(() => _savingReport = true);
    try {
      final boundary = _reportKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('리포트 화면을 찾지 못했어.');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('PNG로 저장할 수 없어.');
      final bytes = Uint8List.view(png.buffer, png.offsetInBytes, png.lengthInBytes);
      await FilePicker.platform.saveFile(
        dialogTitle: '독서 리포트 PNG 저장',
        fileName: 'HYP_Reading_Report.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
        bytes: bytes,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('리포트 이미지 저장 실패: ' + error.toString())));
    } finally {
      if (mounted) setState(() => _savingReport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final works = _works;
    final sessions = _sessions;
    final completed = works.where((w) => w.completed).length;
    final unread = works.where((w) => w.openCount == 0).length;
    final favorites = works.where((w) => w.favorite).length;
    final totalOpens = works.fold<int>(0, (n,w) => n + w.openCount);
    final known = works.where((w) => w.totalPages > 0).toList();
    final progress = known.isEmpty ? null : known.fold<double>(0,
      (n,w) => n + (w.completed ? 1 :
          w.currentPage / w.totalPages).clamp(0.0, 1.0)) / known.length;
    final tags = ReadingInsights.tagStats(works);
    final series = ReadingInsights.series(works);
    final sorted = _mostRead(works);
    final recent = [...works]..sort((a,b) =>
        (b.lastOpenedAt ?? '').compareTo(a.lastOpenedAt ?? ''));
    final seriesProgress = series.entries.toList()
      ..sort((a,b) => b.value.length.compareTo(a.value.length));
    final rankedInterest = tags.where((e) => e.favorites > 0).toList()
      ..sort((a,b) => b.favorites.compareTo(a.favorites));
    final recognizedTags = works.where((w) => w.tags.isNotEmpty).length;
    final recommendationTags = rankedInterest.take(4).map((e) => e.name).toSet();
    final recommendations = works.where((w) => !w.completed &&
        w.openCount == 0).toList()
      ..sort((a,b) {
        int weight(WorkEntry w) => w.tags.where((tag) =>
            recommendationTags.contains(tag.toLowerCase().trim())).length * 10 +
            (w.favorite ? 12 : 0);
        return weight(b).compareTo(weight(a));
      });
    final noMetadata = works.where((w) => w.author.isEmpty ||
        w.tags.isEmpty).toList();
    final stale = works.where((w) => !w.completed &&
        w.lastOpenedAt != null &&
        (DateTime.tryParse(w.lastOpenedAt!)?.isBefore(
            DateTime.now().subtract(const Duration(days: 90))) ?? false)).toList();
    final periodTotals = _sessionPeriods(_report == 'month');
    final summaryTags = rankedInterest.isNotEmpty ? rankedInterest : tags;
    final activeMinutes = (ReadingInsights.activeSeconds(sessions) / 60).round();
    final reportTitle = _report == 'month' ? '월간 독서 리포트' : '연간 독서 리포트';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const HypSectionTitle(icon: Icons.query_stats_rounded,
        title: '내 독서', subtitle: '즐겨찾기 · 취향 · 독서 통계를 내 기기에서 분석해요.'),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        DropdownButton<String>(
          key: const Key('insights-period'),
          value: _period,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('전체 기간')),
            DropdownMenuItem(value: '7', child: Text('최근 7일')),
            DropdownMenuItem(value: '30', child: Text('최근 30일')),
            DropdownMenuItem(value: '365', child: Text('최근 1년')),
          ],
          onChanged: (v) => setState(() => _period = v ?? 'all'),
        ),
        DropdownButton<String>(
          key: const Key('insights-completed-filter'),
          value: _completion,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('모든 작품')),
            DropdownMenuItem(value: 'complete', child: Text('완독 작품')),
            DropdownMenuItem(value: 'incomplete', child: Text('미완독 작품')),
          ],
          onChanged: (v) => setState(() => _completion = v ?? 'all'),
        ),
      ]),
      const Text('서재의 누적 열람 수·완독률은 전체 기록 기준이며, 기간 필터는 날짜가 있는 독서 세션에 적용돼.',
        style: TextStyle(fontSize: 11, color: HypColors.muted)),
      const SizedBox(height: 13),
      LayoutBuilder(builder: (context, constraints) => GridView.count(
        crossAxisCount: constraints.maxWidth < 450 ? 2 : 4,
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8, mainAxisSpacing: 8,
        childAspectRatio: constraints.maxWidth < 450 ? 1.65 : 1.75,
        children: [
          _metric('보유 작품', works.length.toString(), Icons.library_books),
          _metric('즐겨찾기', favorites.toString(), Icons.favorite),
          _metric('완독', completed.toString(), Icons.check_circle),
          _metric('누적 열람', totalOpens.toString(), Icons.visibility),
        ],
      )),
      const SizedBox(height: 8),
      Text('미열람 ' + unread.toString() + '개 · 오프라인 보유율은 다운로드 화면에서 확인 · '
          '평균 진행률 ' + (progress == null ? '계산 불가' :
          (progress * 100).round().toString() + '% (' + known.length.toString() + '개 기준)')),
      const SizedBox(height: 13),
      _section('A · 독서 현황', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('완독률: ' + (works.isEmpty ? '0' :
            (completed * 100 / works.length).round().toString()) + '%'),
        Text('읽는 중: ' + (works.where((w) =>
          w.openCount > 0 && !w.completed).length).toString() + '개'),
        Text('날짜별 기록이 있는 열람 세션: ' + sessions.length.toString() + '회'),
        Text('활성 독서 시간(추정): ' + activeMinutes.toString() + '분'),
      ]), icon: Icons.donut_small),
      _section('B · 태그 취향', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('분석 가능: ' + recognizedTags.toString() + ' / ' +
            works.length.toString() + '개 작품'),
        const SizedBox(height: 8),
        const Text('많이 열람한 태그'),
        _bars(tags.map((tag) => (tag.name, tag.reads)).toList()),
        const Text('즐겨찾기 작품에 많은 태그'),
        _bars(_tagCountsByFavorites(), count: 5),
        const Text('자주 함께 등장하는 태그 조합'),
        _bars(_tagPairs(), count: 5),
        const Text('태그 완독률은 각 태그의 완독 작품 수 / 보유 작품 수로 계산해.',
          style: TextStyle(fontSize: 11, color: HypColors.muted)),
        ...tags.take(5).map((t) => Text(t.name + ' · 완독률 ' +
            (t.works == 0 ? '0' :
            (t.completed * 100 / t.works).round().toString()) + '%')),
      ]), icon: Icons.sell),
      _section('C · 작품 랭킹', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('누적 열람 TOP 8'),
        _ranking(sorted.where((w) => w.openCount > 0).toList()),
        const SizedBox(height: 8),
        const Text('최근 열람 작품'),
        _ranking(recent.where((w) => w.lastOpenedAt != null).toList(), max: 5),
        const SizedBox(height: 8),
        const Text('재열람이 많은 작품 (누적 2회 이상)'),
        _ranking(sorted.where((w) => w.openCount >= 2).toList(), max: 5),
      ]), icon: Icons.emoji_events),
      _section('D · 작가와 서클', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('작가별 누적 열람'),
        _bars(ReadingInsights.topCreators(works)),
        const SizedBox(height: 8),
        const Text('서클별 누적 열람'),
        _bars(ReadingInsights.topCreators(works, circle: true)),
      ]), icon: Icons.people),
      _section('E · 독서 활동 추이', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _activityBars(),
        const SizedBox(height: 12),
        Text('선택 기간 열람 ' + sessions.length.toString() +
            '회 · 활성 시간 약 ' + activeMinutes.toString() + '분'),
        const Text('기존 누적 열람 횟수에는 날짜가 없어 과거 일별 그래프는 복원하지 않아.',
          style: TextStyle(fontSize: 11, color: HypColors.muted)),
      ]), icon: Icons.bar_chart),
      _section('F · 시리즈 진행 상황', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('관리 중인 시리즈: ' + series.length.toString() + '개'),
        if (seriesProgress.isEmpty) const Text('아직 묶은 작품이 없어.'),
        for (final entry in seriesProgress.take(12)) Builder(builder: (context) {
          final ordered = [...entry.value]..sort(WorkGrouping.compareChapters);
          final read = ordered.where((w) => w.completed).length;
          final next = ordered.where((w) => !w.completed).firstOrNull;
          final title = ordered.first.groupTitle.isNotEmpty
              ? ordered.first.groupTitle : '시리즈';
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(read.toString() + '/' +
                ordered.length.toString() + '편 완독'),
            trailing: next == null ? const Icon(Icons.done_all)
                : const Icon(Icons.play_arrow),
            onTap: next == null ? null : () => widget.onOpenWork(next),
          );
        }),
      ]), icon: Icons.layers),
      _section('G · 내 취향 요약', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(summaryTags.isEmpty
            ? '태그 정보가 부족해. 온라인 작품 정보 또는 수동 태그를 채우면 분석할 수 있어.'
            : '내 서재에서는 ' + summaryTags.take(3)
                .map((tag) => tag.name).join(' · ') +
                ' 태그가 눈에 띄어. 즐겨찾기와 누적 열람 기록을 기반으로 한 요약이야.'),
        const SizedBox(height: 5),
        Text('총 ' + works.length.toString() + '개 작품 중 ' +
            recognizedTags.toString() + '개에 태그가 있어. 추정 결과로 봐줘.'),
      ]), icon: Icons.psychology),
      _section('H · 다음 읽을 작품 추천', Column(children: [
        const Text('좋아하는 태그·즐겨찾기·아직 읽지 않은 작품을 우선 추천해.'),
        _ranking(recommendations, max: 5),
      ]), icon: Icons.auto_awesome),
      _section('I · 독서 캘린더', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _heatmap(),
        const SizedBox(height: 10),
        Text('수집된 ' + sessions.length.toString() + '개 세션의 날짜를 사용해.'),
      ]), icon: Icons.calendar_month),
      _section('J · 서재 정리 도우미', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('작가 또는 태그 정보가 부족한 작품: ' +
            noMetadata.length.toString() + '개'),
        _ranking(noMetadata, max: 5),
        Text('90일 이상 열지 않은 미완독 작품: ' + stale.length.toString() + '개'),
        _ranking(stale, max: 5),
        const Text('중복 번호는 서재 저장 시 차단돼. 다운로드 용량 분석은 실제 파일 크기를 확인할 때만 제공할 수 있어.',
          style: TextStyle(fontSize: 11, color: HypColors.muted)),
      ]), icon: Icons.inventory_2),
      _section('K · 월간·연간 독서 리포트', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'month', label: Text('월간')),
            ButtonSegment(value: 'year', label: Text('연간')),
          ],
          selected: {_report},
          onSelectionChanged: (value) => setState(() => _report = value.first),
        ),
        const SizedBox(height: 10),
        RepaintBoundary(key: _reportKey, child: ColoredBox(
          color: HypColors.surface,
          child: Padding(padding: const EdgeInsets.all(13),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(reportTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('HYP Viewer · 기기 안에 저장된 실제 열람 세션 기준'),
              const SizedBox(height: 8),
              _bars(periodTotals, count: 12),
              Text('선택 기간: ' + (_period == 'all' ? '전체' : '최근 ' + _period + '일')),
            ]),
          ),
        )),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _savingReport ? null : _saveReport,
          icon: const Icon(Icons.image_outlined),
          label: const Text('리포트 PNG로 저장'),
        ),
      ]), icon: Icons.summarize),
      _section('L · 통계 필터 및 내 기록 관리', Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('새 독서 활동 기록 수집'),
          subtitle: const Text('활성 시간·날짜·페이지 정보를 기기 안에만 보관해.'),
          value: widget.settings.analyticsEnabled,
          onChanged: (enabled) => widget.onSaveSettings(
              widget.settings.copyWith(analyticsEnabled: enabled)),
        ),
        ListTile(
          key: const Key('insights-clear-history'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_outline),
          title: const Text('날짜별 독서 활동 기록 삭제'),
          subtitle: const Text('서재·완독 표시·기존 열람 횟수는 유지돼.'),
          onTap: () async {
            final approved = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('독서 활동 기록 삭제'),
                content: const Text('기기에 저장된 날짜별 독서 세션을 전부 삭제할까? 이 작업은 되돌릴 수 없어.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('기록 삭제')),
                ],
              ),
            );
            if (approved == true) await widget.onClearHistory();
          },
        ),
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(
              text: '내 서재 ' + works.length.toString() +
                '개 · 완독 ' + completed.toString() +
                '개 · 누적 열람 ' + totalOpens.toString() +
                '회 · 새 독서 세션 ' + sessions.length.toString() + '회')),
          icon: const Icon(Icons.copy),
          label: const Text('통계 요약 복사'),
        ),
        const Text('앱의 JSON 백업에서 서재와 활동 기록을 함께 내보낼 수 있어. 다른 분석 서버로 열람 기록을 전송하지 않아.',
          style: TextStyle(fontSize: 11, color: HypColors.muted)),
      ]), icon: Icons.tune),
    ]);
  }
}
