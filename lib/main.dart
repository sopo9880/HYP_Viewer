import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/export.dart';
import 'core/gallery.dart';
import 'ui/gallery_reader.dart';
import 'ui/hyp_dashboard.dart';
import 'ui/hyp_theme.dart';
import 'core/number_extractor.dart';
import 'core/online_gallery.dart';
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
    theme: HypTheme.dark,
    themeMode: ThemeMode.dark,
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
  int navigationEpoch = 0;
  final galleryStore = GalleryStore();
  final sourceSettings = OnlineSourceSettings();
  final onlineSourceInput = TextEditingController();
  CancelDownload? galleryDownloadToken;
  String? downloadingGalleryKey;
  int downloadedGalleryPages = 0;
  int totalGalleryPages = 0;
  int downloadedGalleryBytes = 0;
  bool downloadingUpdate = false;
  double updateProgress = 0;
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
    _loadOnlineSource();
    _listenForSharedShorts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _automaticUpdateCheck());
  }

  Future<void> _loadOnlineSource() async {
    try {
      final pattern = await sourceSettings.load();
      if (mounted) setState(() => onlineSourceInput.text = pattern);
    } catch (e) {
      _status('온라인 소스 설정을 읽지 못했어: ' + e.toString());
    }
  }

  Future<void> _saveOnlineSource() async {
    try {
      await sourceSettings.save(onlineSourceInput.text.trim());
      _status('온라인 이미지 소스 설정을 저장했어.');
    } catch (e) {
      _status('온라인 소스 설정 오류: ' + e.toString());
    }
  }

  Future<void> _listenForSharedShorts() async {
    await SharedShorts.start((url) {
      if (!mounted) return;
      setState(() {
        urlInput.text = url;
        navigationEpoch += 1;
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

  Future<void> _touchRead(WorkEntry work, {int? page}) async {
    final matches = library.works.where((w) => w.key == work.key);
    if (matches.isEmpty) return;
    final current = matches.first;
    await _updateWork(current.copyWith(
      currentPage: page ?? current.currentPage,
      lastOpenedAt: DateTime.now().toUtc().toIso8601String(),
    ));
  }

  Future<void> _openOriginal(WorkEntry work) async {
    final uri = Uri.tryParse(work.videoUrl);
    if (uri == null || uri.scheme != 'https' ||
        !['www.youtube.com', 'youtube.com', 'm.youtube.com']
            .contains(uri.host.toLowerCase())) {
      _status('원본 쇼츠 링크가 유효하지 않아.');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  Future<void> _readOnline(WorkEntry work) async {
    final pattern = onlineSourceInput.text.trim();
    if (pattern.isEmpty) {
      _status('온라인 소스 URL 패턴을 먼저 설정해줘.');
      return;
    }
    final client = http.Client();
    try {
      final remote = await OnlineGalleryProvider(client).load(pattern, work.workId);
      if (!mounted) return;
      await _touchRead(work);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (ctx) => GalleryReader(
          work: work,
          archive: remote,
          onPageChanged: (page) {
            _touchRead(work, page: page);
          },
        )),
      );
    } catch (e) {
      _status('온라인 읽기 실패: ' + e.toString());
    } finally {
      client.close();
    }
  }

  Future<void> _downloadOnline(WorkEntry work) async {
    if (galleryDownloadToken != null) {
      _status('이미 다른 다운로드가 실행 중이야.');
      return;
    }
    final pattern = onlineSourceInput.text.trim();
    if (pattern.isEmpty) {
      _status('온라인 소스 URL 패턴을 먼저 설정해줘.');
      return;
    }
    final client = http.Client();
    CancelDownload? token;
    try {
      final remote = await OnlineGalleryProvider(client).load(pattern, work.workId);
      if (!remote.downloadAllowed) {
        _status('이 온라인 소스는 작품 다운로드를 허용하지 않아.');
        return;
      }
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('오프라인 다운로드'),
          content: Text('이 작품의 이미지 ' + remote.pageCount.toString() +
              '장을 다운로드해 로컬 CBZ 파일로 저장할까?\n' +
              '본인이 저장 권한을 가진 작품만 다운로드해야 해. '
              '기존 오프라인 파일이 있다면 교체돼.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('다운로드')),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      token = CancelDownload();
      setState(() {
        galleryDownloadToken = token;
        downloadingGalleryKey = work.key;
        downloadedGalleryPages = 0;
        totalGalleryPages = remote.pageCount;
        downloadedGalleryBytes = 0;
      });
      final archive = await OnlineGalleryDownloader(galleryStore).download(
        remote,
        cancellation: token,
        onProgress: (completed, total, bytes) {
          if (mounted) {
            setState(() {
              downloadedGalleryPages = completed;
              totalGalleryPages = total;
              downloadedGalleryBytes = bytes;
            });
          }
        },
      );
      _status('다운로드 완료: ' + archive.pageCount.toString() +
          '장. 이제 인터넷 없이도 읽을 수 있어.');
    } on DownloadCancelled {
      _status('다운로드가 취소됐어. 기존 오프라인 파일은 유지했어.');
    } catch (e) {
      _status('다운로드 실패: ' + e.toString());
    } finally {
      client.close();
      if (token != null && mounted) {
        setState(() {
          galleryDownloadToken = null;
          downloadingGalleryKey = null;
        });
      }
    }
  }

  Future<void> _importGallery(WorkEntry work) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['cbz', 'zip'],
        withData: false,
      );
      if (picked == null) return;
      final selected = picked.files.single.path;
      if (selected == null) {
        _status('선택한 파일의 경로를 읽지 못했어.');
        return;
      }
      final archive = await galleryStore.importFile(work.workId, selected);
      _status('페이지 ' + archive.pageCount.toString() + '장을 불러왔어.');
      await _openGallery(work, archive: archive);
    } catch (e) {
      _status('이미지 파일 가져오기 실패: ' + e.toString());
    }
  }

  Future<void> _openGallery(WorkEntry work, {GalleryArchive? archive}) async {
    try {
      final book = archive ?? await galleryStore.read(work.workId);
      if (!mounted) return;
      await _touchRead(work);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (ctx) => GalleryReader(
          work: work,
          archive: book,
          onPageChanged: (page) {
            _touchRead(work, page: page);
          },
        )),
      );
    } catch (e) {
      _status('읽기 실패: ' + e.toString() + ' / CBZ 또는 ZIP 파일을 먼저 연결해줘.');
    }
  }

  Future<void> _downloadInstaller(
      ReleaseUpdate release, ReleaseAsset asset) async {
    if (downloadingUpdate) return;
    final client = http.Client();
    setState(() {
      downloadingUpdate = true;
      updateProgress = 0;
      message = '설치 파일을 내려받는 중이야.';
    });
    try {
      final installer = await UpdateService(client).download(
        release,
        asset,
        onProgress: (value) {
          if (mounted) setState(() => updateProgress = value.clamp(0.0, 1.0));
        },
      );
      if (!mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('업데이트 파일 검증 완료'),
          content: const Text(
            '다운로드한 파일의 SHA-256을 확인했어. '
            'Windows는 앱을 종료한 뒤 설치하고, Android는 시스템 설치 확인창이 열려. 계속할까?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('나중에')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('설치 시작')),
          ],
        ),
      );
      if (install == true) {
        await UpdateService(client).launchInstaller(installer);
        if (Platform.isWindows) {
          exit(0);
        }
        _status('Android 설치 화면을 열었어. 시스템에서 설치를 승인해줘.');
      } else {
        _status('검증된 설치 파일을 임시 폴더에 보관했어.');
      }
    } catch (e) {
      _status('업데이트 실패: ' + e.toString());
    } finally {
      client.close();
      if (mounted) setState(() => downloadingUpdate = false);
    }
  }

  Future<void> _automaticUpdateCheck() async {
    try {
      final root = await getApplicationSupportDirectory();
      final file = File(root.path + Platform.pathSeparator + 'update_check_at.txt');
      final now = DateTime.now().toUtc();
      if (await file.exists()) {
        final last = DateTime.tryParse(await file.readAsString());
        if (last != null && now.difference(last).inHours < 24) return;
      }
      await file.writeAsString(now.toIso8601String());
      if (mounted) await _checkRelease(silent: true);
    } catch (_) {
      // Offline usage, including widget tests, must work without update checks.
    }
  }

  Future<void> _checkRelease({bool silent = false}) async {
    if (downloadingUpdate) return;
    final client = http.Client();
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final next = await UpdateService(client).latest(current);
      if (next == null) {
        if (!silent) _status('현재 더 새로운 릴리스가 없어.');
        return;
      }
      if (!mounted) return;
      final asset = next.installerFor(defaultTargetPlatform);
      final choice = await showDialog<String>(context: context, builder: (ctx) =>
        AlertDialog(
          title: Text('업데이트 v' + next.version),
          content: Text(next.notes.isEmpty
              ? '새 버전이 공개됐어. 설치 파일을 다운로드할까?'
              : next.notes),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'web'),
                child: const Text('릴리스 보기')),
            if (asset != null) FilledButton(
              onPressed: () => Navigator.pop(ctx, 'download'),
              child: const Text('다운로드 및 검증'),
            ),
          ],
        ),
      );
      if (choice == 'web') {
        await launchUrl(Uri.parse(next.url), mode: LaunchMode.externalApplication);
      } else if (choice == 'download' && asset != null) {
        await _downloadInstaller(next, asset);
      }
    } catch (e) {
      if (!silent) _status('업데이트 확인 실패: ' + e.toString());
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    for (final ctrl in [urlInput, commentInput, numberInput, titleInput, authorInput, apiKeyInput, onlineSourceInput]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HypDashboard(
    library: library,
    galleryStore: galleryStore,
    urlInput: urlInput,
    apiKeyInput: apiKeyInput,
    commentInput: commentInput,
    numberInput: numberInput,
    titleInput: titleInput,
    authorInput: authorInput,
    onlineSourceInput: onlineSourceInput,
    candidates: candidates,
    busy: busy,
    message: message,
    navigationEpoch: navigationEpoch,
    downloadingUpdate: downloadingUpdate,
    updateProgress: updateProgress,
    downloadingGalleryKey: downloadingGalleryKey,
    downloadedGalleryPages: downloadedGalleryPages,
    totalGalleryPages: totalGalleryPages,
    downloadedGalleryBytes: downloadedGalleryBytes,
    onAnalyze: _analyze,
    onFetch: _fetch,
    onSaveWork: _saveWork,
    onSaveOnlineSource: _saveOnlineSource,
    onExportJson: () => _export(false),
    onExportExcel: () => _export(true),
    onImportJson: _import,
    onCheckRelease: () => _checkRelease(),
    onOpenGallery: (work) => _openGallery(work),
    onReadOnline: _readOnline,
    onDownloadOnline: _downloadOnline,
    onImportGallery: _importGallery,
    onUpdateWork: _updateWork,
    onOpenOriginal: _openOriginal,
    onCancelGalleryDownload: () => galleryDownloadToken?.cancel(),
    onDismissMessage: () => setState(() => message = ''),
  );
}
