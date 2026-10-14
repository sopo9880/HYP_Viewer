import 'package:flutter/material.dart';

import '../core/work.dart';
import 'cover_palettes.dart';

class CoverChoice {
  final String mode;
  final int preset;
  final int page;
  const CoverChoice(this.mode, this.preset, this.page);
}

Future<CoverChoice?> showCoverPicker(
  BuildContext context, WorkEntry work,
) => showDialog<CoverChoice>(
  context: context,
  builder: (_) => _CoverPickerDialog(work: work),
);

class _CoverPickerDialog extends StatefulWidget {
  final WorkEntry work;
  const _CoverPickerDialog({required this.work});

  @override
  State<_CoverPickerDialog> createState() => _CoverPickerDialogState();
}

class _CoverPickerDialogState extends State<_CoverPickerDialog> {
  late String _mode;
  late int _preset;
  late TextEditingController _page;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.work.coverMode;
    _preset = widget.work.coverPreset;
    _page = TextEditingController(text: widget.work.coverPage.toString());
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _submit() {
    final page = int.tryParse(_page.text.trim());
    if (_mode == 'page' && (page == null || page < 1 || page > 1000000)) {
      setState(() => _error = '작품 페이지는 1 이상 숫자로 입력해줘.');
      return;
    }
    Navigator.pop(context, CoverChoice(_mode, _preset, page ?? 1));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('서재 표지 선택'),
    content: SizedBox(
      width: 450,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('기본 디자인 6종, 작품 내 원하는 페이지, 내 사진 중에서 표지를 선택할 수 있어.'),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('자동: 작품 첫 페이지'),
              subtitle: const Text('열람하면서 첫 페이지 미리보기를 생성해'),
              leading: Icon(_mode == 'auto'
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              onTap: () => setState(() => _mode = 'auto'),
            ),
            ListTile(
              title: const Text('기본 표지 디자인'),
              leading: Icon(_mode == 'preset'
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              onTap: () => setState(() => _mode = 'preset'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(CoverPalettes.colors.length, (index) {
                final shades = CoverPalettes.colors[index];
                return ChoiceChip(
                  key: Key('cover-preset-$index'),
                  label: Text(CoverPalettes.names[index]),
                  avatar: CircleAvatar(backgroundColor: shades.first,
                    child: Icon(CoverPalettes.symbols[index], size: 15,
                        color: Colors.white)),
                  selected: _mode == 'preset' && _preset == index,
                  onSelected: (_) => setState(() {
                    _mode = 'preset';
                    _preset = index;
                  }),
                );
              }),
            ),
            const SizedBox(height: 12),
            ListTile(
              key: const Key('cover-upload'),
              title: const Text('내 이미지 업로드'),
              subtitle: const Text('사진 파일을 선택한 뒤 드래그·확대해서 자르기'),
              leading: Icon(_mode == 'upload'
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              onTap: () => setState(() => _mode = 'upload'),
            ),
            ListTile(
              title: const Text('작품 내 페이지 선택'),
              subtitle: const Text('이미지 한 장을 축소해 저장 (네트워크 필요)'),
              leading: Icon(_mode == 'page'
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              onTap: () => setState(() => _mode = 'page'),
            ),
            TextField(
              key: const Key('cover-page-input'),
              controller: _page,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '표지로 사용할 페이지 번호',
                hintText: '예: 5',
              ),
              onTap: () => setState(() => _mode = 'page'),
              onChanged: (_) {
                if (_mode != 'page') setState(() => _mode = 'page');
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 12),
            const Text(
              '선택한 페이지 번호는 JSON 백업에 저장돼. '
              '썸네일 이미지 파일은 기기 내부에 저장되므로 다른 기기로 옮기면 다시 생성해야 해.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('취소')),
      FilledButton(
        key: const Key('cover-picker-apply'),
        onPressed: _submit,
        child: const Text('표지 적용'),
      ),
    ],
  );
}
