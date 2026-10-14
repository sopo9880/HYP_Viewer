import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/export.dart';
import 'core/app_backup.dart';
import 'core/gallery.dart';
import 'core/cover_store.dart';
import 'core/hero_artwork_store.dart';
import 'core/reader_settings.dart';
import 'core/i18n.dart';
import 'core/reader_downloader.dart';
import 'core/announcements.dart';
import 'core/android_controls.dart';
import 'core/hitomi_reader_link.dart';
import 'core/hitomi_gallery.dart';
import 'ui/gallery_reader.dart';
import 'ui/cover_picker.dart';
import 'ui/cover_cropper.dart';
import 'ui/work_editor.dart';
import 'ui/hyp_dashboard.dart';
import 'ui/hyp_theme.dart';
import 'core/number_extractor.dart';
import 'core/candidate_verifier.dart';
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
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: HypLanguage.selected,
    builder: (context, language, _) => MaterialApp(
      title: 'HYP Viewer',
      locale: Locale(language),
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: HypTheme.dark,
      themeMode: ThemeMode.dark,
      home: const LibraryHome(),
    ),
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
  final Completer<void> _initialLibraryRead = Completer<void>();
  bool _libraryReadFailed = false;
  final Set<String> _coverCaptures = <String>{};
  int navigationEpoch = 0;
  int libraryNavigationEpoch = 0;
  String appVersion = '—';
  final galleryStore = GalleryStore();
  final sourceSettings = OnlineSourceSettings();
  final onlineSourceInput = TextEditingController();
  CancelDownload? galleryDownloadToken;
  GalleryTransfer? readerTransfer;
  bool isReaderTransferPaused = false;
  final Queue<WorkEntry> _downloadQueue = Queue<WorkEntry>();
  final Set<String> _queuedDownloadIds = {};
  bool _downloadQueueRunning = false;
  bool _downloadQueueCancelled = false;
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
  final Map<String, CandidateVerification> _candidateCache = {};
  bool busy = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadOnlineSource();
    _loadReaderSettings();
    _loadVersionInfo();
    _loadHeroArtwork();
    _listenForSharedShorts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _automaticUpdateCheck();
      if (Platform.isAndroid) _showSecurityNoticeOnce();
    });
  }

  Future<void> _loadVersionInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => appVersion =
          'v${info.version} (build ${info.buildNumber})');
      }
    } catch (_) {
      // Test hosts and unsupported platforms may not supply package metadata.
    }
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
      HypLanguage.selected.value = result.languageCode;
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
      // Newly uploaded artwork should show up even if random mode was active.
      if (readerSettings.heroArtworkSource != 'custom') {
        await _saveReaderSettings(
            readerSettings.copyWith(heroArtworkSource: 'custom'));
      }
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
      HypLanguage.selected.value = updated.languageCode;
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
      // An ACTION_SEND may arrive before async JSON startup has finished.
      // Saving the empty initial UI state would wipe the real library.
      await _initialLibraryRead.future;
      if (_libraryReadFailed) {
        throw StateError('서재 파일 읽기 오류가 해결되기 전에는 저장할 수 없어.');
      }
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
          title: const HypText('HYP Viewer 관리자 공지'),
          content: SizedBox(
            width: 480,
            height: 330,
            child: ListView.separated(
              itemCount: notices.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final n = notices[index];
                return ListTile(
                  title: HypText(n.title),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: HypText(n.message),
                  ),
                  isThreeLine: true,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const HypText('확인'),
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
        title: const HypText('안드로이드 설치 보안 안내'),
        content: const HypText(
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
              child: const HypText('알겠어')),
          if (Platform.isAndroid)
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.settings),
              label: const HypText('보안 설정 확인'),
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
      // Old backups may contain one gallery linked from several different
      // Shorts. Consolidate by work ID while retaining favorites and progress.
      final normalized = LibraryBackup.merge(
        const LibraryBackup(works: [], collections: []), data);
      if (mounted) setState(() => library = normalized);
    } catch (e) {
      _libraryReadFailed = true;
      _status('기존 서재 읽기 실패: ' + e.toString() +
          ' / 데이터 보호를 위해 새 서재 저장을 잠갔어. '
          '원본과 .previous 파일을 확인해줘.');
    } finally {
      if (!_initialLibraryRead.isCompleted) _initialLibraryRead.complete();
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

  Future<Map<String, CandidateVerification>> _verifyCandidateCodes(
      List<String> codes) async {
    final client = http.Client();
    try {
      return await GalleryCandidateVerifier(client, cache: _candidateCache)
          .verifyBatch(codes);
    } finally {
      client.close();
    }
  }

  Future<void> _saveWork() =>
      _saveSelectedWorks([numberInput.text.trim()]);

  Future<void> _quickAddNumber(String code) async {
    // The top search field accepts either a Shorts URL or a gallery ID.
    // A numeric entry must never be sent to YouTube as a video URL.
    urlInput.text = code;
    numberInput.text = code;
    titleInput.clear();
    authorInput.clear();
    commentInput.clear();
    await _saveSelectedWorks([code]);
  }

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
    WorkEntry? openAfterSave;
    try {
      final videoId = ShortsLink.videoId(urlInput.text) ?? '';
      final works = <WorkEntry>[];
      var unknownTitles = 0;
      for (final code in codes) {
        var title = codes.length == 1 ? titleInput.text.trim() : '';
        // Reuse titles from the existence check: don't refetch the same
        // metadata for each selected work while saving a batch.
        final verified = _candidateCache[code];
        if (title.isEmpty && verified?.exists == true) {
          title = verified!.title;
        }
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
      if (mounted) setState(() => libraryNavigationEpoch++);
      if (readerSettings.openAfterSave && works.length == 1) {
        openAfterSave = works.single;
      }
      if (readerSettings.autoCoverEnabled) {
        for (final work in works) {
          unawaited(_prepareAutomaticCover(work));
        }
      }
      if (readerSettings.autoDownloadOnSave) {
        unawaited(_enqueueDownloads(works));
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
    if (openAfterSave != null && mounted) {
      final entry = openAfterSave;
      if (await galleryStore.exists(entry.workId)) {
        await _openGallery(entry);
      } else {
        await _readOnline(entry);
      }
    }
  }

  Future<void> _editWorkDetails(WorkEntry current) async {
    if (!mounted || downloadingGalleryKey == current.key) return;
    final draft = await showDialog<WorkEditDraft>(
      context: context,
      builder: (ctx) => WorkEditorDialog(
        work: current,
        checkWorkId: (id) async {
          final found = await _verifyCandidateCodes([id]);
          return found[id] ??
              const CandidateVerification(CandidateCheck.unavailable);
        },
      ),
    );
    if (draft == null || !mounted) return;
    final changedId = draft.workId != current.workId;
    final duplicate = changedId &&
        library.works.any((w) => w.workId == draft.workId);
    if (duplicate) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const HypText('중복 작품 번호 발견'),
          content: const HypText('새 번호가 이미 서재에 있어. '
              '기존 즐겨찾기·진행도·컬렉션을 합치고 두 작품을 병합할까? '
              'CBZ와 표지 파일은 자동으로 옮기지 않아.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const HypText('취소')),
            FilledButton(
              key: const Key('edit-work-approve-merge'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const HypText('두 작품 병합')),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    final resetCover = changedId && !duplicate &&
        current.coverMode != 'preset';
    final edited = current.copyWith(
      workId: draft.workId, title: draft.title,
      author: draft.author, originalComment: draft.originalComment,
      coverMode: resetCover
          ? (readerSettings.autoCoverEnabled ? 'auto' : 'preset')
          : current.coverMode,
      coverPage: resetCover ? 1 : current.coverPage,
    );
    try {
      await _commitLibrary((latest) => latest.editWork(
        originalWorkId: current.workId,
        edited: edited, mergeDuplicate: duplicate,
      ));
      if (!mounted) return;
      setState(() => coverEpoch++);
      if (changedId && !duplicate && readerSettings.autoCoverEnabled) {
        unawaited(_prepareAutomaticCover(edited));
      }
      _status(changedId
          ? '번호를 변경했어. 기존 CBZ·표지는 원래 번호에 보존했어.'
          : '작품 정보를 수정했어.');
    } catch (error) {
      _status('작품 정보 수정 실패: ' + error.toString());
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
      Uint8List data;
      if (excel) {
        data = LibraryExport.xlsx(library);
      } else {
        var includeLibrary = true;
        var includeSettings = true;
        var includeImages = false;
        final choices = await showDialog<List<bool>>(
          context: context,
          builder: (dialog) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
              title: const HypText('JSON 통합 백업'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const HypText('서재와 앱 설정을 하나의 JSON으로 저장할 수 있어. '
                    'API 키, 기기 권한, 다운로드한 CBZ는 포함되지 않아.'),
                  CheckboxListTile(
                    key: const Key('backup-export-library'),
                    value: includeLibrary,
                    contentPadding: EdgeInsets.zero,
                    title: const HypText('서재·즐겨찾기·읽기 기록 포함'),
                    onChanged: (v) => update(() => includeLibrary = v == true),
                  ),
                  CheckboxListTile(
                    key: const Key('backup-export-settings'),
                    value: includeSettings,
                    contentPadding: EdgeInsets.zero,
                    title: const HypText('앱 설정 포함'),
                    onChanged: (v) => update(() => includeSettings = v == true),
                  ),
                  CheckboxListTile(
                    key: const Key('backup-export-images'),
                    value: includeImages,
                    contentPadding: EdgeInsets.zero,
                    title: const HypText('표지·배너 이미지 포함 (선택)'),
                    subtitle: const HypText('크기가 커질 수 있어 (최대 22MB). '
                        '표지·배너 이미지가 없는 경우 원본 파일을 복사하지 않아.'),
                    onChanged: (v) => update(() => includeImages = v == true),
                  ),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialog),
                    child: const HypText('취소')),
                FilledButton(
                  key: const Key('backup-export-confirm'),
                  onPressed: includeLibrary || includeSettings
                    ? () => Navigator.pop(dialog, [
                        includeLibrary, includeSettings, includeImages])
                    : null,
                  child: const HypText('JSON 백업 생성'),
                ),
              ],
            ),
          ),
        );
        if (choices == null || !mounted) return;
        final covers = <BackupCover>[];
        Uint8List? banner;
        if (choices[2]) {
          if (choices[1]) banner = await heroArtworkStore.read();
          if (choices[0]) {
            for (final work in library.works) {
              if (work.coverMode == 'preset') continue;
              if (covers.length >= AppBackup.maxCovers) {
                throw const FormatException(
                    '이미지 표지가 500개를 넘었어. 이미지 포함을 끄고 다시 백업해줘.');
              }
              final page = work.coverMode == 'page' ? work.coverPage : 1;
              final bytes = await coverStore.read(work.workId,
                  mode: work.coverMode, page: page);
              if (bytes != null) {
                covers.add(BackupCover(workId: work.workId,
                  mode: work.coverMode, page: page, bytes: bytes));
              }
            }
          }
        }
        data = AppBackup(
          library: library,
          settings: choices[1] ? readerSettings : null,
          includesLibrary: choices[0],
          bannerImage: banner,
          covers: covers,
        ).encode();
      }
      final extension = excel ? 'xlsx' : 'json';
      final filename = (excel ? 'HYP_Library_' : 'HYP_Backup_') +
          DateTime.now().toIso8601String().substring(0, 10) +
          '.' + extension;
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: excel ? 'Excel로 내보내기' : 'JSON으로 내보내기',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: data,
      );
      if (saved != null) _status('내보내기 완료');
    } catch (error) {
      _status('내보내기 실패: $error');
    }
  }

  Future<void> _restorePreviousLibrary() async {
    await _initialLibraryRead.future;
    if (!mounted) return;
    try {
      final previous = await storage.readPrevious();
      if (previous == null) {
        _status('이전에 저장된 서재 백업(.previous)이 없어.');
        return;
      }
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const HypText('이전 서재 백업 복구'),
          content: HypText('이전 저장본에 작품 ${previous.works.length}개가 있어. '
              '현재 서재를 이 저장본으로 교체할까? 복구 전에 현재 '
              '서재를 JSON으로 내보내 두는 걸 추천해.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const HypText('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const HypText('이전 서재 복구')),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      // This is the only explicit recovery path that re-enables a load
      // failure. A previous file must have decoded successfully above.
      if (_libraryReadFailed) {
        await storage.save(previous);
        _libraryReadFailed = false;
        if (mounted) setState(() => library = previous);
      } else {
        await _commitLibrary((_) => previous);
      }
      if (mounted) setState(() => libraryNavigationEpoch++);
      _status('이전 저장본에서 ${previous.works.length}개 작품을 복구했어.');
    } catch (error) {
      _status('이전 서재 복구 실패: $error');
    }
  }

  Future<void> _import() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true,
      );
      if (picked == null) return;
      final file = picked.files.single;
      if (file.size > AppBackup.maxJsonBytes) {
        throw const FormatException('JSON 백업은 최대 40MB까지 지원해.');
      }
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) throw Exception('파일을 읽지 못했어.');
      final incoming = AppBackup.decode(utf8.decode(bytes));
      if (!mounted) return;

      var mode = incoming.includesLibrary
          ? AppRestoreMode.addWorks : AppRestoreMode.replaceSettings;
      var destructiveApproved = false;
      final selected = await showDialog<AppRestoreMode>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const HypText('JSON 백업 복원'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 530),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  HypText('백업 작품: ' +
                      incoming.library.works.length.toString() + '개'),
                  HypText(incoming.hasSettings
                      ? '앱 설정 포함됨' : '앱 설정 없음 (기존 형식)'),
                  if (incoming.hasImages)
                    const HypText('표지·배너 이미지 포함됨'),
                  const SizedBox(height: 10),
                  ListTile(
                    key: const Key('backup-mode-add'),
                    enabled: incoming.includesLibrary,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(mode == AppRestoreMode.addWorks
                        ? Icons.radio_button_checked : Icons.radio_button_off),
                    title: const HypText('① 작품 추가'),
                    subtitle: const HypText('기존 서재와 설정을 유지하고 작품만 병합'),
                    onTap: incoming.includesLibrary ? () => update(() {
                      mode = AppRestoreMode.addWorks;
                      destructiveApproved = false;
                    }) : null,
                  ),
                  ListTile(
                    key: const Key('backup-mode-settings'),
                    enabled: incoming.hasSettings,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(mode == AppRestoreMode.replaceSettings
                        ? Icons.radio_button_checked : Icons.radio_button_off),
                    title: const HypText('② 설정 덮어쓰기'),
                    subtitle: const HypText('작품 목록은 유지하고 앱 설정만 교체'),
                    onTap: incoming.hasSettings ? () => update(() {
                      mode = AppRestoreMode.replaceSettings;
                      destructiveApproved = false;
                    }) : null,
                  ),
                  ListTile(
                    key: const Key('backup-mode-all'),
                    enabled: incoming.includesLibrary && incoming.hasSettings,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(mode == AppRestoreMode.replaceEverything
                        ? Icons.radio_button_checked : Icons.radio_button_off),
                    title: const HypText('③ 작품 + 설정 덮어쓰기'),
                    subtitle: const HypText('PC에만 있는 작품이 사라질 수 있어. '
                        '실행 전 현재 서재가 .previous에 보존돼.'),
                    onTap: incoming.includesLibrary && incoming.hasSettings
                        ? () => update(() {
                          mode = AppRestoreMode.replaceEverything;
                          destructiveApproved = false;
                        }) : null,
                  ),
                  if (mode == AppRestoreMode.replaceEverything)
                    CheckboxListTile(
                      key: const Key('backup-overwrite-confirm'),
                      contentPadding: EdgeInsets.zero,
                      title: const HypText('현재 서재를 교체한다는 점을 확인했어'),
                      value: destructiveApproved,
                      onChanged: (v) => update(
                          () => destructiveApproved = v == true),
                    ),
                  const HypText('자동 다운로드·공지 수신은 복원 후 다시 동의해야 해. '
                      'CBZ와 기기별 권한 및 API 키는 복원하지 않아.',
                      style: TextStyle(fontSize: 12)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                  child: const HypText('취소')),
              FilledButton(
                key: const Key('backup-import-confirm'),
                onPressed: mode != AppRestoreMode.replaceEverything ||
                        destructiveApproved
                    ? () => Navigator.pop(dialog, mode) : null,
                child: const HypText('선택한 방식으로 복원'),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      await _initialLibraryRead.future;
      await _libraryWrites;
      if (_libraryReadFailed) {
        throw StateError('서재 복구가 필요해. 현재 백업을 안전하게 읽을 때까지 '
            'JSON 덮어쓰기를 차단했어.');
      }
      final previousLibrary = library;
      final previousSettings = readerSettings;
      final plan = AppRestorePlan.build(
          library, readerSettings, incoming, selected);

      // First write new settings, then commit library atomically. If a
      // library write fails, roll the settings back; library storage itself
      // preserves .previous during a completed replacement.
      if (plan.settings != null) {
        await readerSettingsStorage.save(plan.settings!);
      }
      try {
        if (plan.changesLibrary) {
          await _commitLibrary((latest) => AppRestorePlan.build(
              latest, previousSettings, incoming, selected).library);
        }
      } catch (_) {
        if (plan.settings != null) {
          await readerSettingsStorage.save(previousSettings);
        }
        rethrow;
      }
      if (plan.settings != null) {
        setState(() => readerSettings = plan.settings!);
        HypLanguage.selected.value = plan.settings!.languageCode;
        _syncNoticesTimer();
      }
      final imageErrors = await _restoreBackupImages(
          incoming, selected, previousLibrary);
      if (mounted && plan.changesLibrary) {
        setState(() => libraryNavigationEpoch++);
      }
      if (mounted) setState(() => coverEpoch++);
      _status(imageErrors == 0
          ? 'JSON 복원이 완료됐어.'
          : '서재·설정 복원 완료. 이미지 $imageErrors개는 복원에 실패했어.');
    } catch (error) {
      _status('복원 실패: $error');
    }
  }

  Future<int> _restoreBackupImages(AppBackup incoming,
      AppRestoreMode mode, LibraryBackup before) async {
    if (!incoming.hasImages) return 0;
    var failures = 0;
    if (mode != AppRestoreMode.addWorks && incoming.bannerImage != null) {
      try {
        await heroArtworkStore.save(incoming.bannerImage!);
        if (mounted) setState(() => heroArtwork = incoming.bannerImage);
      } catch (_) {
        failures++;
      }
    }
    if (mode == AppRestoreMode.replaceSettings) return failures;
    final existingIds = before.works.map((w) => w.workId).toSet();
    for (final cover in incoming.covers) {
      final work = library.works.where(
          (w) => w.workId == cover.workId).firstOrNull;
      if (work == null || work.coverMode != cover.mode ||
          (work.coverMode == 'page' && work.coverPage != cover.page)) {
        continue;
      }
      try {
        if (mode == AppRestoreMode.addWorks &&
            existingIds.contains(work.workId) &&
            await coverStore.exists(cover.workId,
                mode: cover.mode, page: cover.page)) {
          continue;
        }
        await coverStore.save(cover.workId, cover.bytes,
            mode: cover.mode, page: cover.page);
      } catch (_) {
        failures++;
      }
    }
    return failures;
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
      final missingTitle =
          work.title.isEmpty || work.title == '작품 ${work.workId}';
      if (missingTitle && remote.title.trim().isNotEmpty) {
        await _updateWork(work.copyWith(title: remote.title.trim()));
      }
      final readerWork = work.copyWith(
        currentPage: work.currentPage.clamp(1, remote.pageCount).toInt(),
        title: missingTitle && remote.title.trim().isNotEmpty
            ? remote.title.trim() : work.title,
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
          onVerticalScrollingChanged: (vertical) {
            unawaited(_saveReaderSettings(
                readerSettings.copyWith(verticalScrolling: vertical)));
          },
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
        title: const HypText('웹 리더 시작 페이지'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HypText('1페이지는 #1-, 2페이지부터는 #2-3처럼 열어. '
                '외부 브라우저에서 넘긴 페이지는 자동 기록되지 않아.'),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('reader-page-input'),
              initialValue: input,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: HypI18n.t(context, '시작 페이지')),
              onChanged: (value) => input = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const HypText('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input),
            child: const HypText('웹에서 열기'),
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

  /// A bulk/auto action requires a separate rights-consent action at the
  /// time it is enabled. No download starts merely because a work is viewed.
  Future<void> _setAutoDownload(bool enabled) async {
    if (!enabled) {
      await _saveReaderSettings(
          readerSettings.copyWith(autoDownloadOnSave: false));
      return;
    }
    if (!mounted) return;
    final accepted = await _confirmDownloadRights(
      title: '새 작품 자동 다운로드',
      message: '앞으로 서재에 추가하는 작품을 자동으로 오프라인 저장해. '
          '저장 권한이 있는 콘텐츠에만 사용해줘. '
          '이미 저장된 파일은 다시 다운로드하지 않고, '
          '다운로드는 앱이 실행 중인 동안 순서대로 진행돼.',
    );
    if (accepted) {
      await _saveReaderSettings(
          readerSettings.copyWith(autoDownloadOnSave: true));
    }
  }

  Future<bool> _confirmDownloadRights({
    required String title, required String message,
  }) async {
    var permitted = false;
    return await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: HypText(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            HypText(message),
            CheckboxListTile(
              key: const Key('bulk-download-rights'),
              value: permitted,
              contentPadding: EdgeInsets.zero,
              title: const HypText('이 콘텐츠를 저장할 권한이 있어'),
              onChanged: (v) => update(() => permitted = v == true),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const HypText('취소')),
            FilledButton(
              onPressed: permitted ? () => Navigator.pop(dialog, true) : null,
              child: const HypText('확인')),
          ],
        ),
      ),
    ) == true;
  }

  Future<void> _downloadAllLibrary() async {
    await _initialLibraryRead.future;
    if (_libraryReadFailed || !mounted || library.works.isEmpty) return;
    final approved = await _confirmDownloadRights(
      title: '서재 전체 다운로드',
      message: '서재의 작품 ${library.works.length}개를 차례대로 다운로드할까? '
          '이미 로컬 파일이 있는 작품은 건너뛰고, 다운로드 제한이나 '
          '네트워크 오류는 우회하지 않아. 아래 확인이 필요해.',
    );
    if (!approved || !mounted) return;
    await _enqueueDownloads(library.works);
  }

  Future<void> _enqueueDownloads(Iterable<WorkEntry> works) async {
    _downloadQueueCancelled = false;
    for (final work in works) {
      if (_queuedDownloadIds.add(work.workId)) _downloadQueue.add(work);
    }
    if (mounted) {
      setState(() {});
      _status('다운로드 대기: ${_downloadQueue.length}개 작품. '
          '앱 실행 중 순서대로 다운로드해.');
    }
    unawaited(_runDownloadQueue());
  }

  Future<void> _runDownloadQueue() async {
    if (_downloadQueueRunning || galleryDownloadToken != null) return;
    _downloadQueueRunning = true;
    try {
      while (_downloadQueue.isNotEmpty && !_downloadQueueCancelled) {
        if (galleryDownloadToken != null) break;
        final work = _downloadQueue.removeFirst();
        _queuedDownloadIds.remove(work.workId);
        if (mounted) setState(() {});
        // A queued work might have been removed from the library.
        if (!library.works.any((w) => w.workId == work.workId)) continue;
        try {
          if (await galleryStore.exists(work.workId)) continue;
          await _downloadOnlineInternal(work, rightsApproved: true);
        } catch (error) {
          _status('작품 ${work.workId} 다운로드 실패: $error');
        }
      }
    } finally {
      _downloadQueueRunning = false;
    }
  }

  void _cancelAllDownloads() {
    _downloadQueueCancelled = true;
    _downloadQueue.clear();
    _queuedDownloadIds.clear();
    galleryDownloadToken?.cancel();
    if (mounted) setState(() {});
  }

  Future<void> _downloadOnline(WorkEntry work) async {
    await _downloadOnlineInternal(work);
  }

  Future<bool> _downloadOnlineInternal(
      WorkEntry work, {bool rightsApproved = false}) async {
    if (galleryDownloadToken != null) {
      _status('이미 진행 중인 다운로드가 있어. 먼저 완료하거나 취소해줘.');
      return false;
    }
    final client = http.Client();
    GalleryTransfer? transfer;
    try {
      if (rightsApproved && await galleryStore.exists(work.workId)) {
        return true;
      }
      final remote = await HitomiGalleryProvider(client).load(work.workId);
      if (!mounted || (rightsApproved && _downloadQueueCancelled)) return false;
      final existing = await galleryStore.exists(work.workId);
      if (rightsApproved && existing) return true;
      var confirmedRights = false;
      final accepted = rightsApproved ? true : await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const HypText('온라인 작품을 오프라인으로 저장'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HypText(remote.pageCount.toString() + '장의 이미지를 CBZ로 저장해. ' +
                    (existing ? '기존 오프라인 파일은 완성 후 교체돼.' :
                        '완료하면 네트워크 없이도 읽을 수 있어.')),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const HypText('이 콘텐츠를 저장할 권한이 있어'),
                  value: confirmedRights,
                  onChanged: (v) =>
                      update(() => confirmedRights = v == true),
                ),
                const HypText('다운로드는 작품별로 직접 승인해야 해. '
                    '사이트가 접근을 제한하면 우회하지 않고 실패해.',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false),
                  child: const HypText('취소')),
              FilledButton(
                onPressed: confirmedRights
                    ? () => Navigator.pop(dialog, true) : null,
                child: const HypText('다운로드'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true || !mounted) return false;
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
      return true;
    } on DownloadCancelled {
      _status('다운로드가 취소됐어. 기존 오프라인 파일은 유지했어.');
      return false;
    } catch (e) {
      _status('오프라인 저장 실패: ' + e.toString());
      return false;
    } finally {
      client.close();
      if (mounted && transfer != null) {
        setState(() {
          galleryDownloadToken = null;
          readerTransfer = null;
          downloadingGalleryKey = null;
          isReaderTransferPaused = false;
        });
        if (!_downloadQueueRunning && _downloadQueue.isNotEmpty &&
            !_downloadQueueCancelled) {
          unawaited(_runDownloadQueue());
        }
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


  /// Explicitly distinguish removing a shelf entry from deleting files.
  /// Always confirm because the library entry includes reading history.
  Future<void> _deleteWork(WorkEntry work) async {
    if (downloadingGalleryKey == work.key) {
      _status('이 작품을 다운로드 중이야. 완료하거나 취소한 뒤 삭제해줘.');
      return;
    }
    if (!library.works.any((entry) => entry.key == work.key)) {
      _status('이미 서재에서 삭제된 작품이야.');
      return;
    }
    if (!mounted) return;
    var alsoDeleteFiles = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, updateDialog) => AlertDialog(
          title: const HypText('서재에서 작품 삭제'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HypText(work.title.isNotEmpty
                    ? work.title : '작품 ${work.workId}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                HypText('작품 번호 ${work.workId}'),
                const SizedBox(height: 12),
                const HypText('서재 목록에서 제거하면 이 작품의 즐겨찾기와 '
                    '읽기 기록도 함께 제거돼. 다른 작품은 유지돼.'),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('delete-work-files-checkbox'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: alsoDeleteFiles,
                  onChanged: (checked) => updateDialog(
                    () => alsoDeleteFiles = checked == true,
                  ),
                  title: const HypText('로컬 파일도 함께 삭제'),
                  subtitle: const HypText('다운로드한 CBZ와 기기 내 표지 미리보기까지 삭제. '
                      '선택하지 않으면 파일은 남아서 작품 재등록 시 다시 사용할 수 있어.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const HypText('취소'),
            ),
            FilledButton.icon(
              key: const Key('confirm-delete-work'),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const HypText('서재에서 삭제'),
            ),
          ],
        ),
      ),
    );
    if (approved != true || !mounted) return;
    if (downloadingGalleryKey == work.key) {
      _status('다운로드가 진행 중이야. 완료 또는 취소 후 삭제해줘.');
      return;
    }
    try {
      await _commitLibrary((latest) => latest.withoutWork(work.workId));
    } catch (error) {
      _status('서재 작품 삭제 실패: $error');
      return;
    }
    if (mounted) setState(() => coverEpoch++);
    if (alsoDeleteFiles) {
      try {
        await galleryStore.delete(work.workId);
        await coverStore.deleteAllForWork(work.workId);
        _status('작품 ${work.workId}을 서재에서 제거하고 로컬 파일도 삭제했어.');
      } catch (error) {
        _status('서재 항목은 삭제했지만 로컬 파일 정리가 일부 실패했어: $error');
      }
    } else {
      _status('작품 ${work.workId}을 서재에서 삭제했어. 로컬 파일은 유지했어.');
    }
  }

  /// Remove selected shelf entries in ONE library save; local files are
  /// preserved unless the user explicitly opts into their deletion.
  Future<bool> _deleteSelectedWorks(List<String> rawIds) async {
    final selectedIds = rawIds.toSet();
    final selected = library.works.where(
        (w) => selectedIds.contains(w.workId)).toList();
    if (!mounted || selected.isEmpty) return false;
    if (selected.any((w) => downloadingGalleryKey == w.key)) {
      _status('다운로드 중인 작품은 완료하거나 취소한 뒤 삭제해줘.');
      return false;
    }
    var deleteFiles = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const HypText('선택한 작품 삭제'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('선택된 작품: ' + selected.length.toString() + '개',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                for (final work in selected.take(4))
                  Text('#' + work.workId + ' · ' + work.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (selected.length > 4)
                  Text('외 ' + (selected.length - 4).toString() + '개'),
                const SizedBox(height: 10),
                const HypText('선택한 작품의 즐겨찾기와 읽기 기록도 제거돼. '
                    '다른 작품과 컬렉션은 유지해.'),
                CheckboxListTile(
                  key: const Key('bulk-delete-files-checkbox'),
                  value: deleteFiles,
                  contentPadding: EdgeInsets.zero,
                  title: const HypText('로컬 파일도 함께 삭제'),
                  subtitle: const HypText('기본 OFF. 켜면 이 작품들의 '
                      '다운로드 파일과 표지 미리보기도 삭제해.'),
                  onChanged: (v) => update(() => deleteFiles = v == true),
                ),
              ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false),
                child: const HypText('취소')),
            FilledButton.icon(
              key: const Key('confirm-delete-selected'),
              onPressed: () => Navigator.pop(dialog, true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const HypText('선택 삭제')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return false;
    if (selected.any((w) => downloadingGalleryKey == w.key)) {
      _status('다운로드가 진행 중인 작품은 삭제할 수 없어.');
      return false;
    }
    final ids = selected.map((w) => w.workId).toSet();
    try {
      await _commitLibrary((latest) => latest.withoutWorks(ids));
    } catch (e) {
      _status('선택 삭제 실패: ' + e.toString());
      return false;
    }
    if (mounted) setState(() => coverEpoch++);
    var fileErrors = 0;
    if (deleteFiles) {
      for (final id in ids) {
        try {
          await galleryStore.delete(id);
          await coverStore.deleteAllForWork(id);
        } catch (_) {
          fileErrors++;
        }
      }
    }
    _status('선택한 작품 ' + ids.length.toString() +
        '개를 서재에서 제거했어. ' +
        (fileErrors > 0
            ? '일부 로컬 파일 정리에 실패했어.'
            : deleteFiles ? '로컬 파일도 정리했어.' : '로컬 파일은 유지했어.'));
    return true;
  }

  Future<void> _deleteOffline(WorkEntry work) async {
    if (!await galleryStore.exists(work.workId) || !mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const HypText('오프라인 파일 삭제'),
        content: const HypText('CBZ 이미지만 삭제할까? '
            '서재 기록·즐겨찾기·표지는 그대로 유지돼.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const HypText('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const HypText('파일 삭제')),
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
          title: const HypText('오프라인 다운로드'),
          content: HypText('이 작품의 이미지 ' + remote.pageCount.toString() +
              '장을 다운로드해 로컬 CBZ 파일로 저장할까?\n' +
              '본인이 저장 권한을 가진 작품만 다운로드해야 해. '
              '기존 오프라인 파일이 있다면 교체돼.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const HypText('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const HypText('다운로드')),
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
        if (_downloadQueue.isNotEmpty && !_downloadQueueRunning &&
            !_downloadQueueCancelled) {
          unawaited(_runDownloadQueue());
        }
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
          onVerticalScrollingChanged: (vertical) {
            unawaited(_saveReaderSettings(
                readerSettings.copyWith(verticalScrolling: vertical)));
          },
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
      bool install;
      if (Platform.isAndroid) {
        // Review system security settings before opening the APK installer.
        // Native Android completes only AFTER the user returns to our app.
        _status('APK 다운로드와 SHA-256 검증 완료. '
            '보안 설정을 확인한 뒤 앱으로 돌아와줘.');
        final returned = await AndroidReaderControls
            .openSecuritySettingsForUpdate();
        if (!mounted) return;
        if (!returned) {
          _status('기기 보안 설정을 열지 못했어. '
              '설정에서 직접 확인한 뒤 업데이트를 다시 시도해줘.');
          return;
        }
        install = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const HypText('보안 설정 확인 후 설치'),
            content: const HypText('보안 설정 화면에서 앱으로 돌아왔어. '
                'HYP Viewer는 보안 위험 자동 차단이나 출처 확인 기능을 '
                '자동으로 끄지 않아. 설치를 계속하면 Android의 '
                '시스템 설치 승인 화면이 열려. 계속할까?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const HypText('나중에')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                  child: const HypText('설치 화면 열기')),
            ],
          ),
        ) == true;
      } else {
        install = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const HypText('업데이트 파일 검증 완료'),
            content: const HypText('다운로드한 파일의 SHA-256을 확인했어. '
                'Windows 설치 프로그램을 열기 전에 앱을 종료할게. 계속할까?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const HypText('나중에')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                  child: const HypText('설치 시작')),
            ],
          ),
        ) == true;
      }
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
          title: HypText('업데이트 v' + next.version),
          content: HypText(next.notes.isEmpty
              ? '새 버전이 공개됐어. 설치 파일을 다운로드할까?'
              : next.notes),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const HypText('취소')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'web'),
                child: const HypText('릴리스 보기')),
            if (asset != null) FilledButton(
              onPressed: () => Navigator.pop(ctx, 'download'),
              child: HypText(Platform.isAndroid
                  ? '다운로드 → 보안 설정 확인' : '다운로드 및 검증'),
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
    heroArtwork: heroArtwork,
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
    libraryNavigationEpoch: libraryNavigationEpoch,
    appVersion: appVersion,
    downloadingUpdate: downloadingUpdate,
    updateProgress: updateProgress,
    downloadingGalleryKey: downloadingGalleryKey,
    downloadedGalleryPages: downloadedGalleryPages,
    totalGalleryPages: totalGalleryPages,
    downloadedGalleryBytes: downloadedGalleryBytes,
    onAnalyze: _analyze,
    onFetch: _fetch,
    onSaveWork: _saveWork,
    onQuickAddNumber: _quickAddNumber,
    onSaveSelectedWorks: _saveSelectedWorks,
    onVerifyCandidateCodes: _verifyCandidateCodes,
    onChooseHeroArtwork: _chooseHeroArtwork,
    onClearHeroArtwork: _clearHeroArtwork,
    onSaveOnlineSource: _saveOnlineSource,
    onExportJson: () => _export(false),
    onExportExcel: () => _export(true),
    onImportJson: _import,
    onRestorePreviousLibrary: _restorePreviousLibrary,
    onCheckRelease: () => _checkRelease(),
    onCheckAnnouncements: () => _checkAnnouncements(),
    onSecurityHelp: _showSecurityHelp,
    onOpenGallery: (work) => _openGallery(work),
    onReadOnline: _readOnline,
    onReadWebPage: _chooseWebPage,
    onDownloadOnline: _downloadOnline,
    onDownloadAll: _downloadAllLibrary,
    onSetAutoDownload: _setAutoDownload,
    queuedDownloadCount: _downloadQueue.length,
    onDownloadJsonSource: _downloadJsonSource,
    onDeleteOffline: _deleteOffline,
    onDeleteWork: _deleteWork,
    onDeleteSelectedWorks: _deleteSelectedWorks,
    onEditWorkDetails: _editWorkDetails,
    onToggleDownloadPause: _pauseOrResumeReaderDownload,
    downloadPaused: isReaderTransferPaused,
    downloadCanPause: readerTransfer != null,
    onImportGallery: _importGallery,
    onUpdateWork: _updateWork,
    onChooseCover: _chooseCover,
    onSaveReaderSettings: _saveReaderSettings,
    onOpenOriginal: _openOriginal,
    onOpenShortsInput: _openShortsInput,
    onCancelGalleryDownload: _cancelAllDownloads,
    onDismissMessage: () => setState(() => message = ''),
  );
}
