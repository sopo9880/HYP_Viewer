import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/candidate_verifier.dart';
import '../core/i18n.dart';
import '../core/work.dart';

/// A user's confirmed edit. Never fetch or overwrite the title implicitly.
class WorkEditDraft {
  final String workId;
  final String title;
  final String author;
  final String originalComment;

  const WorkEditDraft({
    required this.workId,
    required this.title,
    required this.author,
    required this.originalComment,
  });
}

class WorkEditorDialog extends StatefulWidget {
  final WorkEntry work;
  final Future<CandidateVerification> Function(String) checkWorkId;

  const WorkEditorDialog({
    super.key,
    required this.work,
    required this.checkWorkId,
  });

  @override
  State<WorkEditorDialog> createState() => _WorkEditorDialogState();
}

class _WorkEditorDialogState extends State<WorkEditorDialog> {
  late final TextEditingController idInput;
  late final TextEditingController titleInput;
  late final TextEditingController authorInput;
  late final TextEditingController commentInput;
  bool checking = false;
  String checkedId = '';
  CandidateVerification? verification;
  String? error;

  @override
  void initState() {
    super.initState();
    idInput = TextEditingController(text: widget.work.workId);
    titleInput = TextEditingController(text: widget.work.title);
    authorInput = TextEditingController(text: widget.work.author);
    commentInput = TextEditingController(text: widget.work.originalComment);
  }

  @override
  void dispose() {
    idInput.dispose();
    titleInput.dispose();
    authorInput.dispose();
    commentInput.dispose();
    super.dispose();
  }

  void _changedId(String _) {
    setState(() {
      checkedId = '';
      verification = null;
      error = null;
    });
  }

  Future<void> _verify() async {
    final code = idInput.text.trim();
    if (!RegExp(r'^\d{1,12}$').hasMatch(code)) {
      setState(() => error = '작품 번호는 숫자 1~12자리로 입력해줘.');
      return;
    }
    if (checking) return;
    setState(() {
      checking = true;
      error = null;
    });
    CandidateVerification result;
    try {
      result = await widget.checkWorkId(code);
    } catch (e) {
      result = CandidateVerification(
        CandidateCheck.unavailable, reason: e.toString());
    }
    if (!mounted) return;
    setState(() {
      checking = false;
      if (code == idInput.text.trim()) {
        checkedId = code;
        verification = result;
      }
    });
  }

  Future<void> _submit() async {
    final code = idInput.text.trim();
    if (!RegExp(r'^\d{1,12}$').hasMatch(code)) {
      setState(() => error = '작품 번호는 숫자 1~12자리로 입력해줘.');
      return;
    }
    if (code != widget.work.workId &&
        (checkedId != code ||
            verification?.status != CandidateCheck.verified)) {
      final acknowledged = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const HypText('번호 확인 필요'),
          content: const HypText(
              '새 작품 번호의 존재 여부를 확인하지 못했어. '
              '번호가 잘못된 채로 저장될 수 있어. 그래도 저장할까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const HypText('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const HypText('수정 내용 저장')),
          ],
        ),
      );
      if (acknowledged != true || !mounted) return;
    }
    Navigator.of(context).pop(WorkEditDraft(
      workId: code,
      title: titleInput.text.trim(),
      author: authorInput.text.trim(),
      originalComment: commentInput.text,
    ));
  }

  Widget _verificationStatus() {
    if (checking) {
      return const Row(children: [
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(
          strokeWidth: 2)),
        SizedBox(width: 8),
        HypText('번호 확인 중…'),
      ]);
    }
    if (checkedId != idInput.text.trim() || verification == null) {
      return const HypText('새 번호를 저장하기 전에 검증을 권장해.',
          style: TextStyle(fontSize: 12));
    }
    switch (verification!.status) {
      case CandidateCheck.verified:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HypText('작품 존재 확인',
                style: TextStyle(color: Colors.greenAccent)),
            if (verification!.title.isNotEmpty) ...[
              const SizedBox(height: 5),
              SelectableText(verification!.title),
              TextButton.icon(
                key: const Key('edit-work-use-found-title'),
                onPressed: () => titleInput.text = verification!.title,
                icon: const Icon(Icons.subdirectory_arrow_left),
                label: const HypText('확인된 제목 적용'),
              ),
            ],
          ]);
      case CandidateCheck.notFound:
        return const HypText('작품 미존재 (404)',
            style: TextStyle(color: Colors.orangeAccent));
      case CandidateCheck.unavailable:
        return const HypText('서버 확인 실패 · 직접 확인',
            style: TextStyle(color: Colors.amberAccent));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const HypText('작품 정보 수정'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HypText('기존 번호: #' + widget.work.workId,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              TextField(
                key: const Key('edit-work-id'),
                controller: idInput,
                onChanged: _changedId,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12)],
                decoration: InputDecoration(
                  labelText: HypI18n.t(context, '작품 번호'),
                  helperText: HypI18n.t(context,
                      '번호 변경 시 기존 CBZ/표지는 원래 번호에 남겨두고 연결하지 않아.'),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('edit-work-verify'),
                onPressed: checking ? null : _verify,
                icon: const Icon(Icons.fact_check_outlined),
                label: const HypText('번호 존재 검증'),
              ),
              const SizedBox(height: 5),
              _verificationStatus(),
              const SizedBox(height: 12),
              TextField(
                key: const Key('edit-work-title'),
                controller: titleInput,
                decoration: InputDecoration(
                    labelText: HypI18n.t(context, '작품 제목')),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('edit-work-author'),
                controller: authorInput,
                decoration: InputDecoration(
                    labelText: HypI18n.t(context, '작가')),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('edit-work-comment'),
                controller: commentInput,
                minLines: 2, maxLines: 5,
                decoration: InputDecoration(
                    labelText: HypI18n.t(context, '원본 댓글')),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                HypText(error!, style: const TextStyle(
                    color: Colors.orangeAccent)),
              ],
            ],
          )),
        ),
      ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: const HypText('취소')),
      FilledButton(
        key: const Key('edit-work-submit'),
        onPressed: checking ? null : _submit,
        child: const HypText('수정 내용 저장'),
      ),
    ],
  );
}
