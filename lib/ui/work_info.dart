import 'package:flutter/material.dart';

import '../core/hitomi_gallery.dart';
import '../core/i18n.dart';
import '../core/work.dart';

/// Detailed, user-controlled metadata sheet. Offline information is always
/// available; remote fields load only on explicit refresh/open.
class WorkInfoDialog extends StatefulWidget {
  final WorkEntry work;
  final Future<GalleryInfo> Function() fetchInfo;
  final Future<void> Function(GalleryInfo) onCacheInfo;
  final Future<void> Function() onEdit;
  const WorkInfoDialog({
    super.key,
    required this.work,
    required this.fetchInfo,
    required this.onCacheInfo,
    required this.onEdit,
  });

  @override
  State<WorkInfoDialog> createState() => _WorkInfoDialogState();
}

class _WorkInfoDialogState extends State<WorkInfoDialog> {
  GalleryInfo? info;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final fetched = await widget.fetchInfo();
      if (!mounted) return;
      await widget.onCacheInfo(fetched);
      if (!mounted) return;
      setState(() => info = fetched);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _infoLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 116, child: Text(label, style:
          TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      Expanded(child: SelectableText(value.isEmpty ? '확인 불가' : value)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    final total = info?.pageCount ?? work.totalPages;
    final percentage = work.completed ? 100 : total > 0
        ? (((work.currentPage - 1).clamp(0, total) / total) * 100).round()
        : null;
    return AlertDialog(
      title: const HypText('작품 정보'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 570),
        child: SizedBox(width: 470, child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min, children: [
              _infoLine('작품 번호', work.workId),
              _infoLine('제목', info?.title.isNotEmpty == true
                  ? info!.title : work.title),
              _infoLine('작가', info?.author.isNotEmpty == true
                  ? info!.author : work.author),
              _infoLine('그룹 / 서클', info?.group.isNotEmpty == true
                  ? info!.group : work.sourceGroup),
              _infoLine('원작 / 시리즈', info?.series.isNotEmpty == true
                  ? info!.series : work.sourceSeries),
              _infoLine('언어', info?.language.isNotEmpty == true
                  ? info!.language : work.sourceLanguage),
              _infoLine('유형', info?.type.isNotEmpty == true
                  ? info!.type : work.sourceType),
              _infoLine('등록 날짜', info?.date.isNotEmpty == true
                  ? info!.date : work.sourceDate),
              _infoLine('태그', (info?.tags ?? work.tags).join(', ')),
              _infoLine('등장인물', (info?.characters ?? []).join(', ')),
              _infoLine('페이지 수', total > 0 ? '$total' : '확인 불가'),
              _infoLine('조회수', '원본 메타데이터에서 제공되지 않음'),
              const Divider(),
              _infoLine('마지막 열람', work.lastOpenedAt ?? '기록 없음'),
              _infoLine('열람 횟수', work.openCount.toString()),
              _infoLine('읽기 진행도', percentage == null
                  ? work.currentPage.toString() + '페이지부터'
                  : work.currentPage.toString() + '페이지부터 · $percentage%'),
              _infoLine('서재 추가일', work.addedAt),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text('메타데이터 조회 실패: ' + error!,
                    style: const TextStyle(color: Colors.orangeAccent)),
              ],
              if (loading) const LinearProgressIndicator(),
            ],
          ),
        )),
      ),
      actions: [
        TextButton.icon(
          key: const Key('work-info-refresh'),
          onPressed: loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: const HypText('정보 새로고침'),
        ),
        OutlinedButton.icon(
          key: const Key('work-info-edit'),
          onPressed: () async {
            Navigator.of(context).pop();
            await widget.onEdit();
          },
          icon: const Icon(Icons.edit_outlined),
          label: const HypText('정보 수정'),
        ),
        TextButton(onPressed: () => Navigator.pop(context),
            child: const HypText('닫기')),
      ],
    );
  }
}
