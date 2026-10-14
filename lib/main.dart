import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/export.dart';
import 'core/gallery.dart';
import 'core/cover_store.dart';
import 'core/reader_settings.dart';
import 'core/reader_downloader.dart';
import 'core/android_controls.dart';
import 'core/hitomi_reader_link.dart';
import 'core/hitomi_gallery.dart';
import 'ui/gallery_reader.dart';
import 'ui/cover_picker.dart';
import 'ui/cover_cropper.dart';
import 'ui/hyp_dashboard.dart';
import 'ui/hyp_theme.dart';
import 'core/number_extractor.dart';
import 'core/online_gallery.dart';
import 'core/shares.dart';
import 'core/storage.dart';
import 'core/updates.dart';
import 'core/work.dart';
import 'core/youtube.dart';
import 'core/youtube_public.dart';

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
  final coverStore = const CoverStore();
  final readerSettingsStorage = const ReaderSettingsStorage();
  ReaderSettings readerSettings = const ReaderSettings();
  int coverEpoch = 0;
  Future<void> _libraryWrites = Future<void>.value();
  final Set<String> _coverCaptures = <String>{};
  int navigationEpoch = 0;
  final galleryStore = GalleryStore();
  final sourceSettings = OnlineSourceSettings();
  final onlineSourceInput = TextEditingController();
  CancelDownload? galleryDownloadToken;
  GalleryTransfer? readerTransfer;
  bool isReaderTransferPaused = false;
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
    _loadReaderSettings();
    _listenForSharedShorts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _automaticUpdateCheck());
  }

  Future<void> _loadReaderSettings() async {
    try {
      final result = await readerSettingsStorage.load();
      if (mounted) setState(() => readerSettings = result);
    } catch (e) {
      _status('뷰어 설정 읽기 실패: ' + e.toString());
    }
  }

  Future<void> _saveReaderSettings(ReaderSettings updated) async {
    try {
      await readerSettingsStorage.save(updated);
      if (mounted) setState(() => readerSettings = updated);
    } catch (e) {
      _status('뷰어 설정 저장 실패: ' + e.toString());
    }
  }

  /// Apply a mutation to the latest library, not to an old snapshot captured
  /// before an earlier asynchronous save finished.
  Future<void> _commitLibrary(
    LibraryBackup Function(LibraryBackup) change,
  ) {
    final task = _libraryWrites.then((_) async {
      final updated = change(library);
      await storage.save(updated);
      if (mounted) setState(() => library = updated);
    });
    _libraryWrites = task.then<void>((_) {},
        onError: (Object _, StackTrace __) {});
    return task;
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
        message = '쇼츠 링크를 받았어. 공개 댓글을 자동으로 조회할게.';
      });
      _fetch();
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
    setState(() => busy = true);
    final client = http.Client();
    try {
      final key = apiKeyInput.text.trim();
      final data = key.isEmpty
          ? await YoutubePublicClient(client).fetch(videoId)
          : await YoutubeClient(client).fetch(videoId, key);
      titleInput.text = data.title;
      commentInput.text = [data.description, ...data.comments]
          .where((s) => s.trim().isNotEmpty).join('\n');
      _analyze();
      if (data.comments.isEmpty) {
        _status('영상 설명란은 읽었지만 공개 댓글을 가져오지 못했어. '
            '댓글이 필요하면 유튜브에서 직접 복사해줘.');
      }
    } catch (e) {
      _status('댓글 자동 조회 실패: ' + e.toString() +
          ' / 유튜브에서 댓글을 복사해 직접 붙여넣을 수 있어.');
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
      await _commitLibrary((latest) => LibraryBackup.merge(latest,
          LibraryBackup(works: [work], collections: const [])));
      // Start preparing the first-page thumbnail, without blocking Save.
      if (readerSettings.autoCoverEnabled) {
        unawaited(_prepareAutomaticCover(work));
      }
      _status('서재에 저장했어.');
    } catch (e) {
      _status('저장 실패: ' + e.toString());
    }
  }

  Future<void> _updateWork(WorkEntry work) async {
    try {
      await _commitLibrary((latest) => LibraryBackup(
        works: latest.works.map((w) {
          if (w.key != work.key) return w;
          // Do not roll back recently updated reading progress when a
          // bookmark/cover action arrives while an earlier save is in flight.
          return work.copyWith(
            currentPage: w.currentPage,
            lastOpenedAt: w.lastOpenedAt,
          );
        }).toList(),
        collections: latest.collections,
      ));
    } catch (e) {
      _status('변경 실패: ' + e.toString());
    }
  }

  Future<void> _touchRead(WorkEntry work, {int? page}) async {
    try {
      await _commitLibrary((latest) => LibraryBackup(
        works: latest.works.map((w) => w.key == work.key
            ? w.copyWith(
                currentPage: page ?? w.currentPage,
                lastOpenedAt: DateTime.now().toUtc().toIso8601String(),
              )
            : w).toList(),
        collections: latest.collections,
      ));
    } catch (e) {
      _status('읽기 기록 저장 실패: ' + e.toString());
    }
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

  Future<void> _openShortsInput() async {
    final id = ShortsLink.videoId(urlInput.text);
    if (id == null) {
      _status('정확한 YouTube Shorts 링크를 입력해줘.');
      return;
    }
    try {
      final opened = await launchUrl(
        Uri.parse('https://www.youtube.com/shorts/$id'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('유튜브 앱이나 브라우저를 열지 못했어.');
      _status('유튜브에서 댓글을 복사한 다음 앱에 붙여넣어줘.');
    } catch (e) {
      _status('유튜브 열기 실패: ' + e.toString());
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
      await _commitLibrary((latest) =>
          mode == 'replace' ? incoming : LibraryBackup.merge(latest, incoming));
      _status('서재 가져오기 완료');
    } catch (e) {
      _status('복원 실패: ' + e.toString());
    }
  }

  Future<void> _prepareAutomaticCover(WorkEntry work) async {
    if (!readerSettings.autoCoverEnabled || work.coverMode != 'auto') return;
    final client = http.Client();
    try {
      if (await coverStore.exists(work.workId)) return;
      final GalleryPageSource source =
          await galleryStore.exists(work.workId)
              ? await galleryStore.read(work.workId)
              : await HitomiGalleryProvider(client).load(work.workId);
      final first = await source.loadPage(0);
      await _captureAutomaticCover(work, 1, first);
    } catch (_) {
      // Unavailable remote thumbnails must never prevent saving a work.
    } finally {
      client.close();
    }
  }

  Future<void> _captureAutomaticCover(
      WorkEntry work, int page, Uint8List bytes) async {
    if (!readerSettings.autoCoverEnabled ||
        page != 1 || work.coverMode != 'auto' ||
        !_coverCaptures.add(work.workId)) return;
    try {
      if (!await coverStore.exists(work.workId)) {
        await coverStore.save(work.workId, bytes);
        if (mounted) setState(() => coverEpoch++);
      }
    } catch (_) {
      // Image reading remains usable even if generating a cover fails.
    } finally {
      _coverCaptures.remove(work.workId);
    }
  }

  Future<void> _usePageAsCover(
      WorkEntry work, int page, Uint8List bytes) async {
    await coverStore.save(work.workId, bytes, mode: 'page', page: page);
    await _updateWork(work.copyWith(coverMode: 'page', coverPage: page));
    if (mounted) {
      setState(() => coverEpoch++);
      _status('작품 ' + page.toString() + '페이지를 서재 표지로 설정했어.');
    }
  }

  Future<void> _chooseCover(WorkEntry work) async {
    final choice = await showCoverPicker(context, work);
    if (choice == null || !mounted) return;
    final mode = choice.mode;
    try {
      if (mode == 'page') {
        final client = http.Client();
        try {
          final GalleryPageSource gallery =
              await galleryStore.exists(work.workId)
                  ? await galleryStore.read(work.workId)
                  : await HitomiGalleryProvider(client).load(work.workId);
          if (choice.page > gallery.pageCount) {
            throw FormatException('전체 ' + gallery.pageCount.toString() +
                '페이지 중에서 선택해야 해.');
          }
          final bytes = await gallery.loadPage(choice.page - 1);
          await _usePageAsCover(work, choice.page, bytes);
        } finally {
          client.close();
        }
      } else {
        await _updateWork(work.copyWith(
          coverMode: mode, coverPreset: choice.preset,
          coverPage: choice.page,
        ));
        if (mounted) setState(() => coverEpoch++);
        if (mode == 'auto' && !await coverStore.exists(work.workId)) {
          final client = http.Client();
          try {
            final GalleryPageSource gallery =
                await galleryStore.exists(work.workId)
                    ? await galleryStore.read(work.workId)
                    : await HitomiGalleryProvider(client).load(work.workId);
            await coverStore.save(work.workId, await gallery.loadPage(0));
            if (mounted) setState(() => coverEpoch++);
          } catch (_) {
            _status('자동 표지를 선택했어. 첫 페이지를 열면 미리보기를 생성할게.');
          } finally {
            client.close();
          }
        }
      }
    } catch (e) {
      _status('표지 설정 실패: ' + e.toString());
    }
  }

  /// Stream images in the shared Flutter reader; no JSON URL setup required.
  /// If the remote source blocks the client, the web-reader action is available.
  Future<void> _readOnline(WorkEntry work) async {
    final client = http.Client();
    try {
      final remote = await HitomiGalleryProvider(client).load(work.workId);
      if (!mounted) return;
      await _touchRead(work);
      final readerWork = work.copyWith(
        currentPage: work.currentPage.clamp(1, remote.pageCount).toInt(),
        title: work.title.isEmpty ? remote.title : work.title,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (ctx) => GalleryReader(
          work: readerWork,
          archive: remote,
          onPageChanged: (page) { _touchRead(work, page: page); },
          onOpenInBrowser: (page) => _openWebReader(work, page: page),
          settings: readerSettings,
          onPageLoaded: (page, bytes) {
            unawaited(_captureAutomaticCover(work, page, bytes));
          },
          onChooseCover: (page, bytes) => _usePageAsCover(work, page, bytes),
        )),
      );
    } catch (e) {
      _status('앱 내 온라인 읽기 실패: ' + e.toString() +
          ' / 작품 메뉴의 웹 리더로 열기를 이용할 수 있어.');
    } finally {
      client.close();
    }
  }

  Future<void> _openWebReader(WorkEntry work, {int? page}) async {
    final currentPage = page ?? work.currentPage;
    try {
      final uri = HitomiReaderLink.forWork(work.workId, page: currentPage);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('웹 브라우저를 실행하지 못했어.');
      await _touchRead(work, page: currentPage);
      _status('웹 리더를 열었어. 브라우저에서 넘긴 페이지는 앱에 자동 저장되지 않아.');
    } catch (e) {
      _status('웹 리더 열기 실패: ' + e.toString());
    }
  }

  Future<void> _chooseWebPage(WorkEntry work) async {
    var input = work.currentPage.toString();
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('웹 리더 시작 페이지'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1페이지는 #1-, 2페이지부터는 #2-3처럼 열어. '
                '외부 브라우저에서 넘긴 페이지는 자동 기록되지 않아.'),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('reader-page-input'),
              initialValue: input,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '시작 페이지'),
              onChanged: (value) => input = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input),
            child: const Text('웹에서 열기'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    final page = int.tryParse(selected.trim());
    if (page == null || page < 1 || page > 1000000) {
      _status('시작 페이지는 1~1000000 사이의 숫자로 입력해줘.');
      return;
    }
    await _openWebReader(work, page: page);
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
          settings: readerSettings,
          onPageLoaded: (page, bytes) {
            unawaited(_captureAutomaticCover(work, page, bytes));
          },
          onChooseCover: (page, bytes) => _usePageAsCover(work, page, bytes),
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
    coverStore: coverStore,
    coverEpoch: coverEpoch,
    readerSettings: readerSettings,
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
    onReadWebPage: _chooseWebPage,
    onDownloadOnline: _downloadOnline,
    onImportGallery: _importGallery,
    onUpdateWork: _updateWork,
    onChooseCover: _chooseCover,
    onSaveReaderSettings: _saveReaderSettings,
    onOpenOriginal: _openOriginal,
    onOpenShortsInput: _openShortsInput,
    onCancelGalleryDownload: () => galleryDownloadToken?.cancel(),
    onDismissMessage: () => setState(() => message = ''),
  );
}
