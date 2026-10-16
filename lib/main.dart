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
import 'core/cbz_exporter.dart';
import 'core/gallery.dart';
import 'core/cover_store.dart';
import 'core/hero_artwork_store.dart';
import 'core/reader_settings.dart';
import 'core/i18n.dart';
import 'l10n/app_localizations.dart';
import 'core/reader_downloader.dart';
import 'core/reader_cache_pruner.dart';
import 'core/announcements.dart';
import 'core/android_controls.dart';
import 'core/hitomi_reader_link.dart';
import 'core/hitomi_gallery.dart';
import 'ui/gallery_reader.dart';
import 'ui/cover_picker.dart';
import 'ui/cover_cropper.dart';
import 'ui/work_editor.dart';
import 'ui/work_info.dart';
import 'ui/hyp_dashboard.dart';
import 'ui/hyp_theme.dart';
import 'core/number_extractor.dart';
import 'core/candidate_verifier.dart';
import 'core/online_gallery.dart';
import 'core/online_search.dart';
import 'core/shares.dart';
import 'core/social_share_text.dart';
import 'core/storage.dart';
import 'core/updates.dart';
import 'core/work.dart';
import 'core/reading_history.dart';
import 'core/youtube.dart';
import 'core/youtube_public.dart';
import 'core/source_links.dart';
import 'core/youtube_collection.dart';
import 'core/work_edition_service.dart';
import 'core/update_prompt.dart';
import 'core/release_version.dart';
import 'core/background_download_runtime.dart';
import 'core/download_queue_store.dart';
import 'core/finder_reset_policy.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    try {
      await BackgroundDownloadRuntime.instance.configureDesktop();
    } catch (_) { /* Download attempts surface the unavailable tray. */ }
  }
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
        AppLocalizations.delegate,
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

class _LibraryHomeState extends State<LibraryHome> with WidgetsBindingObserver {
  final storage = LibraryStorage();
  final coverStore = const CoverStore();
  final heroArtworkStore = const HeroArtworkStore();
  Uint8List? heroArtwork;
  final readerSettingsStorage = const ReaderSettingsStorage();
  final readingHistoryStore = const ReadingHistoryStore();
  List<ReadingSession> readingSessions = [];
  Future<void> _historyWrites = Future<void>.value();
  ReadingActivityTracker? _activeReading;
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
  final DownloadQueueStore _downloadJobs = DownloadQueueStore();
  final BackgroundDownloadRuntime _backgroundDownloads =
      BackgroundDownloadRuntime.instance;
  final Map<String, String> _downloadSourceById = {};
  final Set<String> _queuedDownloadIds = {};
  bool _downloadQueueRunning = false;
  bool _downloadQueueCancelled = false;
  bool _restoringDownloads = false;
  Timer? _noticesTimer;
  String? downloadingGalleryKey;
  int downloadedGalleryPages = 0;
  int totalGalleryPages = 0;
  int downloadedGalleryBytes = 0;
  bool downloadingUpdate = false;
  double updateProgress = 0;
  String updateStatus = '';
  final urlInput = TextEditingController();
  final commentInput = TextEditingController();
  final numberInput = TextEditingController();
  final titleInput = TextEditingController();
  final authorInput = TextEditingController();
  final apiKeyInput = TextEditingController();
  LibraryBackup library = const LibraryBackup(works: [], collections: []);
  List<NumberCandidate> candidates = [];
  final Map<String, CandidateVerification> _candidateCache = {};
  final Map<String, String> _candidateSourceUrls = {};
  final Map<String, Set<String>> _candidateSourceEvidence = {};
  int downloadNavigationEpoch = 0;
  String activeDownloadWorkId = '';
  int finderClearEpoch = 0;
  final FinderResetPolicy _finderResetPolicy = FinderResetPolicy();

  List<String> _finderSnapshot() => [
    urlInput.text, commentInput.text, numberInput.text,
    titleInput.text, authorInput.text,
    candidates.map((candidate) => candidate.code).join('|'),
  ];

  void _openDownloadsFromNotification() {
    if (mounted) setState(() => downloadNavigationEpoch++);
  }

  void _clearSavedFinderOnTabExit() {
    if (!busy && _finderResetPolicy.consumeOnLeave(_finderSnapshot())) {
      _clearFinder();
    }
  }

  late final Future<void> _settingsLoad;
  bool _updateDismissedThisLaunch = false;
  bool _updateDialogOpen = false;
  bool busy = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadReadingHistory();
    _load();
    _loadOnlineSource();
    _settingsLoad = _loadReaderSettings();
    _loadVersionInfo();
    _loadHeroArtwork();
    _listenForSharedShorts();
    _backgroundDownloads.setDownloadsNavigationHandler(_openDownloadsFromNotification);
    unawaited(_backgroundDownloads.consumePendingDownloadsNavigation().then((open) {
      if (open && mounted) _openDownloadsFromNotification();
    }));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _automaticUpdateCheck();
      if (Platform.isAndroid) _showSecurityNoticeOnce();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _activeReading?.resume();
      // Work that failed while offline can resume after the user returns.
      // Never restart while a manual transfer or the queue is still running.
      if (!_downloadQueueRunning && galleryDownloadToken == null) {
        unawaited(_restoreDownloadQueue());
      }
    } else {
      _activeReading?.pause();
    }
  }

  Future<void> _loadReadingHistory() async {
    try {
      final saved = await readingHistoryStore.load();
      await _historyWrites;
      if (mounted) setState(() => readingSessions = saved);
    } catch (error) {
      _status('독서 활동 기록 불러오기 실패: ' + error.toString());
    }
  }

  Future<void> _commitReadingHistory(
      List<ReadingSession> Function(List<ReadingSession>) edit) {
    final task = _historyWrites.then((_) async {
      final updated = edit(readingSessions);
      if (updated.length > ReadingHistoryStore.maxSessions) {
        updated.removeRange(0, updated.length - ReadingHistoryStore.maxSessions);
      }
      await readingHistoryStore.save(updated);
      if (mounted) setState(() => readingSessions = updated);
    });
    _historyWrites = task.then<void>((_) {},
        onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<void> _finishReading(ReadingActivityTracker tracker) async {
    if (identical(_activeReading, tracker)) _activeReading = null;
    if (!readerSettings.analyticsEnabled) return;
    try {
      final record = tracker.finish();
      await _commitReadingHistory((old) => [...old, record]);
    } catch (error) {
      _status('독서 활동 기록 저장 실패: ' + error.toString());
    }
  }

  Future<void> _clearReadingHistory() async {
    try {
      await _commitReadingHistory((_) => <ReadingSession>[]);
      _status('독서 활동 기록 삭제 완료. 서재의 읽기 진행률은 유지돼.');
    } catch (error) {
      _status('독서 활동 기록 삭제 실패: ' + error.toString());
    }
  }

  Future<File> _pendingUpdateFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(dir.path + Platform.pathSeparator +
        'hyp_pending_update_version.txt');
  }

  Future<void> _checkPendingInstallation(String runningVersion) async {
    try {
      final pendingFile = await _pendingUpdateFile();
      if (!await pendingFile.exists()) return;
      final pendingVersion = (await pendingFile.readAsString()).trim();
      if (!RegExp(r'^\d+\.\d+\.\d+(?:\.\d+)?$').hasMatch(pendingVersion)) {
        await pendingFile.delete();
        return;
      }
      if (UpdateService.isNewer(pendingVersion, runningVersion)) {
        _status('업데이트 v' + pendingVersion +
            ' 설치가 아직 확인되지 않았어. 설정에서 다시 시도할 수 있어.');
      } else {
        await pendingFile.delete();
        _status('v' + pendingVersion +
            ' 업데이트가 실제 앱 버전으로 확인됐어.');
      }
    } catch (_) {
      // A missing or inaccessible pending flag must never block startup.
    }
  }

  Future<void> _loadVersionInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => appVersion = 'v' + hypReleaseVersion +
            ' (build ' + info.buildNumber + ')');
        await _checkPendingInstallation(hypReleaseVersion);
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
        content: Text(AppLocalizations.of(ctx)!.androidSecurityNotice),
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

  void _clearFinder() {
    if (busy) return;
    _finderResetPolicy.reset();
    setState(() {
      for (final ctrl in [urlInput, commentInput, numberInput,
          titleInput, authorInput]) { ctrl.clear(); }
      candidates = [];
      _candidateSourceUrls.clear();
      _candidateSourceEvidence.clear();
      _candidateCache.clear();
      finderClearEpoch++;
      message = '';
    });
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
        message = '공유 내용을 받았어. 작품 번호와 공개 내용을 분석할게.';
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
      if (!_libraryReadFailed && mounted &&
          (Platform.isAndroid || Platform.isWindows)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_restoreDownloadQueue());
        });
      }
    }
  }

  Future<void> _restoreDownloadQueue() async {
    if (_restoringDownloads || _downloadQueueRunning ||
        _downloadQueueCancelled || galleryDownloadToken != null) return;
    _restoringDownloads = true;
    try {
      // A resume event may arrive before LibraryStorage has finished loading.
      // Do not clear approved jobs merely because the in-memory shelf is empty.
      await _initialLibraryRead.future;
      if (!mounted || _libraryReadFailed || _downloadQueueRunning ||
          galleryDownloadToken != null) return;
      final pending = await _downloadJobs.load();
      if (pending.isEmpty || !mounted) return;
      final found = library.works.where((work) =>
          pending.containsKey(work.workId) &&
          work.workId != activeDownloadWorkId &&
          !_queuedDownloadIds.contains(work.workId)).toList();
      if (found.isEmpty) return;
      _downloadSourceById.addAll(pending);
      await _enqueueDownloads(found, restored: true);
      _status('이전 다운로드 ' + found.length.toString() +
          '개를 이어서 진행해.');
    } catch (error) {
      _status('저장된 다운로드 복구 실패: ' + error.toString());
    } finally {
      _restoringDownloads = false;
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

  Future<List<YoutubeCollectionItem>?> _chooseYoutubeCollection(
      YoutubeCollectionReader reader, YoutubeCollectionPage first,
      {required bool playlist}) async {
    if (first.videos.isEmpty || !mounted) return null;
    final selected = <String>{};
    final items = <YoutubeCollectionItem>[...first.videos];
    var current = first;
    var loadingMore = false;
    String? nextError;
    final seenTokens = <String>{};
    Future<void> fetchNext(StateSetter refresh, BuildContext dialog) async {
      if (!current.hasMore || loadingMore || items.length >= 300) return;
      if (!seenTokens.add(current.continuation!)) return;
      refresh(() { loadingMore = true; nextError = null; });
      try {
        final next = await reader.listNext(current, playlist: playlist);
        if (!dialog.mounted) return;
        refresh(() {
          final known = items.map((e) => e.videoId).toSet();
          items.addAll(next.videos.where((e) => known.add(e.videoId)));
          current = next;
          if (next.videos.isEmpty) current = YoutubeCollectionPage(items);
        });
      } catch (error) {
        if (dialog.mounted) refresh(() {
          nextError = error.toString();
          // A failed page can be retried without repeating old results.
          seenTokens.remove(current.continuation);
        });
      } finally {
        if (dialog.mounted) refresh(() => loadingMore = false);
      }
    }
    return showDialog<List<YoutubeCollectionItem>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, refresh) {
          final l = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(l.youtubeChooseVideos),
            content: SizedBox(width: 550, height: 440,
              child: Column(children: [
                Text(l.youtubeVideosLoaded(items.length)),
                const SizedBox(height: 8),
                Expanded(child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    return CheckboxListTile(
                      dense: true, value: selected.contains(item.videoId),
                      title: Text(item.title, maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(item.videoId),
                      onChanged: (value) => refresh(() {
                        if (value == true && selected.length < 5) {
                          selected.add(item.videoId);
                        } else if (value != true) {
                          selected.remove(item.videoId);
                        }
                      }),
                    );
                  },
                )),
                if (nextError != null)
                  Text(l.youtubeMoreUnavailable,
                      style: const TextStyle(color: Colors.orangeAccent)),
                if (current.hasMore && items.length < 300)
                  TextButton.icon(
                    onPressed: loadingMore ? null :
                        () => fetchNext(refresh, dialog),
                    icon: loadingMore
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.expand_more),
                    label: Text(l.youtubeMoreVideos),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                  child: const HypText('취소')),
              FilledButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(
                  dialog, items.where((item) =>
                      selected.contains(item.videoId)).toList()),
                child: Text(l.youtubeAnalyzeSelected),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _fetch() async {
    final raw = urlInput.text.trim();
    if (RegExp(r'^\d{1,12}$').hasMatch(raw)) {
      await _quickAddNumber(raw);
      return;
    }
    final normalized = SocialShareText.normalize(raw);
    if (normalized.isEmpty) {
      _status('분석할 링크나 공유 텍스트를 입력해줘.');
      return;
    }
    final hints = SocialShareText.hints(normalized);
    if (titleInput.text.trim().isEmpty && hints.title.isNotEmpty) {
      titleInput.text = hints.title;
    }
    if (authorInput.text.trim().isEmpty && hints.author.isNotEmpty) {
      authorInput.text = hints.author;
    }
    final links = SourceLink.extract(normalized, limit: 10);
    if (links.isEmpty) {
      // Accept caption-only Android shares; do not silently discard them.
      commentInput.text = normalized;
      _analyze();
      if (candidates.isEmpty) {
        _status('공유 텍스트를 분석했지만 작품 번호는 없었어. '
            '게시물 링크나 댓글을 추가하거나 이미지 검색을 사용해줘.');
      }
      return;
    }
    setState(() => busy = true);
    final client = http.Client();
    final blocks = <String>[];
    final errors = <String>[];
    final youtubePartialText = AppLocalizations.of(context)!.youtubeCommentsPartial;
    final sourceIncompleteText = AppLocalizations.of(context)!.sourceIncomplete;
    final mapped = <String, String>{};
    final evidence = <String, Set<String>>{};
    void remember(String id, String url) {
      mapped.putIfAbsent(id, () => url);
      evidence.putIfAbsent(id, () => <String>{}).add(url);
    }
    try {
      final key = apiKeyInput.text.trim();
      for (final link in links) {
        String content = '';
        try {
          if (link.kind == SourceKind.hitomiWork) {
            content = link.url;
          } else if (link.kind == SourceKind.youtubeCollection) {
            final collection = YoutubeCollectionReader(client);
            final firstPage = await collection.listFirst(link);
            if (firstPage.videos.isEmpty) {
              errors.add('YouTube 영상 목록을 읽지 못했어. 직접 영상 주소를 공유해줘.');
            } else {
              final selected = await _chooseYoutubeCollection(
                  collection, firstPage, playlist: link.uri.path == '/playlist');
              for (final video in selected ?? <YoutubeCollectionItem>[]) {
                try {
                  final result = key.isEmpty
                      ? await YoutubePublicClient(client).fetch(video.videoId)
                      : await YoutubeClient(client).fetch(video.videoId, key);
                  final text = [result.title, result.description,
                      ...result.comments].where((part) =>
                          part.trim().isNotEmpty).join('\n\n');
                  blocks.add(text);
                  if (result.mayBeIncomplete) {
                    errors.add(video.videoId + ': ' + youtubePartialText);
                  }
                  for (final candidate in NumberExtractor.extract(
                      text, source: video.url)) {
                    remember(candidate.code, video.url);
                  }
                } catch (error) {
                  errors.add(video.videoId + ': ' + error.toString());
                }
              }
            }
          } else if (link.kind == SourceKind.youtubeVideo) {
            final result = key.isEmpty
                ? await YoutubePublicClient(client).fetch(link.videoId)
                : await YoutubeClient(client).fetch(link.videoId, key);
            content = [result.title, result.description, ...result.comments]
                .where((value) => value.trim().isNotEmpty).join('\n\n');
            if (result.mayBeIncomplete) {
              errors.add(link.videoId + ': ' + youtubePartialText);
            }
          } else if (link.canPreview) {
            final preview = await PublicSourcePreview(client).fetchDetailed(link);
            content = preview.text;
            if (!preview.fullBody) {
              // Unavailable Instagram captions/comments and truncated
              // community text must never be reported as complete.
              errors.add(sourceIncompleteText);
            }
          } else {
            errors.add('원문 자동 분석 미지원: ' + link.uri.host);
          }
        } catch (error) {
          errors.add(link.uri.host + ': ' + error.toString());
        }
        if (content.isEmpty) continue;
        blocks.add(content);
        for (final candidate in NumberExtractor.extract(
            content, source: link.url)) {
          remember(candidate.code, link.url);
        }
      }
      final shared = normalized.replaceAll(RegExp(r'https?://\S+'), '').trim();
      if (shared.isNotEmpty) blocks.add(shared);
      commentInput.text = SocialShareText.normalize(blocks.join('\n\n'));
      _candidateSourceUrls
        ..clear()
        ..addAll(mapped);
      _candidateSourceEvidence
        ..clear()
        ..addAll(evidence);
      _analyze();
      if (errors.isNotEmpty) {
        _status('분석된 후보 ' + candidates.length.toString() + '개. ' +
            '일부 링크는 원문을 읽지 못했어: ' +
            errors.take(2).join(' / ') + ' 직접 내용을 붙여넣을 수 있어.');
      } else if (candidates.isEmpty) {
        _status('번호가 없어. 공개 설명·본문에 없을 수 있으니 댓글을 직접 붙여넣어줘.');
      }
    } finally {
      client.close();
      if (mounted) setState(() => busy = false);
    }
  }

  List<NumberCandidate> _crossLineFallback() =>
      NumberExtractor.extract(commentInput.text, source: 'comment',
        allowCrossLine: true, crossLineOnly: true, maxCandidates: 160);

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

  Future<void> _saveOnlineSearchWork(OnlineSearchWork result) async {
    await _commitLibrary((latest) {
      if (latest.works.any((w) => w.workId == result.workId)) {
        // A repeat search can teach us a confirmed original/translated
        // title. Preserve the user's own title, reading position, covers
        // and all pre-existing language-group relationships.
        return LibraryBackup(
          works: latest.works.map((work) => work.workId == result.workId
              ? work.withEvidence(
                  aliases: [result.title, ...result.titleAliases])
              : work).toList(),
          collections: latest.collections,
        );
      }
      final work = WorkEntry.create(
        workId: result.workId, title: result.title,
        author: result.artists.join(', '),
      ).copyWith(
        titleAliases: result.titleAliases,
        tags: result.tags,
        sourceGroup: result.groups.join(', '),
        sourceSeries: result.series.join(', '),
        sourceType: result.type,
        sourceLanguage: result.language,
        sourceDate: result.date,
      );
      return WorkEditionService.autoLink(LibraryBackup(
        works: [...latest.works, work],
        collections: latest.collections,
      ), [result.workId]);
    });
    _status('작품 #' + result.workId + ' 서재에 추가했어.');
  }

  Future<void> _linkEdition(WorkEntry anchor, String targetId) async {
    try {
      await _commitLibrary((latest) =>
          WorkEditionService.link(latest, anchor.workId, targetId));
      _status('같은 작품의 다른 언어판으로 묶었어.');
    } catch (error) {
      _status('언어판 묶기에 실패했어: ' + error.toString());
    }
  }

  /// One library commit for all approved editions; a failed guard rolls back
  /// the entire selection, including any newly discovered remote records.
  Future<void> _linkEditionBatch(WorkEntry anchor,
      List<String> localIds, List<OnlineSearchWork> remoteWorks) async {
    await _commitLibrary((latest) => WorkEditionService.linkMany(
        latest, anchor.workId, localIds, remoteWorks));
    _status('언어판 ' + (localIds.length + remoteWorks.length).toString() +
        '개를 같은 작품으로 묶었어.');
  }

  Future<void> _unlinkEdition(WorkEntry work) async {
    await _commitLibrary((latest) =>
        WorkEditionService.unlink(latest, work.workId));
    _status('선택한 언어판만 묶음에서 분리했어.');
  }

  Future<void> _readOnlineSearchWork(OnlineSearchWork result) async {
    try {
      await _saveOnlineSearchWork(result);
      if (!mounted) return;
      final work = library.works.firstWhere((w) => w.workId == result.workId);
      await _readOnline(work);
    } catch (error) {
      _status('검색 작품 열기 실패: ' + error.toString());
    }
  }

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
    final savedFinderInput = _finderSnapshot();
    setState(() => busy = true);
    final client = http.Client();
    WorkEntry? openAfterSave;
    try {
      final links = SourceLink.extract(urlInput.text);
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
        GalleryInfo? info;
        try {
          info = await HitomiGalleryProvider(client).fetchInfo(code);
          if (title.isEmpty) title = info.title;
        } catch (_) {
          // Offline metadata never blocks adding or preserving an ID.
          if (title.isEmpty) {
            try { title = await HitomiGalleryProvider(client).fetchTitle(code); }
            catch (_) { /* Keep a placeholder title. */ }
          }
        }
        if (title.isEmpty) {
          title = '작품 $code';
          unknownTitles += 1;
        }
        final mappedLink = SourceLink.parse(_candidateSourceUrls[code] ?? '') ??
            (links.length == 1 ? links.single : null);
        works.add(WorkEntry.create(
          workId: code,
          videoId: mappedLink?.videoId ?? '',
          videoUrl: mappedLink?.url ?? '',
          sourceUrls: [
            ...?_candidateSourceEvidence[code],
            if (mappedLink != null) mappedLink.url,
          ],
          titleAliases: [
            ...title.split('|').skip(1),
            ...?info?.titleAliases,
          ],
          title: title,
          author: codes.length == 1 && authorInput.text.trim().isNotEmpty
              ? authorInput.text.trim() : (info?.author ?? ''),
          originalComment: commentInput.text,
        ).copyWith(
          coverMode: readerSettings.autoCoverEnabled ? 'auto' : 'preset',
          sourceLanguage: info?.language ?? '',
          sourceGroup: info?.group ?? '',
          sourceSeries: info?.series ?? '',
          sourceType: info?.type ?? '',
          sourceDate: info?.date ?? '',
          totalPages: info?.pageCount ?? 0,
          tags: info?.tags ?? const [],
        ));
      }
      await _commitLibrary((latest) => WorkEditionService.autoLink(
          LibraryBackup.merge(latest,
            LibraryBackup(works: works, collections: const [])), codes));
      if (mounted) setState(() => libraryNavigationEpoch++);
      // Clear only when a successful save is followed by leaving Home.
      // Preserve unsaved/new input and the persistent API key.
      _finderResetPolicy.recordSuccessfulSave(savedFinderInput);
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
      titleAliases: draft.titleAliases,
      sourceUrls: draft.sourceUrls,
      // Keep the backward-compatible primary source in sync with the
      // explicitly edited source list. Otherwise a removed legacy videoUrl
      // would silently reappear when JSON backup is restored.
      videoUrl: draft.sourceUrls.contains(current.videoUrl)
          ? current.videoUrl
          : draft.sourceUrls.isEmpty ? '' : draft.sourceUrls.first,
      videoId: draft.sourceUrls.contains(current.videoUrl)
          ? current.videoId
          : draft.sourceUrls.isEmpty ? '' :
              (ShortsLink.videoId(draft.sourceUrls.first) ?? ''),
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

  Future<void> _showWorkInfo(WorkEntry work) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => WorkInfoDialog(
        work: work,
        fetchInfo: () async {
          final client = http.Client();
          try {
            return await HitomiGalleryProvider(client).fetchInfo(work.workId);
          } finally {
            client.close();
          }
        },
        onCacheInfo: (info) async {
          await _commitLibrary((latest) => LibraryBackup(
            works: latest.works.map((w) {
              if (w.workId != work.workId) return w;
              return w.copyWith(
                author: w.author.isEmpty ? info.author : w.author,
                totalPages: info.pageCount > 0 ? info.pageCount : w.totalPages,
                tags: info.tags,
                sourceLanguage: info.language,
                sourceType: info.type,
                sourceSeries: info.series,
                sourceGroup: info.group,
                sourceDate: info.date,
              ).withEvidence(aliases: info.titleAliases);
            }).toList(),
            collections: latest.collections,
          ));
        },
        onEdit: () => _editWorkDetails(work),
        onFindOtherEditions: () async {
          if (!mounted) return;
          setState(() {
            _requestedEditionId = work.workId;
            _editionRequestEpoch++;
          });
        },
      ),
    );
  }

  Future<void> _savePublicationDates(Map<String, String> dates) async {
    if (dates.isEmpty) return;
    await _commitLibrary((latest) => LibraryBackup(
      works: latest.works.map((work) {
        final date = dates[work.workId];
        return date == null || work.sourceDate.isNotEmpty
            ? work : work.copyWith(sourceDate: date);
      }).toList(),
      collections: latest.collections,
    ));
  }

  Future<void> _groupWorks(List<String> workIds, String title) async {
    final selected = workIds.toSet();
    final name = title.trim();
    if (selected.length < 2 || name.isEmpty || name.length > 200) {
      _status('묶음은 서로 다른 작품 2개 이상과 이름이 필요해.');
      return;
    }
    final id = 'series_' +
        DateTime.now().microsecondsSinceEpoch.toString();
    try {
      await _commitLibrary((latest) {
        final members = latest.works
            .where((work) => selected.contains(work.workId)).toList();
        if (members.length != selected.length ||
            members.any((work) => work.groupId.isNotEmpty)) {
          throw StateError('이미 묶인 작품은 Auto/수동 묶기로 바꿀 수 없어. '
              '먼저 기존 묶음을 해제해줘.');
        }
        return WorkEditionService.createSeries(latest,
            workIds, id, name);
      });
      _status('작품 ' + selected.length.toString() + '개를 묶었어.');
    } catch (error) {
      _status('묶음 만들기 실패: ' + error.toString());
    }
  }

  /// Append only ungrouped works without disturbing existing order,
  /// covers, progress, downloads or favorites.
  Future<void> _addWorksToGroup(String groupId, List<String> orderedIds) async {
    if (groupId.isEmpty || orderedIds.isEmpty ||
        orderedIds.toSet().length != orderedIds.length) {
      throw StateError('잘못된 묶음 추가 요청이야.');
    }
    await _commitLibrary((latest) {
      final old = latest.works.where((w) => w.groupId == groupId).toList();
      if (old.isEmpty) throw StateError('기존 묶음을 찾지 못했어.');
      final newcomers = latest.works.where(
          (w) => orderedIds.contains(w.workId)).toList();
      if (newcomers.length != orderedIds.length ||
          newcomers.any((w) => w.groupId.isNotEmpty)) {
        throw StateError('이미 다른 묶음에 속한 작품은 추가하지 않아.');
      }
      return WorkEditionService.appendSeries(latest, groupId, orderedIds);
    });
    _status('기존 묶음에 ' + orderedIds.length.toString() + '개 작품을 추가했어.');
  }

  Future<void> _ungroupWorks(String groupId) async {
    await _commitLibrary((latest) => LibraryBackup(
      works: latest.works.map((w) => w.groupId == groupId
          ? w.copyWith(groupId: '', groupTitle: '', groupOrder: 0) : w)
          .toList(),
      collections: latest.collections,
    ));
    _status('작품을 삭제하지 않고 묶음만 해제했어.');
  }

  Future<void> _renameGroup(String groupId, String title) async {
    if (title.trim().isEmpty) return;
    await _commitLibrary((latest) => LibraryBackup(
      works: latest.works.map((w) => w.groupId == groupId
          ? w.copyWith(groupTitle: title.trim()) : w).toList(),
      collections: latest.collections,
    ));
  }

  Future<void> _reorderGroup(String groupId, List<String> orderedIds) async {
    await _commitLibrary((latest) =>
        WorkEditionService.reorderSeries(latest, groupId, orderedIds));
  }

  Future<void> _deleteSelectedOffline(List<String> workIds) async {
    final ids = workIds.toSet();
    final works = library.works.where((w) =>
        ids.contains(w.workId)).toList();
    if (works.isEmpty || !mounted) return;
    if (works.any((w) => downloadingGalleryKey == w.key)) {
      _status('다운로드가 진행 중인 작품은 완료 후 정리해줘.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const HypText('선택한 오프라인 파일 삭제'),
        content: HypText(works.length.toString() + '개 작품의 CBZ를 '
            '기기에서 삭제할까? 서재 작품·즐겨찾기·읽기 진행도·표지는 유지해.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const HypText('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const HypText('CBZ 파일 삭제')),
        ],
      ),
    );
    if (confirmed != true) return;
    var removed = 0;
    for (final work in works) {
      try {
        await galleryStore.delete(work.workId);
        removed++;
      } catch (_) {}
    }
    if (mounted) setState(() => coverEpoch++);
    _status(removed.toString() + '개 CBZ를 삭제했어. 서재 기록은 유지했어.');
  }

  Future<void> _exportSelectedDownloads(List<String> ids) async {
    final idsSet = ids.toSet();
    final selected = library.works.where(
        (work) => idsSet.contains(work.workId)).toList();
    if (selected.isEmpty) return;
    try {
      final report = await SelectedCbzExporter.export(galleryStore, selected);
      if (report.cancelled) return;
      _status(report.saved.toString() + '개 CBZ를 선택한 폴더로 내보냈어. ' +
          (report.failed > 0
              ? report.failed.toString() + '개는 실패했어.' : '원본 파일은 유지했어.'));
    } catch (e) {
      _status('CBZ 내보내기 실패: ' + e.toString());
    }
  }

  Future<void> _setCompleted(WorkEntry work, bool completed) async {
    try {
      await _commitLibrary((latest) =>
          latest.withCompleted(work.workId, completed));
      _status(completed ? '완독 처리했어.' : '완독 표시를 해제했어.');
    } catch (error) {
      _status('완독 상태 변경 실패: ' + error.toString());
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
            completed: w.completed,
            lastOpenedAt: w.lastOpenedAt,
            openCount: w.openCount,
            totalPages: w.totalPages,
            addedAt: w.addedAt,
            groupId: w.groupId,
            groupTitle: w.groupTitle,
            groupOrder: w.groupOrder,
            editionGroupId: w.editionGroupId,
          );
        }).toList(),
        collections: latest.collections,
      ));
    } catch (e) {
      _status('변경 실패: ' + e.toString());
    }
  }

  Future<void> _touchRead(WorkEntry work, {
    int? page, int? pageCount, bool? completed,
  }) async {
    try {
      await _commitLibrary((latest) => LibraryBackup(
        works: latest.works.map((w) => w.key == work.key
            ? w.copyWith(
                currentPage: page ?? w.currentPage,
                completed: completed ?? w.completed,
                lastOpenedAt: page == null
                    ? DateTime.now().toUtc().toIso8601String()
                    : w.lastOpenedAt,
                openCount: page == null ? w.openCount + 1 : w.openCount,
                totalPages: pageCount ?? w.totalPages,
              )
            : w).toList(),
        collections: latest.collections,
      ));
    } catch (e) {
      _status('읽기 기록 저장 실패: ' + e.toString());
    }
  }

  Future<void> _openOriginal(WorkEntry work) async {
    final source = SourceLink.parse(work.videoUrl);
    if (source == null) {
      _status('보관된 원본 링크가 없어.');
      return;
    }
    await launchUrl(source.uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openShortsInput() async {
    final links = SourceLink.extract(urlInput.text);
    if (links.isEmpty) {
      _status('유효한 HTTPS 링크를 입력해줘.');
      return;
    }
    try {
      final opened = await launchUrl(links.first.uri,
          mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('브라우저를 열지 못했어.');
      _status('웹에서 본문·댓글을 복사해 앱에 붙여넣을 수 있어.');
    } catch (error) {
      _status('원본 링크 열기 실패: ' + error.toString());
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
          readingSessions: choices[0] ? readingSessions : const [],
          includesReadingHistory: choices[0],
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
                  if (incoming.includesReadingHistory)
                    HypText('독서 활동 기록 ' + incoming.readingSessions.length.toString() +
                        '개 포함됨'),
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
      if (incoming.includesReadingHistory &&
          selected != AppRestoreMode.replaceSettings) {
        await _commitReadingHistory((current) {
          if (selected == AppRestoreMode.replaceEverything) {
            return [...incoming.readingSessions];
          }
          final all = <String, ReadingSession>{
            for (final session in current) session.id: session,
          };
          for (final session in incoming.readingSessions) {
            all[session.id] = session;
          }
          return all.values.toList()
            ..sort((a,b) => a.startedAt.compareTo(b.startedAt));
        });
      }
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
      final remote = await HitomiGalleryProvider(client).load(work.workId,
          dataSaver: readerSettings.dataSaverMode);
      Directory? persistentCache;
      try {
        final base = await getApplicationCacheDirectory();
        final root = Directory(base.path + Platform.pathSeparator +
            'hyp_reader_pages');
        unawaited(ReaderCachePruner.prune(root,
            activeWorkId: work.workId));
        persistentCache = Directory(root.path + Platform.pathSeparator +
            work.workId + Platform.pathSeparator +
            (readerSettings.dataSaverMode ? 'preview' : 'original'));
      } catch (_) {
        // Unavailable OS cache directory: continue with temporary caching.
      }
      if (!mounted) return;
      await _touchRead(work, pageCount: remote.pageCount);
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
      final reading = ReadingActivityTracker(work.workId, readerWork.currentPage);
      _activeReading = reading;
      try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (ctx) => GalleryReader(
          work: readerWork,
          archive: remote,
          persistentCacheDirectory: persistentCache,
          onPageChanged: (page) {
            reading.pageChanged(page);
            _touchRead(work, page: page);
          },
          onFinishedReading: (total) {
            reading.completed = true;
            reading.pageChanged(total);
            unawaited(_touchRead(work, page: total,
                pageCount: total, completed: true));
          },
          onOpenInBrowser: (page) => _openWebReader(work, page: page),
          onDownloadOffline: () => _downloadOnline(work),
          settings: readerSettings,
          onVerticalScrollingChanged: (vertical) {
            unawaited(_saveReaderSettings(
                readerSettings.copyWith(verticalScrolling: vertical)));
          },
          onTwoPageSpreadChanged: (twoPage) {
            unawaited(_saveReaderSettings(
                readerSettings.copyWith(twoPageSpread: twoPage)));
          },
          onPageLoaded: (page, bytes) {
            unawaited(_captureAutomaticCover(work, page, bytes));
          },
          onChooseCover: (page, bytes) => _usePageAsCover(work, page, bytes),
        )),
      );
      } finally {
        await _finishReading(reading);
      }
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

  Future<void> _enqueueDownloads(Iterable<WorkEntry> works,
      {bool restored = false}) async {
    final queued = works.toList();
    // Commit user-approved intent before starting a network request.
    if (!restored) {
      await _downloadJobs.addAll(queued.map((work) => work.workId));
    }
    _downloadQueueCancelled = false;
    for (final work in queued) {
      _downloadSourceById.putIfAbsent(work.workId, () => 'hitomi');
      if (_queuedDownloadIds.add(work.workId)) _downloadQueue.add(work);
    }
    if (mounted) {
      setState(() {});
      _status('다운로드 대기: ${_downloadQueue.length}개 작품. '
          '백그라운드에서도 순서대로 다운로드해.');
    }
    unawaited(_runDownloadQueue());
  }

  Future<void> _runDownloadQueue() async {
    if (_downloadQueueRunning || galleryDownloadToken != null) return;
    _downloadQueueRunning = true;
    try {
      // Acquire before even resolving the first remote gallery. The outer
      // lease stays alive between items and prevents Android 12+ from needing
      // to start a new foreground service while Home is in the background.
      await _backgroundDownloads.holdQueue(() async {
        if (Platform.isAndroid &&
            _backgroundDownloads.notificationsAllowed == false) {
          _status('알림 권한이 꺼져 있어 진행률이 알림창에 표시되지 않아. '
              '다운로드는 계속 시도할게. Android 설정에서 알림을 허용해줘.');
        }
        while (_downloadQueue.isNotEmpty && !_downloadQueueCancelled) {
          if (galleryDownloadToken != null) break;
          final work = _downloadQueue.removeFirst();
          _queuedDownloadIds.remove(work.workId);
          if (mounted) setState(() {});
          // Indeterminate progress is shown during network/metadata loading.
          await _backgroundDownloads.setProgress(0, 0,
              workId: work.workId, queuedCount: _downloadQueue.length,
              language: readerSettings.languageCode);
          // A queued work might have been removed from the library.
          if (!library.works.any((w) => w.workId == work.workId)) {
            await _downloadJobs.remove(work.workId);
            continue;
          }
          try {
            if (await galleryStore.exists(work.workId)) {
              await _downloadJobs.remove(work.workId);
              continue;
            }
            final json = _downloadSourceById[work.workId] == 'json';
            final saved = json
                ? await _downloadJsonSourceInternal(work, rightsApproved: true)
                : await _downloadOnlineInternal(work, rightsApproved: true);
            if (saved) await _downloadJobs.remove(work.workId);
          } catch (error) {
            _status('작품 ${work.workId} 다운로드 실패: $error');
          }
        }
      });
    } catch (error) {
      // Failed foreground-service startup must not discard queued jobs.
      // The persistent queue is retried on next app launch/resume.
      _status('백그라운드 다운로드 시작 실패: $error. '
          '작업은 저장되어 있으니 앱으로 돌아와 다시 시도해줘.');
    } finally {
      _downloadQueueRunning = false;
    }
  }

  void _cancelAllDownloads() {
    _downloadQueueCancelled = true;
    _downloadQueue.clear();
    _queuedDownloadIds.clear();
    galleryDownloadToken?.cancel();
    unawaited(_downloadJobs.clear());
    _downloadSourceById.clear();
    if (mounted) setState(() {});
  }

  Future<void> _downloadOnline(WorkEntry work) async {
    await _downloadOnlineInternal(work);
  }

  Future<bool> _downloadOnlineInternal(
      WorkEntry work, {bool rightsApproved = false}) async {
    if (galleryDownloadToken != null ||
        (!rightsApproved && _downloadQueueRunning)) {
      _status('이미 진행 중인 다운로드가 있어. 먼저 완료하거나 취소해줘.');
      return false;
    }
    final client = http.Client();
    GalleryTransfer? transfer;
    var holdsBackground = false;
    var completedSuccessfully = false;
    var cancelledByUser = false;
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
      await _downloadJobs.add(work.workId);
      await _backgroundDownloads.acquire();
      holdsBackground = true;
      transfer = GalleryTransfer();
      setState(() {
        galleryDownloadToken = transfer;
        readerTransfer = transfer;
        downloadingGalleryKey = work.key;
        downloadedGalleryPages = 0;
        downloadedGalleryBytes = 0;
        totalGalleryPages = remote.pageCount;
        isReaderTransferPaused = false;
        activeDownloadWorkId = work.workId;
      });
      unawaited(_backgroundDownloads.setProgress(0, remote.pageCount,
          workId: work.workId, queuedCount: _downloadQueue.length,
          language: readerSettings.languageCode));
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
            unawaited(_backgroundDownloads.setProgress(completed, total,
                workId: work.workId, queuedCount: _downloadQueue.length,
                language: readerSettings.languageCode));
          }
        },
      );
      await _downloadJobs.remove(work.workId);
      completedSuccessfully = true;
      if (mounted) setState(() => coverEpoch++);
      _status('오프라인 저장 완료! ' +
          downloaded.pageCount.toString() + '페이지를 인터넷 없이 읽을 수 있어.');
      return true;
    } on DownloadCancelled {
      cancelledByUser = true;
      await _downloadJobs.remove(work.workId);
      _status('다운로드가 취소됐어. 기존 오프라인 파일은 유지했어.');
      return false;
    } catch (e) {
      _status('오프라인 저장 실패: ' + e.toString());
      return false;
    } finally {
      client.close();
      if (holdsBackground) {
        await _backgroundDownloads.clearProgress();
        await _backgroundDownloads.release();
        await _backgroundDownloads.showDownloadResult(work.workId,
          success: completedSuccessfully, cancelled: cancelledByUser,
          language: readerSettings.languageCode);
      }
      activeDownloadWorkId = '';
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
    unawaited(_backgroundDownloads.setProgress(
      downloadedGalleryPages, totalGalleryPages,
      workId: activeDownloadWorkId,
      paused: active.isPaused, queuedCount: _downloadQueue.length,
      language: readerSettings.languageCode,
    ));
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
                HypText('선택된 작품: ' + selected.length.toString() + '개',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                for (final work in selected.take(4))
                  HypText('#' + work.workId + ' · ' + work.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (selected.length > 4)
                  HypText('외 ' + (selected.length - 4).toString() + '개'),
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
    await _downloadJsonSourceInternal(work);
  }

  Future<bool> _downloadJsonSourceInternal(WorkEntry work,
      {bool rightsApproved = false}) async {
    if (galleryDownloadToken != null ||
        (!rightsApproved && _downloadQueueRunning)) {
      _status('이미 다른 다운로드가 실행 중이야.');
      return false;
    }
    final pattern = onlineSourceInput.text.trim().isNotEmpty
        ? onlineSourceInput.text.trim()
        : (await sourceSettings.load()).trim();
    if (pattern.isEmpty) {
      _status('온라인 소스 URL 패턴을 먼저 설정해줘.');
      return false;
    }
    final client = http.Client();
    GalleryTransfer? transfer;
    var holdsBackground = false;
    var completedSuccessfully = false;
    var cancelledByUser = false;
    try {
      final remote = await OnlineGalleryProvider(client)
          .load(pattern, work.workId);
      if (!remote.downloadAllowed) {
        _status('이 온라인 소스는 작품 다운로드를 허용하지 않아.');
        return false;
      }
      if (!mounted) return false;
      final approved = rightsApproved ? true : await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const HypText('오프라인 다운로드'),
          content: HypText('이 작품의 이미지 ' + remote.pageCount.toString() +
              '장을 다운로드해 로컬 CBZ 파일로 저장할까?\n' +
              '본인이 저장 권한을 가진 작품만 다운로드해야 해. '
              '기존 오프라인 파일이 있다면 완성한 뒤 교체돼.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const HypText('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const HypText('다운로드')),
          ],
        ),
      );
      if (approved != true || !mounted) return false;
      await _downloadJobs.add(work.workId, source: 'json');
      await _backgroundDownloads.acquire();
      holdsBackground = true;
      transfer = GalleryTransfer();
      setState(() {
        galleryDownloadToken = transfer;
        readerTransfer = transfer;
        downloadingGalleryKey = work.key;
        downloadedGalleryPages = 0;
        totalGalleryPages = remote.pageCount;
        downloadedGalleryBytes = 0;
        isReaderTransferPaused = false;
        activeDownloadWorkId = work.workId;
      });
      unawaited(_backgroundDownloads.setProgress(0, remote.pageCount,
          workId: work.workId, queuedCount: _downloadQueue.length,
          language: readerSettings.languageCode));
      final archive = await ReaderGalleryDownloader(galleryStore).download(
        work.workId, remote,
        transfer: transfer,
        onProgress: (completed, total, bytes) {
          if (mounted) {
            setState(() {
              downloadedGalleryPages = completed;
              totalGalleryPages = total;
              downloadedGalleryBytes = bytes;
            });
            unawaited(_backgroundDownloads.setProgress(completed, total,
                workId: work.workId, queuedCount: _downloadQueue.length,
                language: readerSettings.languageCode));
          }
        },
      );
      await _downloadJobs.remove(work.workId);
      completedSuccessfully = true;
      if (mounted) setState(() => coverEpoch++);
      _status('다운로드 완료: ' + archive.pageCount.toString() +
          '장. 이제 인터넷 없이도 읽을 수 있어.');
      return true;
    } on DownloadCancelled {
      cancelledByUser = true;
      _status('다운로드가 취소됐어. 기존 오프라인 파일은 유지했어.');
      await _downloadJobs.remove(work.workId);
      return false;
    } catch (e) {
      _status('다운로드 실패: ' + e.toString());
      return false;
    } finally {
      client.close();
      if (holdsBackground) {
        await _backgroundDownloads.clearProgress();
        await _backgroundDownloads.release();
        await _backgroundDownloads.showDownloadResult(work.workId,
          success: completedSuccessfully, cancelled: cancelledByUser,
          language: readerSettings.languageCode);
      }
      activeDownloadWorkId = '';
      if (transfer != null && mounted) {
        setState(() {
          galleryDownloadToken = null;
          readerTransfer = null;
          downloadingGalleryKey = null;
          isReaderTransferPaused = false;
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
      await _touchRead(work, pageCount: book.pageCount);
      final reading = ReadingActivityTracker(work.workId, work.currentPage);
      _activeReading = reading;
      try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (ctx) => GalleryReader(
          work: work,
          archive: book,
          onPageChanged: (page) {
            reading.pageChanged(page);
            _touchRead(work, page: page);
          },
          onFinishedReading: (total) {
            reading.completed = true;
            reading.pageChanged(total);
            unawaited(_touchRead(work, page: total,
                pageCount: total, completed: true));
          },
          settings: readerSettings,
          onVerticalScrollingChanged: (vertical) {
            unawaited(_saveReaderSettings(
                readerSettings.copyWith(verticalScrolling: vertical)));
          },
          onTwoPageSpreadChanged: (twoPage) {
            unawaited(_saveReaderSettings(
                readerSettings.copyWith(twoPageSpread: twoPage)));
          },
          onPageLoaded: (page, bytes) {
            unawaited(_captureAutomaticCover(work, page, bytes));
          },
          onChooseCover: (page, bytes) => _usePageAsCover(work, page, bytes),
        )), 
      );
    } finally {
        await _finishReading(reading);
      }
    } catch (e) {
      _status('읽기 실패: ' + e.toString() + ' / CBZ 또는 ZIP 파일을 먼저 연결해줘.');
    }
  }

  Future<void> _downloadInstaller(
      ReleaseUpdate release, ReleaseAsset asset) async {
    if (downloadingUpdate) return;
    final client = http.Client();
    var holdsBackground = false;
    setState(() {
      downloadingUpdate = true;
      updateProgress = 0;
      updateStatus = '설치 파일을 내려받는 중이야.';
      message = '설치 파일을 내려받는 중이야.';
    });
    try {
      await _backgroundDownloads.acquire();
      holdsBackground = true;
      final installer = await UpdateService(client).download(
        release,
        asset,
        onProgress: (value) {
          if (mounted) {
            setState(() => updateProgress = value.clamp(0.0, 1.0));
            unawaited(_backgroundDownloads.setProgress(
                (value * 100).round(), 100,
                isUpdate: true, language: readerSettings.languageCode));
          }
        },
        onStatus: (status) {
          if (mounted) setState(() => updateStatus = status);
        },
      );
      await _backgroundDownloads.clearProgress();
      await _backgroundDownloads.release();
      holdsBackground = false;
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
        final pending = await _pendingUpdateFile();
        await pending.writeAsString(release.version, flush: true);
        try {
          await UpdateService(client).launchInstaller(installer);
        } catch (_) {
          if (await pending.exists()) await pending.delete();
          rethrow;
        }
        if (Platform.isWindows) {
          exit(0);
        }
        _status('Android 설치 화면을 열었어. 승인 후 앱 버전이 변경되면 설치를 확인할게.');
      } else {
        _status('검증된 설치 파일을 앱 보관함에 저장했어. 다시 다운로드할 필요 없어.');
      }
    } catch (e) {
      _status('업데이트 실패: ' + e.toString());
    } finally {
      client.close();
      if (holdsBackground) {
        await _backgroundDownloads.clearProgress();
        await _backgroundDownloads.release();
      }
      if (mounted) setState(() => downloadingUpdate = false);
    }
  }

  /// One GitHub update check on every fresh launch; not a background poll.
  /// Per-version 7-day snoozes are enforced by _checkRelease.
  Future<void> _automaticUpdateCheck() async {
    try {
      await _settingsLoad;
      if (mounted) await _checkRelease(silent: true);
    } catch (_) {
      // An offline session must never be blocked by the updater.
    }
  }

  Future<void> _checkRelease({bool silent = false}) async {
    if (downloadingUpdate || _updateDialogOpen) return;
    if (silent) await _settingsLoad;
    final client = http.Client();
    try {
      final next = await UpdateService(client).latest(hypReleaseVersion);
      if (next == null) {
        if (!silent) _status('현재 더 새로운 릴리스가 없어.');
        return;
      }
      if (!mounted || !UpdatePrompt.shouldShow(readerSettings,
          next.version, DateTime.now(), automatic: silent,
          dismissedThisLaunch: _updateDismissedThisLaunch)) return;
      final asset = next.installerFor(defaultTargetPlatform);
      _updateDialogOpen = true;
      String? choice;
      try {
        choice = await showDialog<String>(context: context, builder: (ctx) =>
        AlertDialog(
          title: HypText('업데이트 v' + next.version),
          content: HypText(next.notes.isEmpty
              ? '새 버전이 공개됐어. 설치 파일을 다운로드할까?'
              : next.notes),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'later'),
                child: const HypText('나중에')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'snooze'),
                child: const HypText('7일간 보지 않기')),
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
      } finally {
        _updateDialogOpen = false;
      }
      if (choice == 'snooze') {
        await _saveReaderSettings(UpdatePrompt.snooze(
            readerSettings, next.version, DateTime.now()));
      } else if (choice == null || choice == 'later') {
        if (silent) _updateDismissedThisLaunch = true;
      } else if (choice == 'web') {
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
    WidgetsBinding.instance.removeObserver(this);
    _noticesTimer?.cancel();
    for (final ctrl in [urlInput, commentInput, numberInput, titleInput, authorInput, apiKeyInput, onlineSourceInput]) {
      ctrl.dispose();
    }
    _backgroundDownloads.setDownloadsNavigationHandler(null);
    super.dispose();
  }

  String? _requestedEditionId;
  int _editionRequestEpoch = 0;

  @override
  Widget build(BuildContext context) => HypDashboard(
    library: library,
    readingSessions: readingSessions,
    onClearReadingHistory: _clearReadingHistory,
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
    downloadNavigationEpoch: downloadNavigationEpoch,
    editionLookupId: _requestedEditionId,
    editionLookupEpoch: _editionRequestEpoch,
    appVersion: appVersion,
    downloadingUpdate: downloadingUpdate,
    updateProgress: updateProgress,
    updateStatus: updateStatus,
    downloadingGalleryKey: downloadingGalleryKey,
    downloadedGalleryPages: downloadedGalleryPages,
    totalGalleryPages: totalGalleryPages,
    downloadedGalleryBytes: downloadedGalleryBytes,
    onAnalyze: _analyze,
    onClearFinder: _clearFinder,
    onLeaveFinderAfterSave: _clearSavedFinderOnTabExit,
    finderClearEpoch: finderClearEpoch,
    onFetch: _fetch,
    onSaveWork: _saveWork,
    onQuickAddNumber: _quickAddNumber,
    onSaveOnlineSearchWork: _saveOnlineSearchWork,
    onLinkEdition: _linkEdition,
    onLinkEditions: _linkEditionBatch,
    onUnlinkEdition: _unlinkEdition,
    onReadOnlineSearchWork: _readOnlineSearchWork,
    onSaveSelectedWorks: _saveSelectedWorks,
    onVerifyCandidateCodes: _verifyCandidateCodes,
    onCrossLineFallback: _crossLineFallback,
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
    onShowWorkInfo: _showWorkInfo,
    onGroupWorks: _groupWorks,
    onAddWorksToGroup: _addWorksToGroup,
    onUngroupWorks: _ungroupWorks,
    onRenameGroup: _renameGroup,
    onReorderGroup: _reorderGroup,
    onExportSelectedDownloads: _exportSelectedDownloads,
    onDeleteSelectedOffline: _deleteSelectedOffline,
    onToggleDownloadPause: _pauseOrResumeReaderDownload,
    downloadPaused: isReaderTransferPaused,
    downloadCanPause: readerTransfer != null,
    onImportGallery: _importGallery,
    onUpdateWork: _updateWork,
    onSetCompleted: _setCompleted,
    onSavePublicationDates: _savePublicationDates,
    onChooseCover: _chooseCover,
    onSaveReaderSettings: _saveReaderSettings,
    onOpenOriginal: _openOriginal,
    onOpenShortsInput: _openShortsInput,
    onCancelGalleryDownload: _cancelAllDownloads,
    onDismissMessage: () => setState(() => message = ''),
  );
}
