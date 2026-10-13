import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/export.dart';
import 'core/number_extractor.dart';
import 'core/shares.dart';
import 'core/storage.dart';
import 'core/updates.dart';
import 'core/work.dart';
import 'core/youtube.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HypViewerApp());
}

class HypViewerApp extends StatelessWidget {
  const HypViewerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HYP Viewer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
    darkTheme: ThemeData.dark(useMaterial3: true),
    themeMode: ThemeMode.system,
    home: const LibraryHome(),
  );
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({super.key});
  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  final storage = LibraryStorage();
  final urlInput = TextEditingController();
  final commentInput = TextEditingController();
  final numberInput = TextEditingController();
  final titleInput = TextEditingController();
  final authorInput = TextEditingController();
  final apiKeyInput = TextEditingController();
  LibraryBackup library = const LibraryBackup(works: [], collections: []);
  List<NumberCandidate> candidates = [];
  bool busy = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    _load();
    _listenForSharedShorts();
  }

  Future<void> _listenForSharedShorts() async {
    await SharedShorts.start((url) {
      if (!mounted) return;
      setState(() {
        urlInput.text = url;
        candidates = [];
        commentInput.clear();
        numberInput.clear();
        titleInput.clear();
        authorInput.clear();
        message = '공유된 쇼츠 링크를 받았어. 댓글을 불러오거나 원문을 붙여넣어줘.';
      });
      if (apiKeyInput.text.trim().isNotEmpty) _fetch();
    });
  }

  Future<void> _load() async {
    try {
      final data = await storage.load();
      if (mounted) setState(() => library = data);
    } catch (e) {
      _status('기존 서재 읽기 실패: ' + e.toString());
    }
  }

  void _status(String value) {
    if (mounted) setState(() => message = value);
  }

  void _analyze() {
    setState(() {
      candidates = NumberExtractor.extract(commentInput.text, source: 'comment');
      if (candidates.length == 1) numberInput.text = candidates.first.code;
      message = candidates.isEmpty
          ? '번호를 찾지 못했어. 댓글을 확인하고 직접 입력해줘.'
          : '후보 ' + candidates.length.toString() + '개 발견. 확인 후 저장해줘.';
    });
  }

  Future<void> _fetch() async {
    final videoId = ShortsLink.videoId(urlInput.text);
    if (videoId == null) {
      _status('정확한 YouTube Shorts 링크를 입력해줘.');
      return;
    }
    if (apiKeyInput.text.trim().isEmpty) {
      _status('YouTube API 키를 입력하거나 댓글을 직접 붙여넣어줘.');
      return;
    }
    setState(() => busy = true);
    final client = http.Client();
    try {
      final data = await YoutubeClient(client).fetch(videoId, apiKeyInput.text.trim());
      titleInput.text = data.title;
      commentInput.text = [data.description, ...data.comments]
          .where((s) => s.trim().isNotEmpty).join('\n');
      _analyze();
    } catch (e) {
      _status('댓글 조회 실패: ' + e.toString());
    } finally {
      client.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveWork() async {
    final code = numberInput.text.trim();
    if (!RegExp(r'^\d{1,12}$').hasMatch(code)) {
      _status('번호는 숫자 1~12자리로 입력해줘.');
      return;
    }
    try {
      final id = ShortsLink.videoId(urlInput.text) ?? '';
      final work = WorkEntry.create(
        workId: code,
        videoId: id,
        videoUrl: id.isEmpty ? '' : 'https://www.youtube.com/shorts/' + id,
        title: titleInput.text,
        author: authorInput.text,
        originalComment: commentInput.text,
      );
      final updated = LibraryBackup.merge(library,
          LibraryBackup(works: [work], collections: const []));
      await storage.save(updated);
      setState(() => library = updated);
      _status('서재에 저장했어.');
    } catch (e) {
      _status('저장 실패: ' + e.toString());
    }
  }

  Future<void> _updateWork(WorkEntry work) async {
    try {
      final updated = LibraryBackup(
        works: library.works.map((w) => w.key == work.key ? work : w).toList(),
        collections: library.collections,
      );
      await storage.save(updated);
      setState(() => library = updated);
    } catch (e) {
      _status('변경 실패: ' + e.toString());
    }
  }

  Future<void> _export(bool excel) async {
    try {
      final data = excel ? LibraryExport.xlsx(library) : LibraryExport.json(library);
      final extension = excel ? 'xlsx' : 'json';
      final filename = 'HYP_Library_' +
          DateTime.now().toIso8601String().substring(0, 10) + '.' + extension;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: excel ? 'Excel로 내보내기' : 'JSON으로 내보내기',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: data,
      );
      if (path != null) _status('내보내기 완료');
    } catch (e) {
      _status('내보내기 실패: ' + e.toString());
    }
  }

  Future<void> _import() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true,
      );
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) throw Exception('파일을 읽지 못했어.');
      final incoming = LibraryBackup.decode(utf8.decode(bytes));
      if (!mounted) return;
      final mode = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('JSON 서재 복원'),
        content: Text('작품 ' + incoming.works.length.toString() + '개를 가져왔어.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('병합')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('전체 복원')),
        ],
      ));
      if (mode == null) return;
      final updated = mode == 'replace' ? incoming : LibraryBackup.merge(library, incoming);
      await storage.save(updated);
      if (mounted) setState(() => library = updated);
      _status('서재 가져오기 완료');
    } catch (e) {
      _status('복원 실패: ' + e.toString());
    }
  }

  Future<void> _checkRelease() async {
    final client = http.Client();
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final next = await UpdateService(client).latest(current);
      if (next == null) {
        _status('현재 더 새로운 릴리스가 없어.');
        return;
      }
      if (!mounted) return;
      final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text('업데이트 v' + next.version),
        content: Text(next.notes),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('GitHub 릴리스 열기')),
        ],
      ));
      if (approved == true) {
        await launchUrl(Uri.parse(next.url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _status('업데이트 확인 실패: ' + e.toString());
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    for (final ctrl in [urlInput, commentInput, numberInput, titleInput, authorInput, apiKeyInput]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HYP Viewer'), actions: [
        IconButton(tooltip: '업데이트 확인', onPressed: _checkRelease, icon: const Icon(Icons.system_update)),
        IconButton(tooltip: 'JSON 내보내기', onPressed: () => _export(false), icon: const Icon(Icons.file_download)),
        IconButton(tooltip: 'Excel 내보내기', onPressed: () => _export(true), icon: const Icon(Icons.table_chart)),
        IconButton(tooltip: 'JSON 가져오기', onPressed: _import, icon: const Icon(Icons.file_upload)),
      ]),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Text('쇼츠 작품 번호 찾기', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(controller: urlInput, decoration: const InputDecoration(labelText: 'YouTube Shorts 링크', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: apiKeyInput, obscureText: true, decoration: const InputDecoration(labelText: 'YouTube API 키 (선택)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: busy ? null : _fetch, icon: const Icon(Icons.download), label: const Text('설명란 및 댓글 불러오기')),
        const SizedBox(height: 10),
        TextField(controller: commentInput, minLines: 3, maxLines: 8,
          decoration: const InputDecoration(labelText: '댓글 원문 (직접 붙여넣기 가능)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(onPressed: _analyze, icon: const Icon(Icons.numbers), label: const Text('숫자 추출')),
        for (final candidate in candidates.take(20)) ListTile(
          title: Text(candidate.code),
          subtitle: Text(candidate.evidence, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.add_circle_outline),
          onTap: () => setState(() => numberInput.text = candidate.code),
        ),
        const SizedBox(height: 8),
        TextField(controller: numberInput, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '확정 작품 번호', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: titleInput, decoration: const InputDecoration(labelText: '작품 제목', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: authorInput, decoration: const InputDecoration(labelText: '작가', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: _saveWork, icon: const Icon(Icons.bookmark_add), label: const Text('서재에 저장')),
        if (busy) const LinearProgressIndicator(),
        if (message.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(message)),
        const Divider(height: 30),
        Text('내 서재 (' + library.works.length.toString() + ')',
          style: Theme.of(context).textTheme.titleLarge),
        if (library.works.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('저장된 작품이 없어.')),
        for (final work in library.works) Card(child: Column(children: [
          ListTile(title: Text(work.title.isEmpty ? work.workId : work.title),
            subtitle: Text('번호 ' + work.workId + ' / ' + work.author),
            trailing: IconButton(
              icon: Icon(work.favorite ? Icons.favorite : Icons.favorite_border),
              onPressed: () => _updateWork(work.copyWith(favorite: !work.favorite)),
            )),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            IconButton(onPressed: () => _updateWork(
              work.copyWith(currentPage: (work.currentPage - 1).clamp(1, 1000000).toInt())),
              icon: const Icon(Icons.remove_circle_outline)),
            Text('페이지 ' + work.currentPage.toString()),
            IconButton(onPressed: () => _updateWork(work.copyWith(currentPage: work.currentPage + 1)),
              icon: const Icon(Icons.add_circle_outline)),
            FilterChip(label: const Text('완독'), selected: work.completed,
              onSelected: (v) => _updateWork(work.copyWith(completed: v))),
            if (work.videoUrl.isNotEmpty) TextButton(
              onPressed: () => launchUrl(Uri.parse(work.videoUrl), mode: LaunchMode.externalApplication),
              child: const Text('원본 쇼츠')),
          ]),
        ])),
      ]),
    );
  }
}
