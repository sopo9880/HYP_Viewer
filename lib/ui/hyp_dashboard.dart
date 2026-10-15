import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import '../core/hitomi_gallery.dart';
import '../core/hitomi_popularity.dart';

import '../core/hero_cover_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/gallery.dart';
import '../core/cover_store.dart';
import '../core/reader_settings.dart';
import '../core/i18n.dart';
import '../core/number_extractor.dart';
import 'candidate_editor.dart';
import '../core/work.dart';
import '../core/work_grouping.dart';
import 'hero_banner.dart';
import 'hyp_theme.dart';
import 'shorts_finder_panel.dart';
import 'work_cards.dart';
import 'auto_group_wizard.dart';
import 'work_group_card.dart';

enum HypPage { home, library, favorites, downloads, history, settings }

extension HypPageInfo on HypPage {
  String get label => switch (this) {
    HypPage.home => '홈',
    HypPage.library => '내 서재',
    HypPage.favorites => '즐겨찾기',
    HypPage.downloads => '다운로드',
    HypPage.history => '열람 기록',
    HypPage.settings => '설정',
  };

  IconData get icon => switch (this) {
    HypPage.home => Icons.home_rounded,
    HypPage.library => Icons.library_books_rounded,
    HypPage.favorites => Icons.favorite_rounded,
    HypPage.downloads => Icons.download_rounded,
    HypPage.history => Icons.history_rounded,
    HypPage.settings => Icons.settings_rounded,
  };
}

/// Windows-first responsive app shell. All actions call the existing library,
/// YouTube, CBZ and updater services instead of imitating them with mock data.
class HypDashboard extends StatefulWidget {
  final LibraryBackup library;
  final GalleryStore galleryStore;
  final CoverStore coverStore;
  final ReaderSettings readerSettings;
  final Uint8List? heroArtwork;
  final int coverEpoch;
  final TextEditingController urlInput;
  final TextEditingController apiKeyInput;
  final TextEditingController commentInput;
  final TextEditingController numberInput;
  final TextEditingController titleInput;
  final TextEditingController authorInput;
  final TextEditingController onlineSourceInput;
  final List<NumberCandidate> candidates;
  final bool busy;
  final String message;
  final int navigationEpoch;
  final int libraryNavigationEpoch;
  final String appVersion;
  final bool downloadingUpdate;
  final double updateProgress;
  final String? downloadingGalleryKey;
  final int downloadedGalleryPages;
  final int totalGalleryPages;
  final int downloadedGalleryBytes;
  final VoidCallback onAnalyze;
  final Future<void> Function() onFetch;
  final Future<void> Function() onSaveWork;
  final Future<void> Function(String code) onQuickAddNumber;
  final Future<void> Function(List<String> codes) onSaveSelectedWorks;
  final CandidateBatchVerify onVerifyCandidateCodes;
  final List<NumberCandidate> Function()? onCrossLineFallback;
  final Future<void> Function() onChooseHeroArtwork;
  final Future<void> Function() onClearHeroArtwork;
  final Future<void> Function() onSaveOnlineSource;
  final Future<void> Function() onExportJson;
  final Future<void> Function() onExportExcel;
  final Future<void> Function() onImportJson;
  final Future<void> Function() onRestorePreviousLibrary;
  final Future<void> Function() onCheckRelease;
  final Future<void> Function() onCheckAnnouncements;
  final Future<void> Function() onSecurityHelp;
  final Future<void> Function(WorkEntry) onOpenGallery;
  final Future<void> Function(WorkEntry) onReadOnline;
  final Future<void> Function(WorkEntry) onReadWebPage;
  final Future<void> Function(WorkEntry) onDownloadOnline;
  final Future<void> Function() onDownloadAll;
  final Future<void> Function(bool enabled) onSetAutoDownload;
  final int queuedDownloadCount;
  final Future<void> Function(WorkEntry) onDownloadJsonSource;
  final Future<void> Function(WorkEntry) onDeleteOffline;
  final Future<void> Function(WorkEntry) onDeleteWork;
  final Future<bool> Function(List<String> ids) onDeleteSelectedWorks;
  final Future<void> Function(WorkEntry) onEditWorkDetails;
  final Future<void> Function(WorkEntry) onShowWorkInfo;
  final Future<void> Function(List<String> ids, String title) onGroupWorks;
  final Future<void> Function(String groupId, List<String> ids)? onAddWorksToGroup;
  final Future<void> Function(String id) onUngroupWorks;
  final Future<void> Function(String id, String title) onRenameGroup;
  final Future<void> Function(String id, List<String> ids) onReorderGroup;
  final Future<void> Function(List<String> ids) onExportSelectedDownloads;
  final Future<void> Function(List<String> ids) onDeleteSelectedOffline;
  final VoidCallback onToggleDownloadPause;
  final bool downloadPaused;
  final bool downloadCanPause;
  final Future<void> Function(WorkEntry) onImportGallery;
  final Future<void> Function(WorkEntry) onUpdateWork;
  final Future<void> Function(Map<String, String>) onSavePublicationDates;
  final Future<void> Function(WorkEntry) onChooseCover;
  final Future<void> Function(ReaderSettings) onSaveReaderSettings;
  final Future<void> Function(WorkEntry) onOpenOriginal;
  final Future<void> Function() onOpenShortsInput;
  final VoidCallback onCancelGalleryDownload;
  final VoidCallback onDismissMessage;

  const HypDashboard({
    super.key,
    required this.library,
    required this.galleryStore,
    required this.coverStore,
    required this.readerSettings,
    required this.heroArtwork,
    required this.coverEpoch,
    required this.urlInput,
    required this.apiKeyInput,
    required this.commentInput,
    required this.numberInput,
    required this.titleInput,
    required this.authorInput,
    required this.onlineSourceInput,
    required this.candidates,
    required this.busy,
    required this.message,
    required this.navigationEpoch,
    required this.libraryNavigationEpoch,
    required this.appVersion,
    required this.downloadingUpdate,
    required this.updateProgress,
    required this.downloadingGalleryKey,
    required this.downloadedGalleryPages,
    required this.totalGalleryPages,
    required this.downloadedGalleryBytes,
    required this.onAnalyze,
    required this.onFetch,
    required this.onSaveWork,
    required this.onQuickAddNumber,
    required this.onSaveSelectedWorks,
    required this.onVerifyCandidateCodes,
    this.onCrossLineFallback,
    required this.onChooseHeroArtwork,
    required this.onClearHeroArtwork,
    required this.onSaveOnlineSource,
    required this.onExportJson,
    required this.onExportExcel,
    required this.onImportJson,
    required this.onRestorePreviousLibrary,
    required this.onCheckRelease,
    required this.onCheckAnnouncements,
    required this.onSecurityHelp,
    required this.onOpenGallery,
    required this.onReadOnline,
    required this.onReadWebPage,
    required this.onDownloadOnline,
    required this.onDownloadAll,
    required this.onSetAutoDownload,
    required this.queuedDownloadCount,
    required this.onDownloadJsonSource,
    required this.onDeleteOffline,
    required this.onDeleteWork,
    required this.onDeleteSelectedWorks,
    required this.onEditWorkDetails,
    required this.onShowWorkInfo,
    required this.onGroupWorks,
    this.onAddWorksToGroup,
    required this.onUngroupWorks,
    required this.onRenameGroup,
    required this.onReorderGroup,
    required this.onExportSelectedDownloads,
    required this.onDeleteSelectedOffline,
    required this.onToggleDownloadPause,
    required this.downloadPaused,
    required this.downloadCanPause,
    required this.onImportGallery,
    required this.onUpdateWork,
    required this.onSavePublicationDates,
    required this.onChooseCover,
    required this.onSaveReaderSettings,
    required this.onOpenOriginal,
    required this.onOpenShortsInput,
    required this.onCancelGalleryDownload,
    required this.onDismissMessage,
  });

  @override
  State<HypDashboard> createState() => _HypDashboardState();
}

class _HypDashboardState extends State<HypDashboard> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  HypPage _page = HypPage.home;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _backupSectionKey = GlobalKey();
  DateTime? _lastHomeBack;
  bool _openBackupSectionRequested = false;
  final Set<String> _offlineKeys = <String>{};
  bool _selectingWorks = false;
  bool _bannerHovered = false;
  bool _notificationHovered = false;
  bool _notificationShown = true;
  Timer? _notificationTimer;
  Timer? _notificationExitTimer;
  String? _openedGroupId;
  final Set<String> _selectedWorkIds = <String>{};
  bool get _canSelectWorks => _page == HypPage.library ||
      _page == HypPage.downloads || _search.text.trim().isNotEmpty;

  final Map<String, int> _pageCounts = <String, int>{};
  final Map<String, Uint8List> _coverImages = <String, Uint8List>{};
  int _offlineRefreshEpoch = 0;
  final List<String?> _rotatingCoverKeys = [null, null, null];
  Timer? _bannerTimer;
  late final TextEditingController _preloadInput;
  final Map<String, Map<String, int>> _popularity = {};
  final Set<String> _popularityTried = {};
  bool _popularityBusy = false;
  bool _publicationBusy = false;
  bool _publicationTried = false;
  String? _sortLoadError;

  void _syncSortLookup() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.readerSettings.librarySort == 'hitomiPopular') {
        unawaited(_loadPopularity());
      } else if (widget.readerSettings.librarySort == 'published') {
        unawaited(_loadPublicationDates());
      }
    });
  }

  Future<void> _loadPopularity({bool refresh = false}) async {
    final period = widget.readerSettings.popularityPeriod;
    if (_popularityBusy || (!refresh && _popularityTried.contains(period))) return;
    _popularityTried.add(period);
    setState(() { _popularityBusy = true; _sortLoadError = null; });
    final client = http.Client();
    try {
      final ranks = await HitomiPopularity(client).loadRanks(period);
      if (mounted) setState(() => _popularity[period] = ranks);
    } catch (error) {
      if (mounted) setState(() =>
          _sortLoadError = '히토미 인기 목록을 받지 못했어: $error');
    } finally {
      client.close();
      if (mounted) setState(() => _popularityBusy = false);
    }
  }

  Future<void> _loadPublicationDates({bool refresh = false}) async {
    if (_publicationBusy || (!refresh && _publicationTried)) return;
    _publicationTried = true;
    final missing = widget.library.works.where(
        (w) => w.sourceDate.isEmpty &&
        RegExp(r'^\d{1,12}$').hasMatch(w.workId)).take(250).toList();
    if (missing.isEmpty) return;
    setState(() { _publicationBusy = true; _sortLoadError = null; });
    final client = http.Client();
    var failures = 0;
    try {
      for (var offset = 0; offset < missing.length && mounted; offset += 3) {
        final dates = <String, String>{};
        await Future.wait(missing.skip(offset).take(3).map((work) async {
          try {
            final info = await HitomiGalleryProvider(client)
                .fetchInfo(work.workId).timeout(const Duration(seconds: 12));
            if (DateTime.tryParse(info.date) != null) {
              dates[work.workId] = info.date;
            }
          } catch (_) { failures++; }
        }));
        if (dates.isNotEmpty) await widget.onSavePublicationDates(dates);
        if (failures >= 8) break;
      }
      if (failures > 0 && mounted) setState(() =>
          _sortLoadError = '$failures개 작품의 등록 날짜를 가져오지 못했어.');
    } finally {
      client.close();
      if (mounted) setState(() => _publicationBusy = false);
    }
  }

  void _shuffleBannerCover() {
    if (!mounted) return;
    setState(() {
      final keys = _coverImages.keys.toList();
      final used = <String>{};
      for (var slide = 0; slide < 3; slide++) {
        final pool = keys.where((key) =>
            key != _rotatingCoverKeys[slide] &&
            (!used.contains(key) || keys.length < 3)).toList();
        final next = pickRandomLibraryCover(
            pool.isEmpty ? keys : pool,
            previous: _rotatingCoverKeys[slide]);
        _rotatingCoverKeys[slide] = next;
        if (next != null) used.add(next);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _preloadInput = TextEditingController(
      text: widget.readerSettings.preloadPages.toString());
    _search.addListener(_changedSearch);
    _scheduleNotificationTimer();
    _syncSortLookup();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshOffline());
    _bannerTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && _page == HypPage.home && !_bannerHovered &&
          widget.readerSettings.heroArtworkSource == 'random' &&
          _coverImages.isNotEmpty) {
        _shuffleBannerCover();
      }
    });
  }

  @override
  void didUpdateWidget(covariant HypDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _notificationShown = true;
      _scheduleNotificationTimer();
    }
    if (oldWidget.readerSettings.librarySort != widget.readerSettings.librarySort ||
        oldWidget.readerSettings.popularityPeriod !=
            widget.readerSettings.popularityPeriod) _syncSortLookup();
    if (oldWidget.readerSettings.preloadPages !=
        widget.readerSettings.preloadPages) {
      _preloadInput.text = widget.readerSettings.preloadPages.toString();
    }
    if (oldWidget.navigationEpoch != widget.navigationEpoch) {
      _page = HypPage.home;
      _search.clear();
    }
    if (oldWidget.libraryNavigationEpoch != widget.libraryNavigationEpoch) {
      _page = HypPage.library;
      _search.clear();
    }
    _selectedWorkIds.removeWhere((id) =>
        !widget.library.works.any((w) => w.workId == id));
    if (oldWidget.library.works.length != widget.library.works.length ||
        oldWidget.coverEpoch != widget.coverEpoch ||
        _coverSignature(oldWidget.library) != _coverSignature(widget.library)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshOffline());
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _notificationTimer?.cancel();
    _notificationExitTimer?.cancel();
    _preloadInput.dispose();
    _search.removeListener(_changedSearch);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _scheduleNotificationTimer() {
    _notificationTimer?.cancel();
    _notificationExitTimer?.cancel();
    if (widget.message.isEmpty || _notificationHovered) return;
    final captured = widget.message;
    final isFailure = RegExp(r'실패|오류|HTTP\s*[45]\d\d|에러',
        caseSensitive: false).hasMatch(captured);
    _notificationTimer = Timer(
        Duration(seconds: isFailure ? 10 : 5), () {
      if (!mounted || widget.message != captured || _notificationHovered) return;
      setState(() => _notificationShown = false);
      _notificationExitTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && widget.message == captured &&
            !_notificationHovered) widget.onDismissMessage();
      });
    });
  }

  void _changedSearch() {
    if (mounted) setState(() {});
  }

  void _navigate(HypPage page) {
    _openedGroupId = null;
    _lastHomeBack = null;
    _search.clear();
    setState(() {
      _page = page;
      if (page != HypPage.library) {
        _selectingWorks = false;
        _selectedWorkIds.clear();
      }
    });
  }

  void _handleSystemBack() {
    if (!Platform.isAndroid) return;
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }
    if (_selectingWorks) {
      _toggleSelectionMode();
      return;
    }
    if (_search.text.isNotEmpty) {
      _search.clear();
      return;
    }
    if (_page == HypPage.library && _openedGroupId != null) {
      setState(() => _openedGroupId = null);
      return;
    }
    if (_page != HypPage.home) {
      _navigate(HypPage.home);
      return;
    }
    final now = DateTime.now();
    if (_lastHomeBack != null &&
        now.difference(_lastHomeBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastHomeBack = now;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 2),
      content: HypText('뒤로가기를 한 번 더 누르면 앱이 종료됩니다.'),
    ));
  }

  Future<void> _openBackupSettings() async {
    _navigate(HypPage.settings);
    _openBackupSectionRequested = true;
    final active = widget.readerSettings.expandedSettings.toSet()
      ..add('backup');
    await widget.onSaveReaderSettings(widget.readerSettings.copyWith(
      expandedSettings: active.toList()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_openBackupSectionRequested) return;
      _openBackupSectionRequested = false;
      final target = _backupSectionKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 260),
          alignment: 0.06);
      }
    });
  }

  void _toggleSelectionMode() => setState(() {
    _selectingWorks = !_selectingWorks;
    if (!_selectingWorks) _selectedWorkIds.clear();
  });

  void _toggleSelectedWork(WorkEntry work) => setState(() {
    if (!_selectedWorkIds.add(work.workId)) {
      _selectedWorkIds.remove(work.workId);
    }
  });

  void _startSelection(WorkEntry work) => setState(() {
    _selectingWorks = true;
    _selectedWorkIds.add(work.workId);
  });

  Future<void> _removeSelectedWorks() async {
    final ids = _selectedWorkIds.toList();
    if (ids.isEmpty) return;
    final completed = await widget.onDeleteSelectedWorks(ids);
    if (!mounted) return;
    if (completed) {
      setState(() {
        _selectedWorkIds.clear();
        _selectingWorks = false;
      });
      await _refreshOffline();
    }
  }

  Future<void> _editSelectedWork() async {
    if (_selectedWorkIds.length != 1) return;
    final matching = widget.library.works.where(
        (w) => w.workId == _selectedWorkIds.first).toList();
    if (matching.isEmpty) return;
    await widget.onEditWorkDetails(matching.single);
    if (!mounted) return;
    setState(() {
      _selectingWorks = false;
      _selectedWorkIds.clear();
    });
    await _refreshOffline();
  }


  String _coverSignature(LibraryBackup backup) => backup.works
      .map((w) => w.key + ':' + w.coverMode + ':' +
          w.coverPreset.toString() + ':' + w.coverPage.toString())
      .join('|');

  Future<void> _refreshOffline() async {
    // Discard out-of-order refreshes after a work was removed or re-added.
    final epoch = ++_offlineRefreshEpoch;
    final offline = <String>{};
    final counts = <String, int>{};
    final images = <String, Uint8List>{};
    try {
      for (final work in widget.library.works) {
        if (work.coverMode != 'preset') {
          try {
            final bytes = await widget.coverStore.read(
              work.workId,
              mode: work.coverMode,
              page: work.coverMode == 'page' ? work.coverPage : 1,
            );
            if (bytes != null) images[work.key] = bytes;
          } catch (_) {
            // Missing cached previews fall back to built-in cover art.
          }
        }

        if (!await widget.galleryStore.exists(work.workId)) continue;
        offline.add(work.key);
        if (counts.length >= 30) continue;
        try {
          final book = await widget.galleryStore.read(work.workId);
          counts[work.key] = book.pageCount;
          if (work.coverMode == 'auto' && !images.containsKey(work.key)) {
            final first = book.pageBytes(0);
            if (first.isNotEmpty && first.length <= 2 * 1024 * 1024) {
              images[work.key] = first;
            }
          }
        } catch (_) {
          // Keep the offline entry even if thumbnail decoding fails.
        }
      }
    } catch (_) {
      // Flutter widget tests can run without platform file services.
    }
    if (!mounted || epoch != _offlineRefreshEpoch) return;
    setState(() {
      _offlineKeys
        ..clear()
        ..addAll(offline);
      _pageCounts
        ..clear()
        ..addAll(counts);
      _coverImages
        ..clear()
        ..addAll(images);
      for (var slide = 0; slide < 3; slide++) {
        if (_rotatingCoverKeys[slide] == null ||
            !images.containsKey(_rotatingCoverKeys[slide])) {
          _rotatingCoverKeys[slide] = pickRandomLibraryCover(
              images.keys, previous: _rotatingCoverKeys[slide]);
        }
      }
    });
  }

  List<WorkEntry> get _works => WorkSorting.sort(
    widget.library.works,
    LibrarySort.values.firstWhere(
      (mode) => mode.name == widget.readerSettings.librarySort,
      orElse: () => LibrarySort.newest,
    ),
    descending: widget.readerSettings.librarySortDescending,
    popularityRanks: _popularity[widget.readerSettings.popularityPeriod] ?? const {},
  );

  List<WorkEntry> get _favorites => _works.where((w) => w.favorite).toList();

  List<WorkEntry> get _visibleLibraryWorks => widget.readerSettings.completedHidden
      ? _works.where((work) => !work.completed).toList() : _works;

  List<WorkEntry> get _recent => widget.library.works
      .where((w) => w.lastOpenedAt != null)
      .toList()
    ..sort((a, b) => (b.lastOpenedAt ?? '').compareTo(a.lastOpenedAt ?? ''));

  List<WorkEntry> get _downloaded =>
      _works.where((w) => _offlineKeys.contains(w.key)).toList();

  List<WorkEntry> get _results {
    final term = _search.text.trim().toLowerCase();
    if (term.isEmpty) return _works;
    return _works.where((w) {
      return [
        w.title, w.author, w.workId, ...w.collections,
      ].join(' ').toLowerCase().contains(term);
    }).toList();
  }

  KeyEventResult _onKeyboardShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit1) {
      _navigate(HypPage.home);
    } else if (event.logicalKey == LogicalKeyboardKey.digit2) {
      _navigate(HypPage.library);
    } else if (event.logicalKey == LogicalKeyboardKey.digit3) {
      _navigate(HypPage.favorites);
    } else if (event.logicalKey == LogicalKeyboardKey.digit4) {
      _navigate(HypPage.downloads);
    } else if (event.logicalKey == LogicalKeyboardKey.digit5) {
      _navigate(HypPage.settings);
    } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Only the Android root page traps system Back. Modal dialogs and
    // pushed GalleryReader routes are popped normally by Navigator.
    canPop: !Platform.isAndroid,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _handleSystemBack();
    },
    child: Focus(
    autofocus: true,
    onKeyEvent: _onKeyboardShortcut,
    child: LayoutBuilder(builder: (context, size) {
    final desktop = size.maxWidth >= 940;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: HypColors.background,
      drawer: desktop ? null : Drawer(
        backgroundColor: HypColors.background,
        child: SafeArea(child: _sidebar(closeDrawer: true)),
      ),
      appBar: desktop ? null : AppBar(
        backgroundColor: HypColors.background,
        title: const HypText('HYP Viewer'),
        actions: [
          IconButton(
            tooltip: '업데이트 확인',
            onPressed: widget.onCheckRelease,
            icon: const Icon(Icons.system_update_alt_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: '추가 메뉴',
            onSelected: _toolsAction,
            itemBuilder: (_) => _toolsMenu,
          ),
        ],
      ),
      body: Row(children: [
        if (desktop) SizedBox(
          width: 264, child: _sidebar(closeDrawer: false)),
        Expanded(child: Column(children: [
          if (desktop) _desktopHeader()
          else Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: _searchField(),
          ),
          if (widget.downloadingUpdate)
            LinearProgressIndicator(value: widget.updateProgress),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [
                    HypColors.background,
                    Color(0xFF10142B),
                    HypColors.background,
                  ],
                ),
              ),
              child: Stack(children: [
                Positioned.fill(child: _contents()),
                if (widget.message.isNotEmpty)
                  Positioned(
                    top: 8, left: 12, right: 12,
                    child: MouseRegion(
                      onEnter: (_) {
                        _notificationHovered = true;
                        _notificationTimer?.cancel();
                        _notificationExitTimer?.cancel();
                        if (!_notificationShown) setState(() => _notificationShown = true);
                      },
                      onExit: (_) {
                        _notificationHovered = false;
                        _scheduleNotificationTimer();
                      },
                      child: AnimatedOpacity(
                        opacity: _notificationShown ? 1 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Semantics(
                      liveRegion: true,
                      child: Material(
                        key: const Key('viewport-notification'),
                        color: HypColors.raised,
                        elevation: 12,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          child: Row(children: [
                            const Icon(Icons.info_outline_rounded,
                                color: HypColors.lightPurple, size: 19),
                            const SizedBox(width: 10),
                            Expanded(child: HypText(widget.message, maxLines: 4,
                                overflow: TextOverflow.ellipsis)),
                            IconButton(
                              tooltip: '알림 닫기',
                              onPressed: widget.onDismissMessage,
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    ),
                    ),
                  ),
              ]),
            ),
          ),
        ])),
      ]),
      bottomNavigationBar: desktop ? null : NavigationBar(
        backgroundColor: HypColors.surface,
        indicatorColor: HypColors.primary.withValues(alpha: 0.45),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        selectedIndex: [
          HypPage.favorites, HypPage.library, HypPage.home,
          HypPage.downloads, HypPage.settings,
        ].indexOf(_page).clamp(0, 4).toInt(),
        onDestinationSelected: (index) => _navigate([
          HypPage.favorites, HypPage.library, HypPage.home,
          HypPage.downloads, HypPage.settings,
        ][index]),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.favorite_outline),
            selectedIcon: const Icon(Icons.favorite),
            label: HypI18n.t(context, '즐겨찾기')),
          NavigationDestination(icon: const Icon(Icons.library_books_outlined),
            selectedIcon: const Icon(Icons.library_books),
            label: HypI18n.t(context, '서재')),
          NavigationDestination(icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: HypI18n.t(context, '홈')),
          NavigationDestination(icon: const Icon(Icons.download_outlined),
            selectedIcon: const Icon(Icons.download),
            label: HypI18n.t(context, '다운로드')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: HypI18n.t(context, '설정')),
        ],
      ),
    );
  }),
  ),
  );

  Widget _sidebar({required bool closeDrawer}) => Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 17),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: HypColors.border.withValues(alpha: 0.62)),
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF202754), HypColors.surface, Color(0xFF111732)],
      ),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: HypColors.primary),
            gradient: const LinearGradient(
              colors: [Color(0xFF443CA4), HypColors.background],
            ),
          ),
          child: const Icon(Icons.auto_stories_rounded,
            color: HypColors.lightPurple, size: 29),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HypText('HYP Viewer', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800)),
            SizedBox(height: 3),
            HypText('좋아하는 이야기를,\n더 가까이',
              style: TextStyle(color: HypColors.muted, fontSize: 11)),
          ],
        )),
      ]),
      const SizedBox(height: 25),
      for (final page in HypPage.values) ...[
        if (page == HypPage.settings) ...[
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Material(
            color: _page == page
                ? HypColors.primary.withValues(alpha: 0.66)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              key: Key('nav-' + page.name),
              borderRadius: BorderRadius.circular(11),
              onTap: () {
                _navigate(page);
                if (closeDrawer) Navigator.maybePop(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13, vertical: 13),
                child: Row(children: [
                  Icon(page.icon, size: 22,
                    color: _page == page ? Colors.white : HypColors.muted),
                  const SizedBox(width: 15),
                  HypText(page.label, style: TextStyle(
                    fontSize: 14,
                    color: HypColors.text,
                    fontWeight: _page == page
                        ? FontWeight.w800 : FontWeight.w500,
                  )),
                ]),
              ),
            ),
          ),
        ),
      ],
      const Spacer(),
      const Divider(),
      const SizedBox(height: 8),
      const HypText('오프라인 보관함',
        style: TextStyle(color: HypColors.muted, fontSize: 12)),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        minHeight: 6,
        backgroundColor: HypColors.border.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(9),
        value: widget.library.works.isEmpty
            ? 0 : (_offlineKeys.length / widget.library.works.length)
                .clamp(0.0, 1.0),
      ),
      const SizedBox(height: 8),
      HypText(
        '내 서재 ' + widget.library.works.length.toString() +
        '개 중 ' + _offlineKeys.length.toString() + '개 저장됨',
        style: const TextStyle(fontSize: 11, color: HypColors.muted),
      ),
    ]),
  );

  Widget _desktopHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(21, 22, 22, 16),
    child: Row(children: [
      Expanded(child: _searchField()),
      const SizedBox(width: 16),
      _toolIcon(Icons.download_outlined, 'JSON 백업',
          widget.onExportJson),
      const SizedBox(width: 8),
      _toolIcon(Icons.table_chart_outlined, 'Excel 내보내기',
          widget.onExportExcel),
      const SizedBox(width: 8),
      _toolIcon(Icons.notifications_outlined, '관리자 공지',
          widget.onCheckAnnouncements),
      const SizedBox(width: 8),
      _toolIcon(Icons.system_update_alt, '앱 업데이트', widget.onCheckRelease),
      const SizedBox(width: 8),
      PopupMenuButton<String>(
        tooltip: '추가 메뉴',
        color: HypColors.raised,
        onSelected: _toolsAction,
        itemBuilder: (_) => _toolsMenu,
        icon: const Icon(Icons.more_horiz_rounded, color: HypColors.text),
      ),
    ]),
  );

  Widget _toolIcon(IconData icon, String tooltip, VoidCallback handler) =>
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color: HypColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HypColors.border),
        ),
        child: IconButton(
          tooltip: tooltip, onPressed: handler,
          icon: Icon(icon, color: HypColors.text),
        ),
      );

  List<PopupMenuEntry<String>> get _toolsMenu => const [
    PopupMenuItem(value: 'settings', child: HypText('설정')),
    PopupMenuItem(value: 'history', child: HypText('열람 기록')),
    PopupMenuItem(value: 'backup', child: HypText('백업 설정')),
  ];

  void _toolsAction(String value) {
    if (value == 'settings') {
      _navigate(HypPage.settings);
    } else if (value == 'history') {
      _navigate(HypPage.history);
    } else if (value == 'backup') {
      _openBackupSettings();
    }
  }

  Widget _searchField() => TextField(
    key: const Key('library-search-input'),
    focusNode: _searchFocus,
    controller: _search,
    decoration: InputDecoration(
      hintText: HypI18n.t(context, '작품 제목, 작가, 번호, 목록으로 검색하세요...'),
      prefixIcon: Icon(Icons.search_rounded, color: HypColors.muted),
    ),
  );

  Widget _contents() {
    final pageContent = _search.text.trim().isNotEmpty
        ? _searchContent()
        : switch (_page) {
            HypPage.home => _homeContent(),
            HypPage.library => _libraryContent(),
            HypPage.favorites => _fullPage('즐겨찾기',
                '하트를 누른 작품만 모아 보여줘.',
                HypPage.favorites.icon, _favorites),
            HypPage.history => _fullPage('열람 기록',
                '최근 읽기 화면을 연 순서대로 표시해.',
                HypPage.history.icon, _recent),
            HypPage.downloads => _downloadsContent(),
            HypPage.settings => _settingsContent(),
          };
    return ListView(
      key: ValueKey(_search.text.trim().isEmpty ? _page.name : 'search'),
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 30),
      children: [pageContent],
    );
  }

  Widget _homeContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HypHeroBanner(
        artwork: widget.readerSettings.heroArtworkSource == 'custom'
            ? widget.heroArtwork : null,
        rotatingArtworks: widget.readerSettings.heroArtworkSource == 'random'
            ? _rotatingCoverKeys.map((key) => _coverImages[key]).toList()
            : null,
        rotatingArtworkKeys: widget.readerSettings.heroArtworkSource == 'random'
            ? List<String?>.from(_rotatingCoverKeys) : null,
        onHoverChanged: (hovered) => _bannerHovered = hovered,
        onOpenArtwork: (key) {
          final matching = widget.library.works.where((work) => work.key == key);
          if (matching.isEmpty) return;
          final work = matching.first;
          if (_offlineKeys.contains(work.key)) widget.onOpenGallery(work);
          else widget.onReadOnline(work);
        },
        onOpenLibrary: () => _navigate(HypPage.library),
        onOpenDownloads: () => _navigate(HypPage.downloads),
      ),
      const SizedBox(height: 17),
      ShortsFinderPanel(
        url: widget.urlInput,
        apiKey: widget.apiKeyInput,
        comment: widget.commentInput,
        workId: widget.numberInput,
        title: widget.titleInput,
        author: widget.authorInput,
        candidates: widget.candidates,
        busy: widget.busy,
        onAnalyze: widget.onAnalyze,
        onFetch: widget.onFetch,
        onOpenYoutube: widget.onOpenShortsInput,
        onSave: widget.onSaveWork,
        onQuickAddNumber: widget.onQuickAddNumber,
        onSaveSelectedWorks: widget.onSaveSelectedWorks,
        onVerifyCandidateCodes: widget.onVerifyCandidateCodes,
        onCrossLineFallback: widget.onCrossLineFallback,
      ),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: HypSectionTitle(
          icon: Icons.library_books_rounded,
          title: '최근 본 작품',
          subtitle: '최근 4개 · 접어서 숨길 수 있어.',
          actionLabel: '전체 보기',
          onAction: () => _navigate(HypPage.history),
        )),
        IconButton(
          key: const Key('recent-collapse-toggle'),
          tooltip: widget.readerSettings.recentCollapsed
              ? '최근 본 작품 펼치기' : '최근 본 작품 접기',
          onPressed: () => widget.onSaveReaderSettings(
            widget.readerSettings.copyWith(
                recentCollapsed: !widget.readerSettings.recentCollapsed)),
          icon: Icon(widget.readerSettings.recentCollapsed
              ? Icons.expand_more : Icons.expand_less),
        ),
      ]),
      if (!widget.readerSettings.recentCollapsed) const SizedBox(height: 12),
      if (!widget.readerSettings.recentCollapsed)
        _gridOrEmpty(
          _recent.take(4).toList(),
          emptyTitle: '아직 열람 기록이 없어',
          emptyMessage: '서재에 작품을 추가하고 읽기를 시작하면 여기에 표시돼.',
        ),
    ],
  );

  Widget _fullPage(String title, String subtitle, IconData icon,
          List<WorkEntry> works) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HypSectionTitle(icon: icon, title: title, subtitle: subtitle),
      const SizedBox(height: 15),
      _gridOrEmpty(
        works,
        emptyTitle: title + '에 표시할 작품이 없어',
        emptyMessage: '홈에서 번호를 찾아 저장하거나 서재에서 작품을 열어봐.',
      ),
    ],
  );

  /// One visual grid for both single works and stacked series covers.
  Widget _groupedLibraryGrid(List<WorkEntry> works) {
    if (works.isEmpty) {
      return _gridOrEmpty(works,
        emptyTitle: '내 서재에 작품이 없어',
        emptyMessage: '홈에서 작품을 저장해줘.');
    }
    final groups = <String, List<WorkEntry>>{};
    for (final work in works) {
      if (work.groupId.isNotEmpty) {
        groups.putIfAbsent(work.groupId, () => []).add(work);
      }
    }
    if (_openedGroupId != null) {
      final selected = groups[_openedGroupId];
      if (selected != null) {
        final ordered = [...selected]..sort((a, b) {
          if (a.groupOrder != b.groupOrder) {
            return a.groupOrder.compareTo(b.groupOrder);
          }
          return WorkGrouping.compareChapters(a, b);
        });
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              IconButton(key: const Key('library-group-back'),
                tooltip: '서재로 돌아가기',
                onPressed: () => setState(() => _openedGroupId = null),
                icon: const Icon(Icons.arrow_back)),
              Expanded(child: Text(
                ordered.first.groupTitle.isEmpty
                    ? '작품 묶음' : ordered.first.groupTitle,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium)),
              PopupMenuButton<String>(
                key: Key('work-group-menu-${_openedGroupId!}'),
                tooltip: '묶음 관리',
                onSelected: (action) => _groupAction(
                    action, _openedGroupId!, selected),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('묶음 이름 수정')),
                  PopupMenuItem(value: 'reorder', child: Text('회차 순서 변경')),
                  PopupMenuItem(value: 'ungroup', child: Text('묶음만 해제')),
                ]),
            ]),
            const SizedBox(height: 10),
            _gridOrEmpty(ordered, emptyTitle: '묶음이 비어 있어',
                emptyMessage: '다른 작품을 선택해서 추가해줘.'),
          ]);
      }
      _openedGroupId = null;
    }
    final entries = <Object>[];
    final seenGroups = <String>{};
    for (final work in works) {
      if (work.groupId.isEmpty) {
        entries.add(work);
      } else if (seenGroups.add(work.groupId)) {
        entries.add(work.groupId);
      }
    }
    return LayoutBuilder(builder: (context, size) {
      final w = size.maxWidth;
      final columns = w >= 1100 ? 5 : w >= 850 ? 4 :
          w >= 620 ? 3 : w >= 335 ? 2 : 1;
      return GridView.builder(
        key: const Key('library-mixed-grid'),
        itemCount: entries.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns, crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 1.15 : 0.68,
        ),
        itemBuilder: (context, index) {
          final entry = entries[index];
          if (entry is String) {
            final members = groups[entry]!;
            final ordered = [...members]
              ..sort((a,b) => a.groupOrder.compareTo(b.groupOrder));
            return HypWorkGroupCard(
              key: Key('work-group-$entry'),
              title: ordered.first.groupTitle.isEmpty
                  ? '작품 묶음' : ordered.first.groupTitle,
              members: ordered,
              coverImages: _coverImages,
              onOpen: () => setState(() => _openedGroupId = entry),
              onAction: (action) => _groupAction(action, entry, members),
            );
          }
          final work = entry as WorkEntry;
          return HypWorkCard(
            work: work,
            isOffline: _offlineKeys.contains(work.key),
            totalPages: _pageCounts[work.key],
            coverBytes: _coverImages[work.key],
            onOpen: () {
              if (_offlineKeys.contains(work.key)) {
                widget.onOpenGallery(work);
              } else {
                widget.onReadOnline(work);
              }
            },
            onAction: (action) => _workAction(action, work),
            selectionMode: _selectingWorks && _canSelectWorks,
            selected: _selectedWorkIds.contains(work.workId),
            onSelect: () => _toggleSelectedWork(work),
            onLongPress: () => _startSelection(work),
          );
        },
      );
    });
  }

  Future<void> _groupSelectedWorks() async {
    final selected = _works.where((w) =>
        _selectedWorkIds.contains(w.workId) && w.groupId.isEmpty).toList();
    if (selected.length < 2) return;
    selected.sort(WorkGrouping.compareChapters);
    final input = TextEditingController(
        text: WorkGrouping.normalizedSeries(selected.first.title));
    String? title;
    try {
      title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const HypText('선택한 작품 묶기'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(selected.length.toString() + '개 작품을 하나의 세트로 묶어.'),
            const SizedBox(height: 10),
            TextField(
              key: const Key('group-name-input'),
              controller: input,
              decoration: const InputDecoration(labelText: '묶음 이름')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const HypText('취소')),
            FilledButton(
              key: const Key('group-confirm'),
              onPressed: () => Navigator.pop(ctx, input.text.trim()),
              child: const HypText('묶음 만들기')),
          ],
        ),
      );
    } finally {
      input.dispose();
    }
    if (title == null || title.isEmpty || !mounted) return;
    await widget.onGroupWorks(
        selected.map((w) => w.workId).toList(), title);
    if (!mounted) return;
    setState(() {
      _selectedWorkIds.clear();
      _selectingWorks = false;
    });
  }

  Future<void> _showAutoGroupWizard() async {
    final suggestions = WorkGrouping.suggest(widget.library.works);
    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: HypText('새로 추천할 시리즈를 찾지 못했어. '
            '작품 정보의 제목·작가를 확인하거나 선택 묶기를 사용해 줘.')));
      return;
    }
    final confirmed = await showDialog<List<AutoGroupReview>>(
      context: context,
      builder: (dialog) => AutoGroupWizard(
        suggestions: suggestions,
        works: widget.library.works,
        coverImages: _coverImages,
      ),
    );
    if (confirmed == null || confirmed.isEmpty || !mounted) return;
    var saved = 0;
    for (final review in confirmed) {
      if (review.existingGroupId.isEmpty) {
        await widget.onGroupWorks(review.workIds, review.title);
        saved++;
      } else if (widget.onAddWorksToGroup != null) {
        try {
          await widget.onAddWorksToGroup!(
              review.existingGroupId, review.workIds);
          final original = widget.library.works.where((work) =>
              work.groupId == review.existingGroupId).toList();
          if (original.isNotEmpty &&
              original.first.groupTitle != review.title) {
            await widget.onRenameGroup(review.existingGroupId, review.title);
          }
          saved++;
        } catch (error) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('묶음 추가 실패: $error')));
        }
      }
    }
    if (mounted && saved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('선택한 묶음 $saved개 적용을 요청했어.')));
    }
  }

  Future<void> _groupAction(String action, String id,
      List<WorkEntry> members) async {
    if (action == 'ungroup') {
      final approve = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const HypText('묶음만 해제'),
          content: const HypText('작품·CBZ·읽기 기록은 그대로 두고 '
              '그룹 표시만 해제할까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const HypText('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const HypText('묶음 해제')),
          ],
        ),
      );
      if (approve == true) await widget.onUngroupWorks(id);
    } else if (action == 'rename') {
      final input = TextEditingController(text: members.first.groupTitle);
      try {
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const HypText('묶음 이름 수정'),
            content: TextField(
              key: const Key('group-rename-input'),
              controller: input),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: const HypText('취소')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, input.text.trim()),
                child: const HypText('저장')),
            ],
          ),
        );
        if (result != null && result.isNotEmpty) {
          await widget.onRenameGroup(id, result);
        }
      } finally {
        input.dispose();
      }
    } else if (action == 'reorder') {
      final ordered = [...members]..sort((a,b) =>
          a.groupOrder.compareTo(b.groupOrder));
      final result = await showDialog<List<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            title: const HypText('회차 순서 변경'),
            content: SizedBox(width: 440, height: 300,
              child: ListView.builder(
                itemCount: ordered.length,
                itemBuilder: (_, index) => ListTile(
                  title: Text((index + 1).toString() + '. ' +
                      ordered[index].title),
                  subtitle: Text('#' + ordered[index].workId),
                  trailing: Row(mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '위로',
                        onPressed: index == 0 ? null : () => update(() {
                          final item = ordered.removeAt(index);
                          ordered.insert(index - 1, item);
                        }),
                        icon: const Icon(Icons.arrow_upward)),
                      IconButton(
                        tooltip: '아래로',
                        onPressed: index == ordered.length - 1
                            ? null : () => update(() {
                          final item = ordered.removeAt(index);
                          ordered.insert(index + 1, item);
                        }),
                        icon: const Icon(Icons.arrow_downward)),
                    ]),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                  child: const HypText('취소')),
              FilledButton(
                onPressed: () => Navigator.pop(dialog,
                    ordered.map((w) => w.workId).toList()),
                child: const HypText('순서 저장')),
            ],
          ),
        ),
      );
      if (result != null) await widget.onReorderGroup(id, result);
    }
  }

  Widget _selectionControls(List<WorkEntry> visible) =>
      !_selectingWorks ? const SizedBox.shrink() : Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Wrap(spacing: 8, runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('선택됨: ' + _selectedWorkIds.length.toString() + '개'),
            OutlinedButton(
              key: const Key('library-select-visible'),
              onPressed: visible.isEmpty ? null : () => setState(() {
                // When searching, select ONLY current matching results;
                // never silently include previously selected hidden works.
                if (_search.text.trim().isNotEmpty) {
                  _selectedWorkIds.clear();
                }
                _selectedWorkIds.addAll(visible.map((w) => w.workId));
              }),
              child: const HypText('전체 선택'),
            ),
            OutlinedButton(
              key: const Key('library-clear-selection'),
              onPressed: _selectedWorkIds.isEmpty ? null
                  : () => setState(() => _selectedWorkIds.clear()),
              child: const HypText('선택 해제'),
            ),
            if (_page == HypPage.library)
              OutlinedButton.icon(
                key: const Key('library-group-selected'),
                onPressed: _selectedWorkIds.length < 2 ||
                    widget.library.works.any((work) =>
                      _selectedWorkIds.contains(work.workId) &&
                      work.groupId.isNotEmpty)
                    ? null : _groupSelectedWorks,
                icon: const Icon(Icons.bookmarks_outlined),
                label: const HypText('선택 묶기'),
              ),
            OutlinedButton.icon(
              key: const Key('library-edit-selected'),
              onPressed: _selectedWorkIds.length == 1
                  ? _editSelectedWork : null,
              icon: const Icon(Icons.edit_outlined),
              label: const HypText('정보 수정'),
            ),
            if (_page == HypPage.downloads) ...[
              FilledButton.icon(
                key: const Key('download-export-selected'),
                onPressed: _selectedWorkIds.isNotEmpty
                    ? () => widget.onExportSelectedDownloads(
                        _selectedWorkIds.toList()) : null,
                icon: const Icon(Icons.folder_outlined),
                label: const HypText('선택 CBZ 폴더로 내보내기'),
              ),
              OutlinedButton.icon(
                key: const Key('download-delete-selected'),
                onPressed: _selectedWorkIds.isNotEmpty ? () async {
                  await widget.onDeleteSelectedOffline(
                      _selectedWorkIds.toList());
                  if (mounted) {
                    setState(() => _selectedWorkIds.clear());
                    await _refreshOffline();
                  }
                } : null,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const HypText('선택 CBZ 삭제'),
              ),
            ]
            else
              FilledButton.icon(
                key: const Key('library-delete-selected'),
                onPressed: _selectedWorkIds.isNotEmpty
                    ? _removeSelectedWorks : null,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const HypText('선택 삭제'),
              ),
          ],
        ),
      );

  Widget _libraryContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HypSectionTitle(
        icon: Icons.library_books_rounded,
        title: '내 서재',
        subtitle: '추가한 작품과 읽기 진행도를 관리하세요.',
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          key: const Key('library-sort'),
          initialValue: widget.readerSettings.librarySort,
          decoration: InputDecoration(
            isDense: true, labelText: HypI18n.t(context, '서재 정렬')),
          items: const [
            DropdownMenuItem(value: 'newest',
                child: HypText('최신 추가순')),
            DropdownMenuItem(value: 'published',
                child: HypText('출시순 (히토미 등록일)')),
            DropdownMenuItem(value: 'hitomiPopular',
                child: HypText('히토미 인기순')),
            DropdownMenuItem(value: 'mostRead',
                child: HypText('인기 (내 열람 횟수)')),
            DropdownMenuItem(value: 'title', child: HypText('이름순')),
            DropdownMenuItem(value: 'number', child: HypText('번호순')),
          ],
          onChanged: (value) {
            if (value != null) widget.onSaveReaderSettings(
              widget.readerSettings.copyWith(librarySort: value));
          },
        )),
        IconButton(
          key: const Key('library-sort-direction'),
          tooltip: '정렬 방향 바꾸기',
          onPressed: () => widget.onSaveReaderSettings(
              widget.readerSettings.copyWith(
                librarySortDescending:
                    !widget.readerSettings.librarySortDescending)),
          icon: Icon(widget.readerSettings.librarySortDescending
              ? Icons.arrow_upward : Icons.arrow_downward),
        ),
      ]),
      if (widget.readerSettings.librarySort == 'hitomiPopular')
        Padding(padding: const EdgeInsets.only(top: 7), child: Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            key: const Key('library-popularity-period'),
            initialValue: widget.readerSettings.popularityPeriod,
            decoration: const InputDecoration(isDense: true,
                labelText: '히토미 인기 기간'),
            items: const [
              DropdownMenuItem(value: 'today', child: Text('일간')),
              DropdownMenuItem(value: 'week', child: Text('주간')),
              DropdownMenuItem(value: 'month', child: Text('월간')),
              DropdownMenuItem(value: 'year', child: Text('연간')),
            ],
            onChanged: (period) {
              if (period != null) widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(popularityPeriod: period));
            },
          )),
          IconButton(tooltip: '인기 순위 새로고침',
              onPressed: _popularityBusy ? null :
                  () => _loadPopularity(refresh: true),
              icon: const Icon(Icons.refresh)),
        ])),
      if (widget.readerSettings.librarySort == 'published')
        Align(alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _publicationBusy ? null :
                () => _loadPublicationDates(refresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('등록일 다시 가져오기'),
          )),
      if (_popularityBusy || _publicationBusy) const LinearProgressIndicator(),
      if (_sortLoadError != null &&
          {'hitomiPopular', 'published'}.contains(widget.readerSettings.librarySort))
        Padding(padding: const EdgeInsets.only(top: 5),
          child: Text(_sortLoadError!,
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          key: const Key('library-select-mode'),
          onPressed: _toggleSelectionMode,
          icon: Icon(_selectingWorks
              ? Icons.close : Icons.checklist_outlined),
          label: HypText(_selectingWorks ? '선택 종료' : '선택'),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          key: const Key('library-group-auto'),
          onPressed: widget.library.works.length < 2
              ? null : _showAutoGroupWizard,
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const HypText('Auto 묶기'),
        )),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          key: const Key('library-download-all'),
          onPressed: widget.library.works.isEmpty
              ? null : widget.onDownloadAll,
          icon: const Icon(Icons.download_for_offline_outlined),
          label: const HypText('전체 다운로드'),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          key: const Key('library-completed-toggle'),
          onPressed: () => widget.onSaveReaderSettings(
            widget.readerSettings.copyWith(
                completedHidden: !widget.readerSettings.completedHidden)),
          icon: Icon(widget.readerSettings.completedHidden
              ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          label: HypText(widget.readerSettings.completedHidden
              ? '완독 표시' : '완독 숨기기'),
        )),
      ]),
      _selectionControls(_visibleLibraryWorks),
      const SizedBox(height: 8),
      _groupedLibraryGrid(_visibleLibraryWorks),
    ],
  );

  Widget _searchContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          key: const Key('search-select-mode'),
          onPressed: _toggleSelectionMode,
          icon: Icon(_selectingWorks
              ? Icons.close : Icons.checklist_outlined),
          label: HypText(_selectingWorks ? '선택 종료' : '선택'),
        ),
      ),
      _selectionControls(_results),
      _fullPage(
        '검색 결과',
        '"' + _search.text + '" · ' + _results.length.toString() + '개 작품',
        Icons.search_rounded,
        _results,
      ),
    ],
  );

  Widget _gridOrEmpty(List<WorkEntry> works, {
    required String emptyTitle,
    required String emptyMessage,
  }) {
    if (works.isEmpty) {
      return HypEmptyState(
        icon: Icons.auto_stories_outlined,
        title: emptyTitle,
        message: emptyMessage,
        actionLabel: '내 서재 보기',
        onAction: () => _navigate(HypPage.library),
      );
    }
    return HypWorkGrid(
      works: works,
      offlineKeys: _offlineKeys,
      pageCounts: _pageCounts,
      coverImages: _coverImages,
      onOpen: (work) {
        if (_offlineKeys.contains(work.key)) {
          widget.onOpenGallery(work);
        } else {
          widget.onReadOnline(work);
        }
      },
      onAction: _workAction,
      selectionMode: _selectingWorks && _canSelectWorks,
      selectedWorkIds: _selectedWorkIds,
      onSelect: _canSelectWorks ? _toggleSelectedWork : null,
      onLongPress: _canSelectWorks ? _startSelection : null,
    );
  }

  void _workAction(String action, WorkEntry work) async {
    if (action == 'offline') {
      await widget.onOpenGallery(work);
    } else if (action == 'online') {
      await widget.onReadOnline(work);
    } else if (action == 'page') {
      await widget.onReadWebPage(work);
    } else if (action == 'download') {
      await widget.onDownloadOnline(work);
      await _refreshOffline();
    } else if (action == 'download_json') {
      await widget.onDownloadJsonSource(work);
      await _refreshOffline();
    } else if (action == 'delete_offline') {
      await widget.onDeleteOffline(work);
      await _refreshOffline();
    } else if (action == 'delete_work') {
      await widget.onDeleteWork(work);
      await _refreshOffline();
    } else if (action == 'import') {
      await widget.onImportGallery(work);
      await _refreshOffline();
    } else if (action == 'cover') {
      await widget.onChooseCover(work);
      await _refreshOffline();
    } else if (action == 'edit_details') {
      await widget.onEditWorkDetails(work);
      await _refreshOffline();
    } else if (action == 'info') {
      await widget.onShowWorkInfo(work);
      await _refreshOffline();
    } else if (action == 'favorite') {
      await widget.onUpdateWork(work.copyWith(favorite: !work.favorite));
    } else if (action == 'original') {
      await widget.onOpenOriginal(work);
    }
  }

  Future<WorkEntry?> _chooseLibraryWork(String purpose) async {
    if (widget.library.works.isEmpty) return null;
    final input = TextEditingController();
    try {
      return await showDialog<WorkEntry>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (dialog, update) {
            final term = input.text.trim().toLowerCase();
            final works = _works.where((w) => [
              w.workId, w.title, w.author,
            ].join(' ').toLowerCase().contains(term)).toList();
            return AlertDialog(
              title: Text(purpose),
              content: SizedBox(
                width: 460, height: 380,
                child: Column(children: [
                  TextField(controller: input,
                    decoration: const InputDecoration(
                      labelText: '작품 번호 또는 제목로 검색'),
                    onChanged: (_) => update(() {})),
                  const SizedBox(height: 8),
                  Expanded(child: ListView.builder(
                    itemCount: works.length,
                    itemBuilder: (_, i) => ListTile(
                      title: HypText(works[i].title),
                      subtitle: Text('#' + works[i].workId),
                      onTap: () => Navigator.pop(dialog, works[i]),
                    ),
                  )),
                ]),
              ),
              actions: [TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const HypText('취소'))],
            );
          },
        ),
      );
    } finally {
      input.dispose();
    }
  }

  Future<void> _connectArchiveFromDownloads() async {
    final chosen = await _chooseLibraryWork('CBZ/ZIP을 연결할 작품');
    if (chosen == null || !mounted) return;
    await widget.onImportGallery(chosen);
    await _refreshOffline();
  }

  Future<void> _downloadSourceFromDownloads() async {
    final chosen = await _chooseLibraryWork('추가 JSON 소스로 받을 작품');
    if (chosen == null || !mounted) return;
    await widget.onDownloadJsonSource(chosen);
    await _refreshOffline();
  }

  Widget _downloadsContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HypSectionTitle(
        icon: Icons.download_rounded,
        title: '다운로드',
        subtitle: '내 기기에 저장된 작품 ' + _downloaded.length.toString() + '개',
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const Key('download-select-mode'),
          onPressed: _toggleSelectionMode,
          icon: Icon(_selectingWorks ? Icons.close : Icons.checklist_outlined),
          label: HypText(_selectingWorks ? '선택 종료' : '선택'),
        ),
        OutlinedButton.icon(
          key: const Key('download-import-cbz'),
          onPressed: widget.library.works.isEmpty
              ? null : _connectArchiveFromDownloads,
          icon: const Icon(Icons.folder_open_outlined),
          label: const HypText('CBZ/ZIP 연결'),
        ),
        OutlinedButton.icon(
          key: const Key('download-json-source'),
          onPressed: widget.library.works.isEmpty
              ? null : _downloadSourceFromDownloads,
          icon: const Icon(Icons.data_object_outlined),
          label: const HypText('고급 JSON 소스 다운로드'),
        ),
      ]),
      _selectionControls(_downloaded),
      const SizedBox(height: 15),
      if (widget.queuedDownloadCount > 0) ...[
        HypPanel(child: Row(children: [
          Expanded(child: HypText(
            '추가 다운로드 대기: ${widget.queuedDownloadCount}개 작품',
            key: const Key('download-queue-count'),
          )),
          TextButton.icon(
            key: const Key('cancel-download-queue'),
            onPressed: widget.onCancelGalleryDownload,
            icon: const Icon(Icons.close_rounded),
            label: const HypText('대기열 취소'),
          ),
        ])),
        const SizedBox(height: 12),
      ],
      if (widget.downloadingGalleryKey != null) ...[
        HypPanel(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HypText('작품 다운로드 중',
              style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: widget.totalGalleryPages > 0
                  ? widget.downloadedGalleryPages / widget.totalGalleryPages
                  : null,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: HypText(
                widget.downloadedGalleryPages.toString() + ' / ' +
                widget.totalGalleryPages.toString() + '장 · ' +
                (widget.downloadedGalleryBytes / 1048576).toStringAsFixed(1) +
                ' MB',
              )),
              if (widget.downloadCanPause)
                TextButton.icon(
                  onPressed: widget.onToggleDownloadPause,
                  icon: Icon(widget.downloadPaused ? Icons.play_arrow : Icons.pause),
                  label: HypText(widget.downloadPaused ? '계속' : '일시정지'),
                ),
              TextButton.icon(
                onPressed: widget.onCancelGalleryDownload,
                icon: const Icon(Icons.close),
                label: const HypText('취소'),
              ),
            ]),
          ],
        )),
        const SizedBox(height: 16),
      ],
      _gridOrEmpty(_downloaded,
        emptyTitle: '다운로드한 작품이 없어',
        emptyMessage: '서재에서 다운로드하거나 CBZ/ZIP을 연결하면 이곳에 표시돼.',
      ),
    ],
  );

  Future<void> _chooseCoverFromSettings() async {
    if (widget.library.works.isEmpty) return;
    final search = TextEditingController();
    WorkEntry? selected;
    try {
      selected = await showDialog<WorkEntry>(
        context: context,
        builder: (_) => StatefulBuilder(builder: (ctx, refresh) {
          final term = search.text.trim().toLowerCase();
          final filtered = widget.library.works.where((work) =>
            work.workId.contains(term) ||
            work.title.toLowerCase().contains(term)).toList();
          return AlertDialog(
            title: const HypText('표지를 바꿀 작품 선택'),
            content: SizedBox(
              width: 500,
              height: 420,
              child: Column(children: [
                TextField(
                  key: const Key('cover-work-search'),
                  controller: search,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: HypI18n.t(context, '작품 번호 또는 제목'),
                  ),
                  onChanged: (_) => refresh(() {}),
                ),
                const SizedBox(height: 10),
                Expanded(child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, index) {
                    final work = filtered[index];
                    return ListTile(
                      title: HypText(work.title.isEmpty ? '작품 ' + work.workId : work.title),
                      subtitle: HypText('번호 ' + work.workId),
                      onTap: () => Navigator.pop(ctx, work),
                    );
                  },
                )),
              ]),
            ),
            actions: [TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const HypText('취소'),
            )],
          );
        }),
      );
    } finally {
      search.dispose();
    }
    if (selected != null) {
      await widget.onChooseCover(selected);
      await _refreshOffline();
    }
  }

  void _applyPreloadSetting() {
    final pages = int.tryParse(_preloadInput.text.trim());
    if (pages == null || pages < -1 || pages > 1500) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const HypText('미리 로딩은 -1 또는 0~1500 사이 숫자로 입력해줘.'),
      ));
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onSaveReaderSettings(
      widget.readerSettings.copyWith(preloadPages: pages));
  }

  Widget _settingsPanel(String id, String title, Widget content) {
    final expanded = widget.readerSettings.expandedSettings.contains(id);
    return Container(
      key: id == 'backup' ? _backupSectionKey : null,
      child: HypPanel(child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
        key: Key('settings-section-' + id + (expanded ? '-open' : '-closed')),
        initiallyExpanded: expanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 9),
        title: HypText(title,
            style: Theme.of(context).textTheme.titleMedium),
        onExpansionChanged: (opening) {
          final enabled = widget.readerSettings.expandedSettings.toSet();
          if (opening) {
            enabled.add(id);
          } else {
            enabled.remove(id);
          }
          widget.onSaveReaderSettings(widget.readerSettings.copyWith(
              expandedSettings: enabled.toList()));
        },
        children: [content],
      ))),
    );
  }

  Widget _settingsContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const HypSectionTitle(
        icon: Icons.settings_rounded,
        title: '설정',
        subtitle: '뷰어 조작, 기본 표지, 추가 다운로드 소스와 앱 데이터를 관리해.',
      ),
      const SizedBox(height: 14),
      _settingsPanel('general', '언어·일반', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HypText('언어', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('app-language-setting'),
            initialValue: widget.readerSettings.languageCode,
            decoration: InputDecoration(
              labelText: HypI18n.t(context, '앱 언어'),
            ),
            // Native names are deliberately NOT translated by the selected
            // language: the chooser always reads 한국어 / English / 日本語.
            items: const [
              DropdownMenuItem(value: 'ko', child: Text('한국어')),
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'ja', child: Text('日本語')),
            ],
            onChanged: (language) {
              if (language != null) {
                widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(languageCode: language));
              }
            },
          ),
          const SizedBox(height: 7),
          const HypText('언어를 바꾸면 메뉴와 버튼에 즉시 적용되고 다음 실행에도 유지돼.',
              style: TextStyle(fontSize: 12, color: HypColors.muted)),
        ],
      )),
      const SizedBox(height: 10),
      _settingsPanel('hero', '홈 배너', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HypText('홈 배너 일러스트',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(
            key: const Key('hero-artwork-source-setting'),
            initialValue: widget.readerSettings.heroArtworkSource,
            decoration: InputDecoration(
              labelText: HypI18n.t(context, '홈 배너 배경 선택'),
            ),
            items: const [
              DropdownMenuItem(value: 'default',
                  child: HypText('기본 디자인')),
              DropdownMenuItem(value: 'custom',
                  child: HypText('직접 업로드한 일러스트')),
              DropdownMenuItem(value: 'random',
                  child: HypText('내 서재 표지 중 랜덤')),
            ],
            onChanged: (source) {
              if (source != null) {
                widget.onSaveReaderSettings(
                  widget.readerSettings.copyWith(heroArtworkSource: source));
              }
            },
          ),
          if (widget.readerSettings.heroArtworkSource == 'random') ...[
            const SizedBox(height: 10),
            if (_coverImages[_rotatingCoverKeys.first] != null)
              ClipRRect(
                key: const Key('random-hero-preview'),
                borderRadius: BorderRadius.circular(9),
                child: Image.memory(_coverImages[_rotatingCoverKeys.first]!,
                  height: 125, fit: BoxFit.cover, cacheWidth: 1000),
              )
            else
              const HypText('사용 가능한 서재 이미지 표지가 없어. '
                  '표지를 직접 설정하거나 첫 페이지 표지를 생성해줘.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('hero-random-refresh'),
              onPressed: _coverImages.isEmpty ? null : _shuffleBannerCover,
              icon: const Icon(Icons.shuffle),
              label: const HypText('다른 서재 표지 무작위 선택'),
            ),
          ],
          const SizedBox(height: 9),
          const HypText('첫 화면의 "좋아하는 이야기를, 언제 어디서나" '
              '배경 일러스트를 직접 설정할 수 있어.',
              style: TextStyle(fontSize: 12, color: HypColors.muted)),
          const SizedBox(height: 11),
          if (widget.heroArtwork != null) ...[
            ClipRRect(
              key: const Key('hero-artwork-preview'),
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(height: 130,
                child: Image.memory(widget.heroArtwork!, fit: BoxFit.cover,
                    width: double.infinity, cacheWidth: 1200,
                    gaplessPlayback: true)),
            ),
            const SizedBox(height: 9),
          ],
          Wrap(spacing: 10, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const Key('hero-artwork-upload'),
              onPressed: widget.onChooseHeroArtwork,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: HypText(widget.heroArtwork == null
                  ? '일러스트 업로드' : '일러스트 교체'),
            ),
            if (widget.heroArtwork != null)
              TextButton.icon(
                key: const Key('hero-artwork-reset'),
                onPressed: widget.onClearHeroArtwork,
                icon: const Icon(Icons.restore_rounded),
                label: const HypText('기본 배경으로 되돌리기'),
              ),
          ]),
          const SizedBox(height: 7),
          const HypText('PNG · JPG · WebP (최대 12MB). 이미지 자체는 '
              '이 기기에 저장되며 JSON 통합 백업에서 선택적으로 포함할 수 있어.',
              style: TextStyle(fontSize: 12, color: HypColors.muted)),
        ],
      )),
      const SizedBox(height: 10),
      _settingsPanel('viewer', '뷰어·로딩 설정', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HypText('이미지 뷰어 설정', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const HypText('읽기 방향을 정하면 화면 스와이프와 방향키도 함께 적용돼.',
            style: TextStyle(fontSize: 12, color: HypColors.muted)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const Key('reader-direction-setting'),
            initialValue: widget.readerSettings.nextDirection,
            decoration: InputDecoration(labelText: HypI18n.t(context, '다음 페이지로 넘기는 방향')),
            items: const [
              DropdownMenuItem(value: 'left',
                  child: HypText('왼쪽으로 넘기기 (→ 다음 페이지)')),
              DropdownMenuItem(value: 'right',
                  child: HypText('오른쪽으로 넘기기 (← 다음 페이지)')),
            ],
            onChanged: (v) {
              if (v != null) widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(nextDirection: v));
            },
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('open-after-save-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('서재 추가 후 작품 자동 열기'),
              subtitle: const HypText('기본값은 끔. 켜면 한 작품을 저장한 직후 뷰어를 열어. '
                  '여러 작품을 한 번에 저장하면 서재로 이동해.'),
              value: widget.readerSettings.openAfterSave,
              onChanged: (v) => widget.onSaveReaderSettings(
                  widget.readerSettings.copyWith(openAfterSave: v)),
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('auto-download-on-save-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('서재에 추가할 때 자동 다운로드'),
              subtitle: const HypText('기본값은 꺼짐. 권한 확인 후 새 작품을 '
                  '순서대로 다운로드하고 기존 CBZ는 건너뛰어.'),
              value: widget.readerSettings.autoDownloadOnSave,
              onChanged: widget.onSetAutoDownload,
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('reader-tap-navigation-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('화면 좌우 터치로 페이지 넘기기 (기본 켜짐)'),
              subtitle: const HypText('왼쪽 30%는 이전 페이지, 오른쪽 30%는 다음 페이지. '
                  '가운데 40%는 화면 UI 숨김·표시. 기존에 꺼둔 설정은 유지돼.'),
              value: widget.readerSettings.tapNavigation,
              onChanged: (v) => widget.onSaveReaderSettings(
                  widget.readerSettings.copyWith(tapNavigation: v)),
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('reader-webtoon-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('웹툰형 연속 세로 보기'),
              subtitle: const HypText('페이지 간 간격 없이 아래로 계속 스크롤해. '
                  '켜면 2쪽 모아보기보다 우선 적용돼.'),
              value: widget.readerSettings.webtoonMode,
              onChanged: (v) => widget.onSaveReaderSettings(
                  widget.readerSettings.copyWith(webtoonMode: v)),
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('reader-two-page-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('2쪽 모아보기'),
              subtitle: const HypText('1-2, 3-4처럼 두 페이지를 한 화면에 표시'),
              value: widget.readerSettings.twoPageSpread,
              onChanged: (v) => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(twoPageSpread: v)),
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('reader-vertical-scroll-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('세로로 페이지 넘기기'),
              subtitle: const HypText('뷰어 오른쪽 위의 가로/세로 전환 버튼과 '
                  '같은 설정이야. 종료 후에도 유지돼. '
                  '2쪽 모아보기는 가로로 표시돼.'),
              value: widget.readerSettings.verticalScrolling,
              onChanged: (v) => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(verticalScrolling: v)),
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              key: const Key('reader-toolbar-settings'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const HypText('뷰어 오른쪽 위 아이콘 구성'),
            subtitle: const HypText('각 버튼을 표시하거나 숨길 수 있어. 기본값은 모두 표시야.'),
            children: [
              SwitchListTile.adaptive(
                key: const Key('reader-show-download-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const HypText('다운로드 버튼 표시'),
                subtitle: const HypText('온라인 이미지 저장 버튼'),
                value: widget.readerSettings.showDownloadAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showDownloadAction: v)),
              ),
              SwitchListTile.adaptive(
                key: const Key('reader-show-cover-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const HypText('표지 지정 버튼 표시'),
                subtitle: const HypText('현재 페이지를 표지로 등록하는 버튼'),
                value: widget.readerSettings.showCoverAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showCoverAction: v)),
              ),
              SwitchListTile.adaptive(
                key: const Key('reader-show-page-controls-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const HypText('페이지 도구 버튼 표시'),
                subtitle: const HypText('하단 페이지 바 표시/숨기기 버튼'),
                value: widget.readerSettings.showPageControlsAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showPageControlsAction: v)),
              ),
              SwitchListTile.adaptive(
                key: const Key('reader-show-web-reader-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const HypText('웹 리더 버튼 표시'),
                subtitle: const HypText('현재 페이지를 브라우저에서 열기'),
                value: widget.readerSettings.showWebReaderAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showWebReaderAction: v)),
              ),
              SwitchListTile.adaptive(
                key: const Key('reader-show-orientation-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const HypText('가로/세로 전환 버튼 표시'),
                subtitle: const HypText('뷰어 오른쪽 위 전환 버튼'),
                value: widget.readerSettings.showOrientationAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showOrientationAction: v)),
              ),
            ],
          )),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(child: TextField(
              key: const Key('reader-preload-setting'),
              controller: _preloadInput,
              keyboardType: const TextInputType.numberWithOptions(
                  signed: true),
              decoration: InputDecoration(
                labelText: HypI18n.t(context, '앞뒤 미리 로딩 페이지'),
                helperText: HypI18n.t(context,
                    '직접 입력: 0~1500 / -1은 전체 로딩 (임시 디스크 캐시)'),
              ),
              onSubmitted: (_) => _applyPreloadSetting(),
            )),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('reader-preload-apply'),
              onPressed: _applyPreloadSetting,
              child: const HypText('적용'),
            ),
          ]),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            key: const Key('data-saver-setting'),
            contentPadding: EdgeInsets.zero,
            title: const HypText('데이터 절약 모드'),
            subtitle: const HypText('켜면 -1 전체 로딩을 잠시 멈추고 '
                '보이는 페이지와 다음 1장 위주로 요청해. '
                '동시 네트워크 요청도 1개로 제한해.'),
            value: widget.readerSettings.dataSaverMode,
            onChanged: (v) => widget.onSaveReaderSettings(
              widget.readerSettings.copyWith(dataSaverMode: v)),
          ),
          const SizedBox(height: 8),
          const HypText(
            '키보드(뷰어): ← / →, PageUp / PageDown, Space, Home / End, '
            'Esc(닫기). 서재의 작품 메뉴에서 표지 선택 가능.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
        ],
      )),
      const SizedBox(height: 10),
      _settingsPanel('cover', '표지 관리', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HypText('표지 자동 설정 및 편집', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Material(color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('automatic-cover-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('새 작품의 첫 페이지를 자동 표지로 사용'),
              subtitle: const HypText('끄면 새 작품은 기본 디자인 표지로 시작해. '
                  '기존에 직접 지정한 표지는 바뀌지 않아.'),
              value: widget.readerSettings.autoCoverEnabled,
              onChanged: (v) => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(autoCoverEnabled: v)),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('settings-cover-manager'),
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _chooseCoverFromSettings,
            label: const HypText('서재 작품 표지 편집 · 이미지 업로드 및 자르기'),
          ),
          const SizedBox(height: 8),
          const HypText('이미지를 선택하거나 작품 페이지를 불러온 뒤, '
              '미리보기 영역에서 드래그·확대·축소하여 표지를 만들 수 있어.',
              style: TextStyle(fontSize: 12, color: HypColors.muted)),
        ],
      )),
      const SizedBox(height: 13),
      _settingsPanel('android', 'Android 동작', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HypText('Android 뷰어 동작', style: Theme.of(context).textTheme.titleMedium),
          Material(color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('volume-keys-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('볼륨키로 페이지 넘기기'),
              subtitle: const HypText('뷰어가 열려 있을 때 볼륨+는 이전, '
                  '볼륨−는 다음 페이지. 소리 조절은 일시적으로 대신 사용돼.'),
              value: widget.readerSettings.volumeKeyNavigation,
              onChanged: (v) => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(volumeKeyNavigation: v)),
            ),
          ),
          Material(color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('landscape-spread-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('2쪽 보기에서 가로 화면 고정'),
              subtitle: const HypText('Android에서 2쪽 모아보기일 때만 가로 방향으로 열어. '
                  '끄면 휴대폰을 돌려 자유롭게 회전할 수 있어.'),
              value: widget.readerSettings.forceLandscapeForSpreads,
              onChanged: (v) => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(forceLandscapeForSpreads: v)),
            ),
          ),
        ],
      )),
      const SizedBox(height: 13),
      _settingsPanel('notices', '공지', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HypText('관리자 공지', style: Theme.of(context).textTheme.titleMedium),
          Material(color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('announcements-setting'),
              contentPadding: EdgeInsets.zero,
              title: const HypText('관리자 공지 수신 (동의)'),
              subtitle: const HypText('앱 실행 중이나 재실행 시 공개 공지를 확인해. '
                  '앱을 종료한 상태의 시스템 푸시 알림은 아직 지원하지 않아.'),
              value: widget.readerSettings.receiveAnnouncements,
              onChanged: (v) => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(receiveAnnouncements: v)),
            ),
          ),
          OutlinedButton.icon(
            key: const Key('announcements-open'),
            onPressed: widget.onCheckAnnouncements,
            icon: const Icon(Icons.campaign_outlined),
            label: const HypText('공지 목록 확인'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('android-security-help'),
            onPressed: widget.onSecurityHelp,
            icon: const Icon(Icons.security),
            label: const HypText('Android 설치 및 보안 위험 자동 차단 안내'),
          ),
        ],
      )),
      const SizedBox(height: 13),
      _settingsPanel('web', '기본 웹 리더', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HypText('기본 웹 리더 (주소 고정)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 7),
          const HypText(
            '기본 온라인 읽기는 이미지 메타데이터를 이용해 앱 안에서 열어. '
            '작품 메뉴의 웹 리더를 선택하면 브라우저에서 고정 링크를 열 수 있어. '
            '1페이지는 #1-, 2페이지부터는 #2-3 형식이야.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
          const SizedBox(height: 8),
          const SelectableText('https://hitomi.la/reader/{workId}.html#1-'),
          const SizedBox(height: 4),
          const HypText(
            '앱 안에서 읽는 경우에는 페이지 진행도가 저장돼. '
            '외부 브라우저에서 넘긴 페이지는 자동 기록되지 않아.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
        ],
      )),
      const SizedBox(height: 13),
      _settingsPanel('source', '추가 이미지 소스', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HypText('추가 JSON 이미지 소스 (선택)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 7),
          const HypText(
            '자체 보유하거나 이용 허가된 JSON 이미지 서버를 통해 오프라인 저장하려는 경우에만 설정해줘. 기본 온라인 읽기나 웹 리더에 필요하지 않아.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('online-source-input'),
            controller: widget.onlineSourceInput,
            decoration: InputDecoration(
              labelText: HypI18n.t(context, '추가 JSON 소스 URL 패턴'),
              hintText: HypI18n.t(context, 'https://gallery.example/galleries/{workId}.json'),
              helperText: HypI18n.t(context, '추가 JSON 소스로 다운로드할 때만 사용하는 고급 설정이야.'),
            ),
          ),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: widget.onSaveOnlineSource,
              icon: const Icon(Icons.save_outlined),
              label: const HypText('소스 설정 저장'),
            )),
        ],
      )),
      const SizedBox(height: 13),
      _settingsPanel('backup', '서재 데이터·백업', Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HypText('서재 데이터', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('library-restore-previous'),
            onPressed: widget.onRestorePreviousLibrary,
            icon: const Icon(Icons.restore_page_outlined),
            label: const HypText('이전 서재 백업에서 복구'),
          ),
          const SizedBox(height: 6),
          const HypText('JSON은 백업·기기 이전용, Excel은 확인용이야.',
            style: TextStyle(fontSize: 12, color: HypColors.muted)),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
              onPressed: widget.onExportJson,
              icon: const Icon(Icons.file_download_outlined),
              label: const HypText('JSON 백업'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onImportJson,
              icon: const Icon(Icons.file_upload_outlined),
              label: const HypText('JSON 가져오기'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onExportExcel,
              icon: const Icon(Icons.table_chart_outlined),
              label: const HypText('Excel 내보내기'),
            ),
          ]),
        ],
      )),
      const SizedBox(height: 13),
      _settingsPanel('updates', '업데이트', Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HypText('업데이트', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const HypText('최신 0.x 업데이트 · GitHub Releases',
            style: TextStyle(color: HypColors.muted, fontSize: 12)),
          const SizedBox(height: 9),
          HypText('현재 버전: ${widget.appVersion}',
              key: const Key('app-version-label'),
              style: const TextStyle(color: HypColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onCheckRelease,
            icon: const Icon(Icons.system_update_alt_rounded),
            label: const HypText('업데이트 확인'),
          ),
        ],
      )),
    ],
  );
}
