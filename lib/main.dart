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
import 'core/hero_artwork_store.dart';
import 'core/reader_settings.dart';
import 'core/reader_downloader.dart';
import 'core/announcements.dart';
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
  final heroArtworkStore = const HeroArtworkStore();
  Uint8List? heroArtwork;
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
  Timer? _noticesTimer;
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
    _loadHeroArtwork();
    _listenForSharedShorts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _automaticUpdateCheck();
      if (Platform.isAndroid) _showSecurityNoticeOnce();
    });
  }

  void _syncNoticesTimer() {
    _noticesTimer?.cancel();
    _noticesTimer = null;
    if (!readerSettings.receiveAnnouncements) return;
    _noticesTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (mounted && readerSettings.receiveAnnouncements) {
        _checkAnnouncements(silent: true);
      }
    });
  }

  Future<void> _loadReaderSettings() async {
    try {
      final result = await readerSettingsStorage.load();
      if (mounted) setState(() => readerSettings = result);
      _syncNoticesTimer();
      if (result.receiveAnnouncements) {
        unawaited(_checkAnnouncements(silent: true));
      }
    } catch (e) {
      _status('뷰어 설정 읽기 실패: ' + e.toString());
    }
  }

  Future<void> _loadHeroArtwork() async {
    try {
      final bytes = await heroArtworkStore.read();
      if (mounted) setState(() => heroArtwork = bytes);
    } catch (error) {
      _status('홈 배너 이미지 읽기 실패: $error');
    }
  }

  Future<void> _chooseHeroArtwork() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final selected = picked.files.single;
      if (selected.size > HeroArtworkStore.maxBytes) {
        throw const FormatException('배너 이미지는 최대 12MB까지 지원해.');
      }
      final bytes = selected.bytes ?? (selected.path != null
          ? await File(selected.path!).readAsBytes() : null);
      if (bytes == null) {
        throw const FormatException('선택한 이미지 파일을 읽지 못했어.');
      }
      await heroArtworkStore.save(bytes);
      if (mounted) setState(() => heroArtwork = bytes);
      _status('홈 배너 첫 번째 화면에 일러스트를 설정했어.');
    } catch (error) {
      _status('배너 이미지 설정 실패: $error');
    }
  }

  Future<void> _clearHeroArtwork() async {
    try {
      await heroArtworkStore.clear();
      if (mounted) setState(() => heroArtwork = null);
      _status('홈 배너를 기본 디자인으로 되돌렸어.');
    } catch (error) {
      _status('기본 배경 복원 실패: $error');
    }
  }

  Future<void> _saveReaderSettings(ReaderSettings updated) async {
    final wasSubscribed = readerSettings.receiveAnnouncements;
    try {
      await readerSettingsStorage.save(updated);
      if (mounted) setState(() => readerSettings = updated);
      _syncNoticesTimer();
      if (updated.receiveAnnouncements && !wasSubscribed) {
        unawaited(_checkAnnouncements(silent: true));
      }
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

  Future<File> _lastSeenNoticeFile() async {
    final root = await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return File(root.path + Platform.pathSeparator + 'announcements_last_seen.txt');
  }

  Future<void> _checkAnnouncements({bool silent = false}) async {
    if (silent && !readerSettings.receiveAnnouncements) return;
    final client = http.Client();
    try {
      final notices = await AnnouncementService(client).load();
      if (notices.isEmpty || !mounted) {
        if (!silent) _status('게시된 공지가 없어.');
        return;
      }
      final file = await _lastSeenNoticeFile();
      final latestId = notices.first.id;
      final seen = await file.exists() ? (await file.readAsString()).trim() : '';
      if (silent && seen == latestId) return;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('HYP Viewer 관리자 공지'),
          content: SizedBox(
            width: 480,
            height: 330,
            child: ListView.separated(
              itemCount: notices.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final n = notices[index];
                return ListTile(
                  title: Text(n.title),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(n.message),
                  ),
                  isThreeLine: true,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      await file.writeAsString(latestId, flush: true);
    } catch (e) {
      if (!silent) _status('관리자 공지 확인 실패: ' + e.toString());
    } finally {
      client.close();
    }
  }

  Future<void> _showSecurityHelp() async {
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('안드로이드 설치 보안 안내'),
        content: const Text(
          '삼성 갤럭시의 보안 위험 자동 차단 기능은 일부 APK 설치를 '
          '막을 수 있어. 이는 기기를 보호하는 중요한 기능이야.\\n\\n'
          '앱에서는 보안 차단을 자동 해제할 수 없어. '
          '설치에 문제가 있다면 APK의 게시자, GitHub 릴리스 주소, '
          'SHA-256 체크섬을 먼저 확인하고, '
          '기기의 보안 설정은 직접 검토해줘. '
          '보호 기능을 끄는 것은 권장하지 않아.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('알겠어')),
          if (Platform.isAndroid)
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.settings),
              label: const Text('보안 설정 확인'),
            ),
        ],
      ),
    );
    if (open == true) {
      final didOpen = await AndroidReaderControls.openSecuritySettings();
      if (!didOpen) _status('이 기기에서는 보안 설정 화면을 열 수 없어.');
    }
  }

  Future<void> _showSecurityNoticeOnce() async {
    try {
      final root = await getApplicationSupportDirectory();
      final marker = File(root.path + Platform.pathSeparator +
          'security_install_help_seen.txt');
      if (await marker.exists()) return;
      await marker.writeAsString('shown', flush: true);
      if (mounted) await _showSecurityHelp();
    } catch (_) {
      // Security help is informational and never blocks launching.
    }
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
      // Shorts titles often describe multiple DIFFERENT works; their real
      // titles are fetched individually when the user saves the codes.
      titleInput.clear();
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

  Future<void> _saveWork() =>
      _saveSelectedWorks([numberInput.text.trim()]);

  Future<void> _saveSelectedWorks(List<String> selectedCodes) async {
    if (busy) return;
    final codes = selectedCodes.map((code) => code.trim()).toSet().toList();
    if (codes.isEmpty ||
        codes.any((code) => !RegExp(r'^\d{1,12}$').hasMatch(code))) {
      _status('번호는 숫자 1~12자리로 입력해줘.');
      return;
    }
    setState(() => busy = true);
    final client = http.Client();
    try {
      final videoId = ShortsLink.videoId(urlInput.text) ?? '';
      final works = <WorkEntry>[];
      var unknownTitles = 0;
      for (final code in codes) {
        var title = codes.length == 1 ? titleInput.text.trim() : '';
        if (title.isEmpty) {
          try {
            title = await HitomiGalleryProvider(client).fetchTitle(code);
          } catch (_) {
            // A missing or offline metadata server must not lose a saved ID.
          }
        }
        if (title.isEmpty) {
          title = '작품 $code';
          unknownTitles += 1;
        }
        works.add(WorkEntry.create(
          workId: code,
          videoId: videoId,
          videoUrl: videoId.isEmpty
              ? '' : 'https://www.youtube.com/shorts/$videoId',
          title: title,
          author: codes.length == 1 ? authorInput.text : '',
          originalComment: commentInput.text,
        ).copyWith(
          coverMode: readerSettings.autoCoverEnabled ? 'auto' : 'preset',
        ));
      }
      await _commitLibrary((latest) => LibraryBackup.merge(latest,
          LibraryBackup(works: works, collections: const [])));
      if (readerSettings.autoCoverEnabled) {
        for (final work in works) {
          unawaited(_prepareAutomaticCover(work));
        }
      }
      _status('작품 ${works.length}개를 서재에 저장했어.' +
          (unknownTitles > 0
              ? ' 제목을 찾지 못한 $unknownTitles개는 임시 이름으로 저장했어.'
              : ''));
    } catch (error) {
      _status('저장 실패: $error');
    } finally {
      client.close();
      if (mounted) setState(() => busy = false);
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

  Future<void> _saveCroppedCover(
      WorkEntry work, Uint8List source, {int page = 1}) async {
    if (!mounted) return;
    final cropped = await showCoverCropper(context, source);
    if (cropped == null || !mounted) return;
    await coverStore.save(work.workId, cropped, mode: 'custom');
    await _updateWork(work.copyWith(coverMode: 'custom', coverPage: page));
    if (mounted) {
      setState(() => coverEpoch++);
      _status('보이는 영역을 작품 표지로 저장했어.');
    }
  }

  Future<void> _usePageAsCover(
      WorkEntry work, int page, Uint8List bytes) async {
    try {
      await _saveCroppedCover(work, bytes, page: page);
    } catch (e) {
      _status('표지 변경 실패: ' + e.toString());
    }
  }

  Future<void> _chooseCover(WorkEntry work) async {
    final choice = await showCoverPicker(context, work);
    if (choice == null || !mounted) return;
    try {
      if (choice.mode == 'upload') {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
          withData: true,
        );
        if (picked == null || picked.files.isEmpty) return;
        final chosen = picked.files.single;
        if (chosen.size > GalleryArchive.maxSingleImageBytes) {
          throw const FormatException('이미지 파일은 최대 35MB까지 지원해.');
        }
        final bytes = chosen.bytes ??
            (chosen.path != null ? await File(chosen.path!).readAsBytes() : null);
        if (bytes == null) throw const FormatException('선택한 이미지를 읽지 못했어.');
        await _saveCroppedCover(work, bytes);
      } else if (choice.mode == 'page') {
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
          await _saveCroppedCover(work, bytes, page: choice.page);
        } finally {
          client.close();
        }
      } else {
        await _updateWork(work.copyWith(
          coverMode: choice.mode,
          coverPreset: choice.preset,
          coverPage: choice.page,
        ));
        if (mounted) setState(() => coverEpoch++);
        if (choice.mode == 'auto' && readerSettings.autoCoverEnabled &&
            !await coverStore.exists(work.workId)) {
          unawaited(_prepareAutomaticCover(work));
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
          onDownloadOffline: () => _downloadOnline(work),
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
      _status('이미 진행 중인 다운로드가 있어. 먼저 완료하거나 취소해줘.');
      return;
    }
    final client = http.Client();
    GalleryTransfer? transfer;
    try {
      final remote = await HitomiGalleryProvider(client).load(work.workId);
      if (!mounted) return;
      final existing = await galleryStore.exists(work.workId);
      var confirmedRights = false;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('온라인 작품을 오프라인으로 저장'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(remote.pageCount.toString() + '장의 이미지를 CBZ로 저장해. ' +
                    (existing ? '기존 오프라인 파일은 완성 후 교체돼.' :
                        '완료하면 네트워크 없이도 읽을 수 있어.')),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('이 콘텐츠를 저장할 권한이 있어'),
                  value: confirmedRights,
                  onChanged: (v) =>
                      update(() => confirmedRights = v == true),
                ),
                const Text('다운로드는 작품별로 직접 승인해야 해. '
                    '사이트가 접근을 제한하면 우회하지 않고 실패해.',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('취소')),
              FilledButton(
                onPressed: confirmedRights
                    ? () => Navigator.pop(dialog, true) : null,
                child: const Text('다운로드'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true || !mounted) return;
      transfer = GalleryTransfer();
      setState(() {
        galleryDownloadToken = transfer;
        readerTransfer = transfer;
        downloadingGalleryKey = work.key;
        downloadedGalleryPages = 0;
        downloadedGalleryBytes = 0;
        totalGalleryPages = remote.pageCount;
        isReaderTransferPaused = false;
      });
      final downloaded = await ReaderGalleryDownloader(galleryStore).download(
        work.workId, remote,
        transfer: transfer,
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
      if (mounted) setState(() => coverEpoch++);
      _status('오프라인 저장 완료! ' +
          downloaded.pageCount.toString() + '페이지를 인터넷 없이 읽을 수 있어.');
    } on DownloadCancelled {
      _status('다운로드가 취소됐어. 기존 오프라인 파일은 유지했어.');
    } catch (e) {
      _status('오프라인 저장 실패: ' + e.toString());
    } finally {
      client.close();
      if (mounted && transfer != null) {
        setState(() {
          galleryDownloadToken = null;
          readerTransfer = null;
          downloadingGalleryKey = null;
          isReaderTransferPaused = false;
        });
      }
    }
  }

  void _pauseOrResumeReaderDownload() {
    final active = readerTransfer;
    if (active == null) return;
    if (active.isPaused) {
      active.resume();
    } else {
      active.pause();
    }
    if (mounted) setState(() => isReaderTransferPaused = active.isPaused);
  }

  Future<void> _deleteOffline(WorkEntry work) async {
    if (!await galleryStore.exists(work.workId) || !mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오프라인 파일 삭제'),
        content: const Text('CBZ 이미지만 삭제할까? '
            '서재 기록·즐겨찾기·표지는 그대로 유지돼.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('파일 삭제')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await galleryStore.delete(work.workId);
      if (mounted) setState(() => coverEpoch++);
      _status('오프라인 이미지를 삭제했어. 서재 기록은 유지했어.');
    } catch (e) {
      _status('오프라인 파일 삭제 실패: ' + e.toString());
    }
  }

  Future<void> _downloadJsonSource(WorkEntry work) async {
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
    _noticesTimer?.cancel();
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
    onCheckAnnouncements: () => _checkAnnouncements(),
    onSecurityHelp: _showSecurityHelp,
    onOpenGallery: (work) => _openGallery(work),
    onReadOnline: _readOnline,
    onReadWebPage: _chooseWebPage,
    onDownloadOnline: _downloadOnline,
    onDownloadJsonSource: _downloadJsonSource,
    onDeleteOffline: _deleteOffline,
    onToggleDownloadPause: _pauseOrResumeReaderDownload,
    downloadPaused: isReaderTransferPaused,
    downloadCanPause: readerTransfer != null,
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
