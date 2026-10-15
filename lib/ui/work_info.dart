import 'package:flutter/material.dart';

import '../core/hitomi_gallery.dart';
import '../core/i18n.dart';
import '../l10n/app_localizations.dart';
import '../core/work.dart';

/// Detailed, user-controlled metadata sheet. Offline information is always
/// available; remote fields load only on explicit refresh/open.
class WorkInfoDialog extends StatefulWidget {
  final WorkEntry work;
  final Future<GalleryInfo> Function() fetchInfo;
  final Future<void> Function(GalleryInfo) onCacheInfo;
  final Future<void> Function() onEdit;
  final Future<void> Function()? onFindOtherEditions;
  const WorkInfoDialog({
    super.key,
    required this.work,
    required this.fetchInfo,
    required this.onCacheInfo,
    required this.onEdit,
    this.onFindOtherEditions,
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
      Expanded(child: SelectableText(value.isEmpty
          ? AppLocalizations.of(context)!.workInfoUnavailable : value)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final work = widget.work;
    final total = info?.pageCount ?? work.totalPages;
    final percentage = work.completed ? 100 : total > 0
        ? (((work.currentPage - 1).clamp(0, total) / total) * 100).round()
        : null;
    return AlertDialog(
      title: Text(l.workInfoHeader),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 570),
        child: SizedBox(width: 470, child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min, children: [
              _infoLine(l.workInfoOriginalId, work.workId),
              if (work.videoUrl.isNotEmpty)
                _infoLine(l.workInfoSourceLink, work.videoUrl),
              _infoLine(l.workInfoTitle, info?.title.isNotEmpty == true
                  ? info!.title : work.title),
              _infoLine(l.workInfoAuthor, info?.author.isNotEmpty == true
                  ? info!.author : work.author),
              _infoLine(l.workInfoCircle, info?.group.isNotEmpty == true
                  ? info!.group : work.sourceGroup),
              _infoLine(l.workInfoSeries, info?.series.isNotEmpty == true
                  ? info!.series : work.sourceSeries),
              _infoLine(l.workInfoLanguage, info?.language.isNotEmpty == true
                  ? info!.language : work.sourceLanguage),
              _infoLine(l.workInfoType, info?.type.isNotEmpty == true
                  ? info!.type : work.sourceType),
              _infoLine(l.workInfoAdded, info?.date.isNotEmpty == true
                  ? info!.date : work.sourceDate),
              _infoLine(l.workInfoTags, (info?.tags ?? work.tags).join(', ')),
              _infoLine(l.workInfoCharacters, (info?.characters ?? []).join(', ')),
              _infoLine(l.workInfoPages,
                  total > 0 ? total.toString() : l.workInfoUnavailable),
              _infoLine(l.workInfoViews, l.workInfoNotProvided),
              const Divider(),
              _infoLine(l.workInfoLastOpen, work.lastOpenedAt ?? l.workInfoNoHistory),
              _infoLine(l.workInfoOpenCount, work.openCount.toString()),
              _infoLine(l.workInfoProgressLabel, percentage == null
                  ? l.workInfoFromPage(work.currentPage)
                  : l.workInfoProgress(work.currentPage, percentage)),
              _infoLine(l.workInfoAddedToLibrary, work.addedAt),
              if (error != null) ...[
                const SizedBox(height: 8),
                HypText('메타데이터 조회 실패: ' + error!,
                    style: const TextStyle(color: Colors.orangeAccent)),
              ],
              if (loading) const LinearProgressIndicator(),
            ],
          ),
        )),
      ),
      actions: [
        if (widget.onFindOtherEditions != null) TextButton.icon(
          key: const Key('work-info-find-editions'),
          icon: const Icon(Icons.language),
          label: const HypText('다른 언어판 찾기'),
          onPressed: () {
            Navigator.of(context).pop();
            widget.onFindOtherEditions!();
          },
        ),
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
