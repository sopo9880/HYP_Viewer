import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import '../core/download_failure_store.dart';
import '../core/hitomi_gallery.dart';
import '../core/hitomi_popularity.dart';

import '../core/hero_cover_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/gallery.dart';
import '../core/cover_store.dart';
import '../core/reader_settings.dart';
import 'windows_dpi_panel.dart';
import 'android_dpi_panel.dart';
import '../core/i18n.dart';
import '../l10n/app_localizations.dart';
import '../core/number_extractor.dart';
import '../core/online_search.dart';
import '../core/hitomi_web_search.dart';
import 'hitomi_web_search_page.dart';
import 'auto_hitomi_web_search.dart';
import '../core/online_edition_groups.dart';
import '../core/reading_history.dart';
import 'reading_insights.dart';
import 'candidate_editor.dart';
import '../core/work.dart';
import '../core/blacklist.dart';
import 'blacklist_manager.dart';
import '../core/work_grouping.dart';
import '../core/work_editions.dart';
import '../core/title_alias_index.dart';
import '../core/local_search.dart';
import 'reader_navigation_focus.dart';
import 'work_edition_card.dart';
import 'hero_banner.dart';
import 'hyp_theme.dart';
import 'edition_finder_dialog.dart';
import 'shorts_finder_panel.dart';
import 'work_cards.dart';
import 'auto_group_wizard.dart';
import 'work_group_card.dart';
import 'hyp_animated_title.dart';
import 'failed_downloads_panel.dart';

enum HypPage { home, library, favorites, downloads, history, settings }

extension HypPageInfo on HypPage {
  String get label => switch (this) {
    HypPage.home => '홈',
    HypPage.library => '내 서재',
    HypPage.favorites => '내 독서',
    HypPage.downloads => '다운로드',
    HypPage.history => '열람 기록',
    HypPage.settings => '설정',
  };

  IconData get icon => switch (this) {
    HypPage.home => Icons.home_rounded,
    HypPage.library => Icons.library_books_rounded,
    HypPage.favorites => Icons.insights_rounded,
    HypPage.downloads => Icons.download_rounded,
    HypPage.history => Icons.history_rounded,
    HypPage.settings => Icons.settings_rounded,
  };
}

/// Windows-first responsive app shell. All actions call the existing library,
/// YouTube, CBZ and updater services instead of imitating them with mock data.
class HypDashboard extends StatefulWidget {
  final LibraryBackup library;
  final BlacklistRules blacklist;
  final Future<void> Function(BlacklistRules) onSaveBlacklist;
  final Future<void> Function(BlacklistRule) onBlacklistAdd;
  final Future<void> Function() onBlacklistExport;
  final Future<BlacklistRules?> Function() onBlacklistImport;
  final String? editionLookupId;
  final int editionLookupEpoch;
  final List<ReadingSession> readingSessions;
  final Future<void> Function() onClearReadingHistory;
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
  final int downloadNavigationEpoch;
  final String appVersion;
  final bool downloadingUpdate;
  final double updateProgress;
  final String updateStatus;
  final String? downloadingGalleryKey;
  final int downloadedGalleryPages;
  final int totalGalleryPages;
  final int downloadedGalleryBytes;
  final VoidCallback onAnalyze;
  final VoidCallback onClearFinder;
  final VoidCallback? onLeaveFinderAfterSave;
  final int finderClearEpoch;
  final Future<void> Function() onFetch;
  final Future<void> Function()? onInspectSource;
  final Future<void> Function()? onInspectImages;
  final Future<void> Function() onSaveWork;
  final Future<void> Function(String code) onQuickAddNumber;
  final Future<void> Function(OnlineSearchWork) onSaveOnlineSearchWork;
  final Future<void> Function(WorkEntry anchor, String editionId) onLinkEdition;
  final Future<void> Function(WorkEntry anchor, List<String> localIds,
      List<OnlineSearchWork> remoteWorks)? onLinkEditions;
  final Future<void> Function(WorkEntry) onUnlinkEdition;
  final Future<void> Function(OnlineSearchWork) onReadOnlineSearchWork;
  final Future<void> Function(OnlineSearchWork) onPreviewOnlineSearchWork;
  final Future<void> Function(String) onPreviewCandidate;
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
  final Map<String, FailedDownload> failedDownloads;
  final Future<void> Function(String workId)? onRetryFailedDownload;
  final Future<void> Function(String workId)? onDismissFailedDownload;
  final Future<void> Function()? onClearFailedDownloads;
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
  final Future<void> Function(String groupId, List<String> ids)? onRemoveGroupChapters;
  final Future<void> Function(String source, String target, List<String> ids)? onMoveGroupChapters;
  final Future<void> Function(List<String> ids) onExportSelectedDownloads;
  final Future<void> Function(List<String> ids) onDeleteSelectedOffline;
  final VoidCallback onToggleDownloadPause;
  final bool downloadPaused;
  final bool downloadCanPause;
  final Future<void> Function(WorkEntry) onImportGallery;
  final Future<void> Function(WorkEntry) onUpdateWork;
  final Future<void> Function(WorkEntry, bool) onSetCompleted;
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
    required this.blacklist,
    required this.onSaveBlacklist,
    required this.onBlacklistAdd,
    required this.onBlacklistExport,
    required this.onBlacklistImport,
    this.editionLookupId,
    this.editionLookupEpoch = 0,
    required this.readingSessions,
    required this.onClearReadingHistory,
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
    this.downloadNavigationEpoch = 0,
    required this.appVersion,
    required this.downloadingUpdate,
    required this.updateProgress,
    required this.updateStatus,
    required this.downloadingGalleryKey,
    required this.downloadedGalleryPages,
    required this.totalGalleryPages,
    required this.downloadedGalleryBytes,
    required this.onAnalyze,
    required this.onClearFinder,
    this.onLeaveFinderAfterSave,
    required this.finderClearEpoch,
    required this.onFetch,
    this.onInspectSource,
    this.onInspectImages,
    required this.onSaveWork,
    required this.onQuickAddNumber,
    required this.onSaveOnlineSearchWork,
    required this.onLinkEdition,
    this.onLinkEditions,
    required this.onUnlinkEdition,
    required this.onReadOnlineSearchWork,
    required this.onPreviewOnlineSearchWork,
    required this.onPreviewCandidate,
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
    this.failedDownloads = const {},
    this.onRetryFailedDownload,
    this.onDismissFailedDownload,
    this.onClearFailedDownloads,
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
    this.onRemoveGroupChapters,
    this.onMoveGroupChapters,
    required this.onExportSelectedDownloads,
    required this.onDeleteSelectedOffline,
    required this.onToggleDownloadPause,
    required this.downloadPaused,
    required this.downloadCanPause,
    required this.onImportGallery,
    required this.onUpdateWork,
    required this.onSetCompleted,
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
  Timer? _searchDebounce;
  Timer? _autoWebSearchDebounce;
  String _autoWebQuery = '';
  bool _autoWebBusy = false;
  String? _autoWebError;
  final Map<String, (DateTime, List<HitomiWebGallery>)> _autoWebCache = {};
  http.Client? _activeRemoteSearchClient;
  int _searchEpoch = 0;
  String _searchScope = 'all'; // all, local, online
  String _searchLanguage = '';
  bool _remoteBusy = false;
  String? _remoteError;
  List<OnlineSearchWork> _remoteResults = [];
  // User-approved public Hitomi web results stay distinct from mirror
  // snapshots, which can arrive later and otherwise replace their lists.
  final Map<String, OnlineSearchWork> _webSearchResults = {};
  String _webSearchQuery = '';
  int _remoteTotal = 0;
  int _remotePage = 0;
  bool _remoteHasMore = false;
  int _remoteProgressDone = 0;
  int _remoteProgressTotal = 0;
  Map<String, List<String>> _remoteFieldMatches = const {};
  String _remoteFieldFilter = '';
  final Set<String> _searchedRemoteFields = <String>{};
  final Set<String> _loadedRemoteFacets = {};
  final Set<String> _loadingRemoteFacets = {};
  final Map<String, int> _remoteFacetPages = {};
  final Set<String> _moreRemoteFacets = {};
  String? _remoteFacetError;
  List<String> _remoteWarnings = const [];
  final Map<String, (DateTime, OnlineSearchResult)> _remoteCache = {};
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _dashboardFocus = FocusNode(debugLabel: 'dashboard-shortcuts');
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
  final Set<String> _selectedGroupIds = <String>{};
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
  bool _groupScanBusy = false;
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
    if (widget.downloadNavigationEpoch > 0) _page = HypPage.downloads;
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
    if (oldWidget.readerSettings.autoWebSearch !=
        widget.readerSettings.autoWebSearch) _changedSearch();
    if (oldWidget.readerSettings.preloadPages !=
        widget.readerSettings.preloadPages) {
      _preloadInput.text = widget.readerSettings.preloadPages.toString();
    }
    if (oldWidget.navigationEpoch != widget.navigationEpoch) {
      _page = HypPage.home;
      _search.clear();
    }
    if (oldWidget.libraryNavigationEpoch != widget.libraryNavigationEpoch) {
      if (_page == HypPage.home) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onLeaveFinderAfterSave?.call();
        });
      }
      _page = HypPage.library;
      _search.clear();
    }
    if (oldWidget.downloadNavigationEpoch != widget.downloadNavigationEpoch) {
      if (_page == HypPage.home) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onLeaveFinderAfterSave?.call();
        });
      }
      _page = HypPage.downloads;
      _search.clear();
    }
    if (oldWidget.editionLookupEpoch != widget.editionLookupEpoch &&
        widget.editionLookupId != null) {
      final id = widget.editionLookupId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final match = widget.library.works
            .where((entry) => entry.workId == id).firstOrNull;
        if (match != null) _findOtherEditions(match);
      });
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
    _searchDebounce?.cancel();
    _autoWebSearchDebounce?.cancel();
    _activeRemoteSearchClient?.close();
    _activeRemoteSearchClient = null;
    _search.removeListener(_changedSearch);
    _search.dispose();
    _searchFocus.dispose();
    _dashboardFocus.dispose();
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
    _searchDebounce?.cancel();
    _autoWebSearchDebounce?.cancel();
    _autoWebQuery = '';
    _autoWebBusy = false;
    _autoWebError = null;
    _activeRemoteSearchClient?.close();
    _activeRemoteSearchClient = null;
    _searchEpoch++;
    _remoteResults = [];
    final currentQuery = _search.text.trim();
    if (currentQuery != _webSearchQuery) {
      _webSearchResults.clear();
      _webSearchQuery = currentQuery;
    }
    _remoteError = null;
    _remotePage = 0;
    _remoteTotal = 0;
    _remoteHasMore = false;
    _remoteProgressDone = 0;
    _remoteProgressTotal = 0;
    _remoteFieldMatches = const {};
    _remoteFieldFilter = '';
    _searchedRemoteFields.clear();
    _loadedRemoteFacets.clear();
    _loadingRemoteFacets.clear();
    _remoteFacetPages.clear();
    _moreRemoteFacets.clear();
    _remoteFacetError = null;
    _remoteWarnings = const [];
    _remoteBusy = false;
    if (mounted) setState(() {});
    if (_search.text.trim().isNotEmpty && _searchScope != 'local') {
      final epoch = _searchEpoch;
      _searchDebounce = Timer(const Duration(milliseconds: 450),
          () => _fetchOnlineSearch(epoch: epoch));
      if (AutoWebSearchPolicy.shouldSearch(
          enabled: widget.readerSettings.autoWebSearch,
          query: currentQuery, scope: _searchScope)) {
        _autoWebSearchDebounce = Timer(AutoWebSearchPolicy.debounce, () {
          if (!mounted || epoch != _searchEpoch) return;
          final cached = _autoWebCache[currentQuery];
          if (cached != null && DateTime.now().difference(cached.$1) <
              AutoWebSearchPolicy.cacheTtl) {
            setState(() {
              for (final item in cached.$2) {
                _webSearchResults[item.workId] = OnlineSearchWork(
                    workId: item.workId, title: item.title);
              }
            });
          } else {
            setState(() {
              _autoWebBusy = true;
              _autoWebQuery = currentQuery;
            });
          }
        });
      }
    }
  }

  void _autoWebSearchFinished(String query, List<HitomiWebGallery> items,
      String? error) {
    if (!mounted || query != _search.text.trim() ||
        _autoWebQuery != query || _searchScope == 'local') return;
    setState(() {
      _autoWebQuery = '';
      _autoWebBusy = false;
      _autoWebError = error;
      if (items.isNotEmpty) {
        _autoWebCache[query] = (DateTime.now(), items);
        if (_autoWebCache.length > 20) {
          _autoWebCache.remove(_autoWebCache.keys.first);
        }
        for (final item in items) {
          _webSearchResults[item.workId] = OnlineSearchWork(
              workId: item.workId, title: item.title);
        }
      }
    });
  }

  Future<void> _fetchOnlineSearch({required int epoch, bool next = false}) async {
    if (!mounted || _searchScope == 'local' || _search.text.trim().isEmpty) return;
    final term = _search.text.trim();
    // A title already known in the library can have verified translations
    // under a completely different name. Query only synonyms of matching
    // works; never upload the entire private library or reading history.
    final aliases = TitleAliasIndex.fromLibrary(widget.library.works);
    final otherNames = <String>[];
    if (!RegExp(r'^[a-z_]+:', caseSensitive: false).hasMatch(term)) {
      for (final work in widget.library.works) {
        if (!LocalWorkSearch.matches(work, term)) continue;
        for (final alias in aliases.aliasesFor(work)) {
          if (alias.toLowerCase() != term.toLowerCase() &&
              alias.length <= 100 && !otherNames.contains(alias)) {
            otherNames.add(alias);
          }
          if (otherNames.length >= 4) break;
        }
        if (otherNames.length >= 4) break;
      }
    }
    final expanded = [term, ...otherNames].join(' | ');
    final page = next ? _remotePage + 1 : 1;
    final key = [expanded.toLowerCase(), _searchLanguage, page].join('|');
    final cached = _remoteCache[key];
    if (cached != null && DateTime.now().difference(cached.$1) <
        const Duration(minutes: 10)) {
      _useOnlineResults(cached.$2, epoch, next: next);
      return;
    }
    setState(() {
      _remoteBusy = true;
      _remoteProgressDone = 0;
      _remoteProgressTotal = 0;
      _remoteError = null;
    });
    final client = http.Client();
    _activeRemoteSearchClient = client;
    try {
      final service = OnlineWorkSearch(client);
      final result = await service.searchUnified(expanded, page: page,
          language: _searchLanguage,
          onProgress: (done, total) {
            if (mounted && epoch == _searchEpoch) {
              setState(() {
                _remoteProgressDone = done;
                _remoteProgressTotal = total;
              });
            }
          },
          onPartial: (partial) {
            if (mounted && epoch == _searchEpoch) {
              _useOnlineResults(partial, epoch, next: next);
            }
          });
      if (!mounted || epoch != _searchEpoch) return;
      _remoteCache[key] = (DateTime.now(), result);
      if (_remoteCache.length > 60) _remoteCache.clear();
      _useOnlineResults(result, epoch, next: next);
    } catch (error) {
      if (mounted && epoch == _searchEpoch) setState(() {
        _remoteError = error.toString();
      });
    } finally {
      if (identical(_activeRemoteSearchClient, client)) {
        _activeRemoteSearchClient = null;
      }
      client.close();
      if (mounted && epoch == _searchEpoch) {
        setState(() => _remoteBusy = false);
        if (_remoteFieldFilter.isNotEmpty) {
          _loadRemoteFacet(_remoteFieldFilter, epoch: epoch);
        }
      }
    }
  }

  void _useOnlineResults(OnlineSearchResult result, int epoch,
      {required bool next}) {
    if (!mounted || epoch != _searchEpoch) return;
    final previousCount = _remoteResults.length;
    setState(() {
      _remotePage = result.page;
      if (!next) _searchedRemoteFields.clear();
      _searchedRemoteFields.addAll(result.searchedFields);
      _remoteFieldMatches = <String, List<String>>{
        if (next) ..._remoteFieldMatches,
        for (final entry in result.matchedFields.entries)
          entry.key: {...?_remoteFieldMatches[entry.key],
             ...entry.value}.toList(),
      };
      _remoteWarnings = [
        if (next) ..._remoteWarnings,
        ...result.warnings,
      ];
      final seen = <String>{};
      _remoteResults = [...next ? _remoteResults : <OnlineSearchWork>[],
        ...result.works].where((work) => seen.add(work.workId)).toList();
      _remoteTotal = _remoteResults.length;
      // Avoid an endless Load More button when a mirror repeats the same
      // result page or a page contains only already collected IDs.
      _remoteHasMore = result.hasNextPage &&
          (!next || _remoteTotal > previousCount) && result.page < 100;
    });
  }

  void _selectRemoteFacet(String field, bool chosen) {
    setState(() => _remoteFieldFilter = chosen ? field : '');
    if (chosen && field != 'web') _loadRemoteFacet(field, epoch: _searchEpoch);
  }

  /// Explicitly search the selected metadata field even when a dense title
  /// result skipped broad field expansion. Never replace the previous
  /// result set or alter library records; merge only new public gallery IDs.
  Future<void> _loadRemoteFacet(String field, {
    required int epoch, bool next = false,
  }) async {
    if (!mounted || _searchScope == 'local' || _remoteBusy ||
        field == 'general' || field == 'advanced' ||
        _loadingRemoteFacets.contains(field) ||
        !const {'artist', 'group', 'series', 'tag', 'female', 'male'}
            .contains(field) ||
        (!next && _loadedRemoteFacets.contains(field)) ||
        (next && !_moreRemoteFacets.contains(field))) return;
    final raw = _search.text.trim();
    if (raw.isEmpty || RegExp(r'^[a-z_]+:', caseSensitive: false)
        .hasMatch(raw)) return;
    final terms = raw.split('|').map((part) => part.trim())
        .where((part) => part.length >= 2 &&
            part.length + field.length + 1 <= 150).take(2).toList();
    if (terms.isEmpty) return;
    final page = next ? (_remoteFacetPages[field] ?? 1) + 1 : 1;
    setState(() {
      _loadingRemoteFacets.add(field);
      _remoteFacetError = null;
    });
    final client = http.Client();
    try {
      final service = OnlineWorkSearch(client);
      final responses = await Future.wait(terms.map((term) async {
        try {
          return await service.search(field + ':' + term,
              page: page, language: _searchLanguage);
        } catch (_) {
          return null;
        }
      }));
      if (!mounted || epoch != _searchEpoch) return;
      final valid = responses.whereType<OnlineSearchResult>().toList();
      if (valid.isEmpty) {
        throw StateError('분야별 검색 서버에 연결하지 못했어.');
      }
      setState(() {
        final known = <String, OnlineSearchWork>{
          for (final work in _remoteResults) work.workId: work,
        };
        final fields = <String, Set<String>>{
          for (final entry in _remoteFieldMatches.entries)
            entry.key: {...entry.value},
        };
        var added = 0;
        var hasMore = false;
        for (final response in valid) {
          hasMore = hasMore || (response.works.isNotEmpty &&
              (response.total > page * 15 || response.works.length >= 15));
          for (final work in response.works) {
            final previous = known[work.workId];
            if (previous == null) added++;
            // Preserve the original record when the focused mirror returns
            // fewer metadata fields; add only verified public evidence.
            final enriched = previous == null ? work :
                OnlineWorkSearch.combineWorks(previous, work);
            known[work.workId] = enriched;
            fields.putIfAbsent(work.workId, () => <String>{})
              ..add(field)
              ..addAll(OnlineWorkSearch.metadataFields(enriched, raw));
          }
        }
        _remoteResults = known.values.toList();
        _searchedRemoteFields.add(field);
        _remoteFieldMatches = {
          for (final entry in fields.entries)
            entry.key: entry.value.toList(),
        };
        _remoteTotal = _remoteResults.length;
        _loadedRemoteFacets.add(field);
        _remoteFacetPages[field] = page;
        if (hasMore && added > 0 && page < 100) {
          _moreRemoteFacets.add(field);
        } else {
          _moreRemoteFacets.remove(field);
        }
      });
    } catch (error) {
      if (mounted && epoch == _searchEpoch) {
        setState(() => _remoteFacetError = error.toString());
      }
    } finally {
      client.close();
      if (mounted && epoch == _searchEpoch) {
        setState(() => _loadingRemoteFacets.remove(field));
      }
    }
  }

  void _navigate(HypPage page) {
    if (_page == HypPage.home && page != HypPage.home) {
      widget.onLeaveFinderAfterSave?.call();
    }
    _dashboardFocus.requestFocus();
    _openedGroupId = null;
    _lastHomeBack = null;
    // A homepage capture with no search term has no TextField change event.
    // Clear imported results explicitly when navigating to another section.
    _webSearchResults.clear();
    _webSearchQuery = '';
    _search.clear();
    setState(() {
      _page = page;
      if (page != HypPage.library) {
        _selectingWorks = false;
        _selectedWorkIds.clear();
        _selectedGroupIds.clear();
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
    if (_webSearchResults.isNotEmpty) {
      _dashboardFocus.requestFocus();
      setState(() => _webSearchResults.clear());
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
    if (!_selectingWorks) {
      _selectedWorkIds.clear();
      _selectedGroupIds.clear();
    }
  });

  void _toggleSelectedWork(WorkEntry work) => setState(() {
    if (!_selectedWorkIds.add(work.workId)) {
      _selectedWorkIds.remove(work.workId);
    }
  });

  void _toggleSelectedGroup(String id) => setState(() {
    if (!_selectedGroupIds.add(id)) _selectedGroupIds.remove(id);
  });

  void _startSelectingGroup(String id) => setState(() {
    _selectingWorks = true;
    _selectedGroupIds.add(id);
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
        _selectedGroupIds.clear();
        _selectingWorks = false;
      });
      await _refreshOffline();
    }
  }

  Future<void> _editSelectedWork() async {
    if (_selectedGroupIds.isNotEmpty || _selectedWorkIds.length != 1) return;
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


  Future<void> _openReaderWith(Future<void> Function() action) =>
      ReaderNavigationFocus.show(
        returnFocus: _dashboardFocus,
        isMounted: () => mounted,
        openReader: action,
      );

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

  List<WorkEntry> get _visibleLibraryWorks =>
      WorkEditions.visibleOnShelf(_works, widget.readerSettings.completedHidden);

  List<WorkEntry> get _recent => widget.library.works
      .where((w) => w.lastOpenedAt != null)
      .toList()
    ..sort((a, b) => (b.lastOpenedAt ?? '').compareTo(a.lastOpenedAt ?? ''));

  List<WorkEntry> get _downloaded =>
      _works.where((w) => _offlineKeys.contains(w.key)).toList();

  List<WorkEntry> get _results => LocalWorkSearch.rankResults(
      LocalWorkSearch.queryLibrary(_works, _search.text,
          language: _searchLanguage).where((work) => !widget.blacklist.blocks(
            id: work.workId, title: work.title,
            artists: [work.author], groups: [work.sourceGroup],
            tags: work.tags)), _search.text);

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
    focusNode: _dashboardFocus,
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
            tooltip: AppLocalizations.of(context)!.tooltipUpdate,
            onPressed: widget.onCheckRelease,
            icon: const Icon(Icons.system_update_alt_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: AppLocalizations.of(context)!.tooltipMore,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LinearProgressIndicator(value: widget.updateProgress),
                const SizedBox(height: 4),
                HypText(widget.updateStatus +
                    ' · ' + (widget.updateProgress * 100).toStringAsFixed(0) +
                    '%', style: const TextStyle(fontSize: 11)),
              ]),
            ),
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
                              tooltip: AppLocalizations.of(context)!.tooltipDismiss,
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
            label: HypI18n.t(context, '내 독서')),
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
        tooltip: AppLocalizations.of(context)!.tooltipMore,
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

  Future<void> _openHitomiWebSearch() async {
    final query = _search.text.trim();
    if (query.length > 150) return;
    final epoch = _searchEpoch;
    // On both Cancel and Apply, keep focus on the non-text dashboard scope.
    final imported = await ReaderNavigationFocus
        .showResult<List<HitomiWebGallery>?>(
      returnFocus: _dashboardFocus,
      isMounted: () => mounted,
      openRoute: () => Navigator.of(context)
          .push<List<HitomiWebGallery>>(MaterialPageRoute(
        builder: (_) => HitomiWebSearchPage(query: query,
            adBlockMode: widget.readerSettings.webSearchAdBlockMode),
      )),
    );
    if (!mounted || epoch != _searchEpoch ||
        imported == null || imported.isEmpty) return;
    setState(() {
      for (final entry in imported) {
        _webSearchResults[entry.workId] = OnlineSearchWork(
          workId: entry.workId, title: entry.title);
      }
      if (_searchScope == 'local') _searchScope = 'all';
    });
  }

  Widget _searchField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('library-search-input'),
        focusNode: _searchFocus,
        controller: _search,
        decoration: InputDecoration(
          hintText: HypI18n.t(context,
              '작품 제목, 작가, 번호, 목록으로 검색하세요...'),
          prefixIcon: Icon(Icons.search_rounded, color: HypColors.muted),
        ),
      ),
      if (_autoWebBusy)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(AppLocalizations.of(context)!.autoWebSearchWorking,
              style: const TextStyle(fontSize: 11)),
        ),
      if (_autoWebError != null)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(AppLocalizations.of(context)!.webSearchCaptureFailed,
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent)),
        ),
      if (_autoWebQuery.isNotEmpty)
        AutoHitomiWebSearch(
          adBlockMode: widget.readerSettings.webSearchAdBlockMode,
          key: ValueKey('auto-web-' + _autoWebQuery),
          query: _autoWebQuery,
          onFinished: _autoWebSearchFinished,
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const Key('search-web-site'),
          onPressed: _search.text.trim().length <= 150
              ? _openHitomiWebSearch : null,
          icon: const Icon(Icons.public_outlined, size: 18),
          label: Text(AppLocalizations.of(context)!.webSearchAction),
        ),
      ),
    ],
  );

  Widget _contents() {
    final showSearchResults = _search.text.trim().isNotEmpty ||
        _webSearchResults.isNotEmpty;
    final pageContent = showSearchResults
        ? _searchContent()
        : switch (_page) {
            HypPage.home => _homeContent(),
            HypPage.library => _libraryContent(),
            HypPage.favorites => _insightsContent(),
            HypPage.history => _fullPage('열람 기록',
                '최근 읽기 화면을 연 순서대로 표시해.',
                HypPage.history.icon, _recent),
            HypPage.downloads => _downloadsContent(),
            HypPage.settings => _settingsContent(),
          };
    return ListView(
      key: ValueKey(showSearchResults
          ? (_search.text.trim().isEmpty ? 'web-results' : 'search')
          : _page.name),
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 30),
      children: [pageContent],
    );
  }

  Widget _insightsContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HypReadingInsights(
        works: _works,
        sessions: widget.readingSessions,
        offlineCount: _offlineKeys.length,
        settings: widget.readerSettings,
        onSaveSettings: widget.onSaveReaderSettings,
        onClearHistory: widget.onClearReadingHistory,
        onOpenWork: (work) {
          if (_offlineKeys.contains(work.key)) {
            _openReaderWith(() => widget.onOpenGallery(work));
          } else {
            _openReaderWith(() => widget.onReadOnline(work));
          }
        },
      ),
      const SizedBox(height: 16),
      _fullPage('즐겨찾기', '기존에 즐겨찾기한 작품을 그대로 확인해.',
          Icons.favorite_rounded, _favorites),
    ],
  );

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
          if (_offlineKeys.contains(work.key)) _openReaderWith(() => widget.onOpenGallery(work));
          else _openReaderWith(() => widget.onReadOnline(work));
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
        onClear: widget.onClearFinder,
        clearEpoch: widget.finderClearEpoch,
        onFetch: widget.onFetch,
        onInspectSource: widget.onInspectSource,
        onInspectImages: widget.onInspectImages,
        onOpenYoutube: widget.onOpenShortsInput,
        onSave: widget.onSaveWork,
        onQuickAddNumber: widget.onQuickAddNumber,
        onSaveSelectedWorks: widget.onSaveSelectedWorks,
        onVerifyCandidateCodes: widget.onVerifyCandidateCodes,
        onCrossLineFallback: widget.onCrossLineFallback,
        blacklist: widget.blacklist,
        onBlacklistAdd: widget.onBlacklistAdd,
        onPreview: widget.onPreviewCandidate,
      ),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: HypSectionTitle(
          icon: Icons.library_books_rounded,
          title: '최근 본 작품',
          subtitle: AppLocalizations.of(context)!
              .homeRecentCountHint(_recent.take(4).length),
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

  LibrarySort get _currentSort => LibrarySort.values.firstWhere(
    (mode) => mode.name == widget.readerSettings.librarySort,
    orElse: () => LibrarySort.newest);

  List<WorkEntry> _sortWithinGroup(Iterable<WorkEntry> works) =>
      WorkSorting.sort(works, _currentSort,
        descending: widget.readerSettings.librarySortDescending,
        popularityRanks:
            _popularity[widget.readerSettings.popularityPeriod] ?? const {});

  Future<void> _reviewLegacyCompletion() async {
    // A last-page bookmark does not prove the page actually rendered. Never
    // silently mark historical records complete; the reader stays in control.
    final review = _works.where((work) =>
        !work.completed && work.totalPages > 0 &&
        work.currentPage >= work.totalPages).take(100).toList();
    final language = AppLocalizations.of(context)!;
    if (review.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(language.legacyCompletionEmpty)));
      return;
    }
    final selection = <String>{};
    final confirmed = await showDialog<List<String>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, refresh) {
          final words = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(words.legacyCompletionReview),
            content: SizedBox(width: 550, height: 420,
              child: Column(children: [
                Text(words.legacyCompletionHint),
                const SizedBox(height: 9),
                Expanded(child: ListView.builder(
                  itemCount: review.length,
                  itemBuilder: (_, index) {
                    final work = review[index];
                    return CheckboxListTile(
                      dense: true,
                      value: selection.contains(work.workId),
                      title: HypAnimatedTitle(title: work.title),
                      subtitle: Text(work.workId + ' · ' +
                          work.currentPage.toString() + '/' +
                          work.totalPages.toString()),
                      onChanged: (checked) => refresh(() {
                        if (checked == true) {
                          selection.add(work.workId);
                        } else {
                          selection.remove(work.workId);
                        }
                      }),
                    );
                  },
                )),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                  child: Text(words.cancel)),
              FilledButton(
                onPressed: selection.isEmpty ? null : () =>
                    Navigator.pop(dialog, selection.toList()),
                child: Text(words.legacyCompletionApply),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed == null || !mounted) return;
    for (final work in review) {
      if (confirmed.contains(work.workId)) {
        await widget.onSetCompleted(work, true);
      }
    }
  }

  Future<void> _openEditionStack(List<WorkEntry> editions) async {
    final selected = await showModalBottomSheet<WorkEntry>(
      context: context, isScrollControlled: true,
      builder: (sheet) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const HypText('읽을 언어판 선택',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 7),
          SizedBox(height: 300, child: ListView(children: [
            for (final work in [
              WorkEditions.preferred(editions,
                  widget.readerSettings.preferredEditionLanguage),
              ...editions.where((entry) => entry.workId !=
                  WorkEditions.preferred(editions,
                      widget.readerSettings.preferredEditionLanguage).workId),
            ]) ListTile(
              key: Key('edition-choice-' + work.workId),
              leading: const Icon(Icons.menu_book),
              title: HypAnimatedTitle(
                title: WorkEditions.languageName(work.sourceLanguage) +
                    ' · ' + work.title,
              ),
              subtitle: HypText('#' + work.workId + ' · ' +
                  HypI18n.t(context, work.completed ? '완독' : '읽는 중')),
              onTap: () => Navigator.pop(sheet, work),
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  Navigator.pop(sheet);
                  _workAction(action, work);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'completed',
                      child: HypText(work.completed ? '완독 해제' : '완독 처리')),
                  const PopupMenuItem(value: 'find_editions',
                      child: HypText('다른 언어판 찾기')),
                  const PopupMenuItem(value: 'unlink_edition',
                      child: HypText('언어판 묶음에서 분리')),
                ],
              ),
            ),
          ])),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(sheet);
              _findOtherEditions(editions.first);
            },
            icon: const Icon(Icons.language),
            label: const HypText('다른 언어판 찾기'),
          ),
        ]),
      )),
    );
    if (selected == null || !mounted) return;
    if (_offlineKeys.contains(selected.key)) _openReaderWith(() => widget.onOpenGallery(selected));
    else _openReaderWith(() => widget.onReadOnline(selected));
  }

  Widget _editionTile(List<WorkEntry> members) {
    if (members.length > 1) {
      return HypWorkEditionCard(
        editions: members,
        coverImages: _coverImages,
        onOpen: () => _openEditionStack(members),
        onOpenCover: () {
          final opened = members.where((entry) =>
              entry.lastOpenedAt?.isNotEmpty == true).toList();
          final selected = WorkEditions.preferred(
              opened.isEmpty ? members : opened,
              opened.isEmpty
                  ? widget.readerSettings.preferredEditionLanguage : 'recent');
          if (_offlineKeys.contains(selected.key)) {
            _openReaderWith(() => widget.onOpenGallery(selected));
          } else {
            _openReaderWith(() => widget.onReadOnline(selected));
          }
        },
      );
    }
    final work = members.first;
    return HypWorkCard(
      work: work,
      isOffline: _offlineKeys.contains(work.key),
      totalPages: _pageCounts[work.key],
      coverBytes: _coverImages[work.key],
      onOpen: () {
        if (_offlineKeys.contains(work.key)) _openReaderWith(() => widget.onOpenGallery(work));
        else _openReaderWith(() => widget.onReadOnline(work));
      },
      onAction: (action) => _workAction(action, work),
      selectionMode: _selectingWorks && _canSelectWorks,
      selected: _selectedWorkIds.contains(work.workId),
      onSelect: () => _toggleSelectedWork(work),
      onLongPress: () => _startSelection(work),
    );
  }

  List<List<WorkEntry>> _editionEntries(List<WorkEntry> works) {
    final seen = <String>{};
    final entries = <List<WorkEntry>>[];
    for (final work in works) {
      if (work.editionGroupId.isEmpty) {
        entries.add([work]);
      } else if (seen.add(work.editionGroupId)) {
        entries.add(works.where((candidate) =>
          candidate.editionGroupId == work.editionGroupId).toList());
      }
    }
    return entries;
  }

  Widget _editionAwareGrid(List<WorkEntry> works) {
    final entries = _editionEntries(works);
    if (entries.isEmpty) return _gridOrEmpty(works,
        emptyTitle: '묶음이 비어 있어',
        emptyMessage: '다른 작품을 선택해서 추가해줘.');
    return LayoutBuilder(builder: (context, size) => GridView.builder(
      key: const Key('edition-aware-grid'),
      itemCount: entries.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columnsForWidth(size.maxWidth),
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: _columnsForWidth(size.maxWidth) == 1 ? 1.15 : 0.68),
      itemBuilder: (_, i) => _editionTile(entries[i]),
    ));
  }

  int _columnsForWidth(double width) =>
      width >= 1100 ? 5 : width >= 850 ? 4 :
      width >= 620 ? 3 : width >= 335 ? 2 : 1;

  /// A series contains chapter cells, each cell may contain several editions.
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
        final ordered = _sortWithinGroup(selected);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              IconButton(key: const Key('library-group-back'),
                tooltip: AppLocalizations.of(context)!.tooltipBackLibrary,
                onPressed: () => setState(() => _openedGroupId = null),
                icon: const Icon(Icons.arrow_back)),
              Expanded(child: HypAnimatedTitle(
                title: ordered.first.groupTitle.isEmpty
                    ? '작품 묶음' : ordered.first.groupTitle,
                style: Theme.of(context).textTheme.titleMedium,
              )),
              PopupMenuButton<String>(
                key: Key('work-group-menu-' + _openedGroupId!),
                tooltip: AppLocalizations.of(context)!.tooltipManageGroup,
                onSelected: (action) => _groupAction(
                    action, _openedGroupId!, selected),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'members', child: HypText('구성원 추가·제외·이동')),
                  PopupMenuItem(value: 'rename', child: HypText('묶음 이름 수정')),
                  PopupMenuItem(value: 'reorder', child: HypText('회차 순서 변경')),
                  PopupMenuItem(value: 'ungroup', child: HypText('묶음만 해제')),
                ]),
            ]),
            const SizedBox(height: 10),
            _editionAwareGrid(ordered),
          ]);
      }
      _openedGroupId = null;
    }
    final entries = <Object>[];
    final seenGroups = <String>{};
    final seenEd = <String>{};
    for (final work in works) {
      if (work.groupId.isNotEmpty) {
        if (seenGroups.add(work.groupId)) entries.add(work.groupId);
      } else if (work.editionGroupId.isNotEmpty) {
        if (seenEd.add(work.editionGroupId)) {
          entries.add(works.where((v) => v.groupId.isEmpty &&
              v.editionGroupId == work.editionGroupId).toList());
        }
      } else {
        entries.add(<WorkEntry>[work]);
      }
    }
    return LayoutBuilder(builder: (context, size) => GridView.builder(
      key: const Key('library-mixed-grid'),
      itemCount: entries.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columnsForWidth(size.maxWidth),
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: _columnsForWidth(size.maxWidth) == 1 ? 1.15 : 0.68),
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is String) {
          final members = groups[entry]!;
          final ordered = _sortWithinGroup(members);
          final seenChapters = <String>{};
          final representatives = ordered.where((member) =>
              member.editionGroupId.isEmpty ||
              seenChapters.add(member.editionGroupId)).toList();
          return HypWorkGroupCard(
            key: Key('work-group-' + entry),
            title: ordered.first.groupTitle.isEmpty
                ? '작품 묶음' : ordered.first.groupTitle,
            members: representatives,
            coverImages: _coverImages,
            onOpen: () => setState(() => _openedGroupId = entry),
            onAction: (action) => _groupAction(action, entry, members),
            selectionMode: _selectingWorks,
            selected: _selectedGroupIds.contains(entry),
            onSelect: () => _toggleSelectedGroup(entry),
            onLongPress: () => _startSelectingGroup(entry),
          );
        }
        return _editionTile(entry as List<WorkEntry>);
      },
    ));
  }

  Future<void> _findOtherEditions(WorkEntry work) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => EditionFinderDialog(
        anchor: work,
        library: widget.library.works,
        coverImages: _coverImages,
        onLinkSelected: (localIds, remoteWorks) async {
          final batch = widget.onLinkEditions;
          if (batch == null) {
            throw StateError('언어판 일괄 묶기 기능이 연결되지 않았어.');
          }
          await batch(work, localIds, remoteWorks);
        },
      ),
    );
  }

  Future<void> _groupSelectedWorks() async {
    final ordered = <WorkEntry>[];
    final included = <String>{};
    for (final groupId in _selectedGroupIds) {
      final members = widget.library.works.where((w) =>
          w.groupId == groupId).toList()
        ..sort((a, b) => a.groupOrder.compareTo(b.groupOrder));
      for (final work in members) {
        if (included.add(work.workId)) ordered.add(work);
      }
    }
    final singles = _works.where((w) =>
        _selectedWorkIds.contains(w.workId)).toList()
      ..sort(WorkGrouping.compareChapters);
    for (final work in singles) {
      if (included.add(work.workId)) ordered.add(work);
    }
    if (ordered.map(WorkEditions.groupKey).toSet().length < 2 ||
        _selectedGroupIds.length + _selectedWorkIds.length < 2) return;
    final input = TextEditingController(text: _selectedGroupIds.length == 1
        ? widget.library.works.firstWhere((w) =>
            w.groupId == _selectedGroupIds.first).groupTitle
        : WorkGrouping.normalizedSeries(ordered.first.title));
    (String, List<String>)? result;
    try {
      result = await showDialog<(String, List<String>)>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (dialog, update) =>
          AlertDialog(
            title: HypText(HypI18n.t(dialog, '선택한 작품과 묶음 통합')),
            content: SizedBox(
              width: 460, height: MediaQuery.sizeOf(dialog).height * 0.48,
              child: Column(children: [
                HypText('묶음 ' + _selectedGroupIds.length.toString() +
                    '개 포함 · 총 ' + ordered.length.toString() + '개 작품'),
                const SizedBox(height: 8),
                TextField(key: const Key('group-name-input'),
                  controller: input, onChanged: (_) => update(() {}),
                  decoration: InputDecoration(
                      labelText: HypI18n.t(dialog, '묶음 이름'))),
                const SizedBox(height: 10),
                Expanded(child: ListView.builder(
                  itemCount: ordered.length,
                  itemBuilder: (context, index) {
                    final work = ordered[index];
                    return ListTile(
                      dense: true, title: HypAnimatedTitle(title: work.title),
                      subtitle: Text('#' + work.workId),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: HypI18n.t(dialog, '한 칸 위로'),
                          onPressed: index == 0 ? null : () => update(() {
                            final value = ordered.removeAt(index);
                            ordered.insert(index - 1, value);
                          }),
                          icon: const Icon(Icons.arrow_upward)),
                        IconButton(
                          tooltip: HypI18n.t(dialog, '한 칸 아래로'),
                          onPressed: index == ordered.length - 1 ? null :
                              () => update(() {
                                final value = ordered.removeAt(index);
                                ordered.insert(index + 1, value);
                              }),
                          icon: const Icon(Icons.arrow_downward)),
                      ]),
                    );
                  },
                )),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                child: const HypText('취소')),
              FilledButton(
                key: const Key('group-confirm'),
                onPressed: input.text.trim().isEmpty ? null : () =>
                    Navigator.pop(dialog, (input.text.trim(),
                        ordered.map((w) => w.workId).toList())),
                child: HypText(HypI18n.t(dialog, '한 묶음으로 통합'))),
            ],
          ),
        ),
      );
    } finally {
      input.dispose();
    }
    if (result == null || !mounted) return;
    try {
      await widget.onGroupWorks(result.$2, result.$1);
      if (!mounted) return;
      setState(() {
        _selectedWorkIds.clear();
        _selectedGroupIds.clear();
        _selectingWorks = false;
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: HypText('묶음 통합 실패: $error')));
    }
  }

  Future<void> _enrichAndGroup() async {
    if (_groupScanBusy) return;
    setState(() => _groupScanBusy = true);
    final client = http.Client();
    var refreshed = 0;
    try {
      final provider = HitomiGalleryProvider(client);
      // Limit network pressure. User-confirmed metadata enrichment only.
      final eligible = widget.library.works.where((work) =>
          work.title.isEmpty || work.title == '작품 ' + work.workId ||
          (work.author.isEmpty && work.sourceGroup.isEmpty)).take(80).toList();
      for (var i = 0; i < eligible.length; i += 3) {
        final batch = eligible.skip(i).take(3).toList();
        await Future.wait(batch.map((work) async {
          try {
            final info = await provider.fetchInfo(work.workId)
                .timeout(const Duration(seconds: 10));
            if (!mounted) return;
            final newTitle = (work.title.isEmpty ||
                work.title == '작품 ' + work.workId) && info.title.isNotEmpty
                ? info.title : work.title;
            final newAuthor = work.author.isEmpty ? info.author : work.author;
            final newGroup = work.sourceGroup.isEmpty ? info.group : work.sourceGroup;
            if (newTitle == work.title && newAuthor == work.author &&
                newGroup == work.sourceGroup &&
                work.sourceSeries.isNotEmpty) return;
            await widget.onUpdateWork(work.copyWith(
              title: newTitle, author: newAuthor,
              sourceGroup: newGroup,
              sourceSeries: work.sourceSeries.isEmpty
                  ? info.series : work.sourceSeries,
              tags: work.tags.isEmpty ? info.tags : work.tags,
              sourceType: work.sourceType.isEmpty ? info.type : work.sourceType,
              sourceLanguage: work.sourceLanguage.isEmpty
                  ? info.language : work.sourceLanguage,
            ));
            refreshed++;
          } catch (_) { /* A remote source may be temporarily unavailable. */ }
        }));
      }
    } finally {
      client.close();
      if (mounted) setState(() => _groupScanBusy = false);
    }
    if (!mounted) return;
    final proposals = WorkGrouping.suggest(widget.library.works);
    if (proposals.isEmpty) {
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: const HypText('Auto 묶기 · 탐색 완료'),
        content: HypText('작품 ' + refreshed.toString() +
            '개 정보를 갱신했지만 추천 묶음이 없어. '
            '수동으로 여러 작품을 선택해 묶을 수도 있어.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
          child: const HypText('확인'))],
      ));
    } else {
      await _showAutoGroupWizard();
    }
  }

  Future<void> _showAutoGroupWizard() async {
    final suggestions = WorkGrouping.suggest(widget.library.works);
    if (suggestions.isEmpty) {
      final retry = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const HypText('Auto 묶기 · 탐색 결과'),
          content: HypText('전체 ' + widget.library.works.length.toString() +
              '개 작품을 비교했지만 새 시리즈 후보를 찾지 못했어.\n\n'
              '서재의 제목·작가·서클·시리즈 정보가 부족하면 후보를 놓칠 수 있어. '
              '온라인에서 누락된 작품 정보를 보충한 후 재탐색할까?\n'
              '(기존 묶음과 읽기 기록은 변경하지 않아.)'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const HypText('닫기')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const HypText('정보 갱신 후 재탐색')),
          ],
        ),
      );
      if (retry == true && mounted) await _enrichAndGroup();
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
            SnackBar(content: HypText('묶음 추가 실패: $error')));
        }
      }
    }
    if (mounted && saved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: HypText('선택한 묶음 $saved개 적용을 요청했어.')));
    }
  }

  Future<void> _groupAction(String action, String id,
      List<WorkEntry> members) async {
    if (action == 'members') {
      await _manageGroupMembers(id, members);
    } else if (action == 'ungroup') {
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
      final seen = <String>{};
      final ordered = ([...members]..sort((a,b) =>
          a.groupOrder.compareTo(b.groupOrder)))
          .where((work) => work.editionGroupId.isEmpty ||
              seen.add(work.editionGroupId)).toList();
      final result = await showDialog<List<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            title: const HypText('회차 순서 변경'),
            content: SizedBox(width: 440, height: 300,
              child: ListView.builder(
                itemCount: ordered.length,
                itemBuilder: (_, index) => ListTile(
                  title: HypAnimatedTitle(
                    title: (index + 1).toString() + '. ' +
                        ordered[index].title,
                  ),
                  subtitle: HypText('#' + ordered[index].workId),
                  trailing: Row(mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: AppLocalizations.of(context)!.tooltipMoveUp,
                        onPressed: index == 0 ? null : () => update(() {
                          final item = ordered.removeAt(index);
                          ordered.insert(index - 1, item);
                        }),
                        icon: const Icon(Icons.arrow_upward)),
                      IconButton(
                        tooltip: AppLocalizations.of(context)!.tooltipMoveDown,
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

  Future<void> _manageGroupMembers(String id, List<WorkEntry> members) async {
    final available = widget.library.works.where((w) => w.groupId.isEmpty)
        .where((w) => w.editionGroupId.isEmpty ||
            widget.library.works.every((peer) => peer.editionGroupId != w.editionGroupId || peer.groupId.isEmpty))
        .toList();
    final groups = widget.library.works.where((w) =>
        w.groupId.isNotEmpty && w.groupId != id).map((w) => w.groupId).toSet().toList();
    final commands = <String>[
      'add', 'remove', if (groups.isNotEmpty) 'move', 'edit'];
    final action = await showDialog<String>(context: context, builder: (ctx) =>
      SimpleDialog(title: const HypText('묶음 구성원 관리'), children: [
        for (final name in commands) SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, name),
          child: HypText(name == 'add' ? '서재에서 작품 추가' :
            name == 'remove' ? '회차를 묶음에서 제외' :
            name == 'edit' ? '회차 제목 수정' : '다른 묶음으로 이동'),
        ),
      ]));
    if (!mounted || action == null) return;
    final seenEditions = <String>{};
    final options = (action == 'add' ? available : members).where((w) =>
      w.editionGroupId.isEmpty || seenEditions.add(w.editionGroupId)).toList();
    if (options.isEmpty) return;
    final picked = <String>{};
    final selected = await showDialog<List<String>>(context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const HypText('회차 선택'),
        content: SizedBox(width: 460, height: 350, child: ListView(
          children: [for (final w in options) CheckboxListTile(
            title: HypAnimatedTitle(title: w.title),
            subtitle: HypText('#' + w.workId),
            value: picked.contains(w.workId),
            onChanged: (v) => update(() { if (v == true) { picked.add(w.workId); } else { picked.remove(w.workId); } }),
          )])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const HypText('취소')),
          FilledButton(onPressed: picked.isEmpty || (action == 'edit' && picked.length != 1)
              ? null : () => Navigator.pop(ctx, picked.toList()),
            child: const HypText('계속'))],
      )));
    if (selected == null || selected.isEmpty || !mounted) return;
    try {
      if (action == 'edit') {
        final target = members.firstWhere((w) => w.workId == selected.single);
        await widget.onEditWorkDetails(target);
      } else if (action == 'add') {
        await widget.onAddWorksToGroup?.call(id, selected);
      } else if (action == 'remove') {
        await widget.onRemoveGroupChapters?.call(id, selected);
      } else if (groups.isNotEmpty) {
        final target = await showDialog<String>(context: context, builder: (ctx) =>
          SimpleDialog(title: const HypText('대상 묶음 선택'), children: [
            for (final targetId in groups) SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, targetId),
              child: HypText(widget.library.works.firstWhere((w) => w.groupId == targetId).groupTitle),
            ),
          ]));
        if (target != null) await widget.onMoveGroupChapters?.call(id, target, selected);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: HypText('묶음 편집 실패: $error')));
    }
  }

  Widget _selectionControls(List<WorkEntry> visible) =>
      !_selectingWorks ? const SizedBox.shrink() : Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Wrap(spacing: 8, runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            HypText('선택됨: ' + _selectedWorkIds.length.toString() +
                '개 작품 · ' + _selectedGroupIds.length.toString() + '개 묶음'),
            OutlinedButton(
              key: const Key('library-select-visible'),
              onPressed: visible.isEmpty ? null : () => setState(() {
                // When searching, select ONLY current matching results;
                // never silently include previously selected hidden works.
                if (_search.text.trim().isNotEmpty) {
                  _selectedWorkIds.clear();
                }
                if (_page == HypPage.library && _search.text.isEmpty) {
                  for (final work in visible) {
                    if (work.groupId.isNotEmpty) {
                      _selectedGroupIds.add(work.groupId);
                    } else {
                      _selectedWorkIds.add(work.workId);
                    }
                  }
                } else {
                  _selectedWorkIds.addAll(visible.map((w) => w.workId));
                }
              }),
              child: const HypText('전체 선택'),
            ),
            OutlinedButton(
              key: const Key('library-clear-selection'),
              onPressed: _selectedWorkIds.isEmpty && _selectedGroupIds.isEmpty
                  ? null : () => setState(() {
                    _selectedWorkIds.clear();
                    _selectedGroupIds.clear();
                  }),
              child: const HypText('선택 해제'),
            ),
            if (_page == HypPage.library)
              OutlinedButton.icon(
                key: const Key('library-group-selected'),
                onPressed: _selectedWorkIds.length + _selectedGroupIds.length < 2
                    ? null : _groupSelectedWorks,
                icon: const Icon(Icons.bookmarks_outlined),
                label: const HypText('선택 묶기'),
              ),
            OutlinedButton.icon(
              key: const Key('library-edit-selected'),
              onPressed: _selectedGroupIds.isEmpty &&
                    _selectedWorkIds.length == 1 ? _editSelectedWork : null,
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
                onPressed: _selectedGroupIds.isEmpty &&
                    _selectedWorkIds.isNotEmpty ? _removeSelectedWorks : null,
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
            DropdownMenuItem(value: 'chapter', child: HypText('회차순 (수동 순서)')),
          ],
          onChanged: (value) {
            if (value != null) widget.onSaveReaderSettings(
              widget.readerSettings.copyWith(librarySort: value));
          },
        )),
        IconButton(
          key: const Key('library-sort-direction'),
          tooltip: AppLocalizations.of(context)!.tooltipSortDirection,
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
            decoration: InputDecoration(isDense: true,
                labelText: AppLocalizations.of(context)!.tooltipPopularPeriod),
            items: const [
              DropdownMenuItem(value: 'today', child: HypText('일간')),
              DropdownMenuItem(value: 'week', child: HypText('주간')),
              DropdownMenuItem(value: 'month', child: HypText('월간')),
              DropdownMenuItem(value: 'year', child: HypText('연간')),
            ],
            onChanged: (period) {
              if (period != null) widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(popularityPeriod: period));
            },
          )),
          IconButton(tooltip: AppLocalizations.of(context)!.tooltipRefreshPopular,
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
            label: const HypText('등록일 다시 가져오기'),
          )),
      if (_popularityBusy || _publicationBusy) const LinearProgressIndicator(),
      if (_sortLoadError != null &&
          {'hitomiPopular', 'published'}.contains(widget.readerSettings.librarySort))
        Padding(padding: const EdgeInsets.only(top: 5),
          child: HypText(_sortLoadError!,
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
          onPressed: widget.library.works.length < 2 || _groupScanBusy
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
      if (_works.any((work) => !work.completed &&
          work.totalPages > 0 && work.currentPage >= work.totalPages))
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: _reviewLegacyCompletion,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(AppLocalizations.of(context)!.legacyCompletionReview),
        )),
      _selectionControls(_visibleLibraryWorks),
      const SizedBox(height: 8),
      if (widget.readerSettings.completedHidden &&
          _visibleLibraryWorks.isEmpty && widget.library.works.isNotEmpty)
        Padding(padding: const EdgeInsets.all(12),
          child: Column(children: [
            const HypText('모든 작품이 완독으로 분류돼 숨겨져 있어.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(completedHidden: false)),
              icon: const Icon(Icons.visibility),
              label: const HypText('완독 작품 다시 표시'),
            ),
          ]),
        )
      else
        _groupedLibraryGrid(_visibleLibraryWorks),
    ],
  );

  static String _nativeLanguageName(String code) => switch (code) {
    'korean' => '한국어',
    'japanese' => '日本語',
    'english' => 'English',
    'chinese' => '中文',
    _ => code,
  };

  String _searchFieldLabel(BuildContext context, String field) {
    final l = AppLocalizations.of(context)!;
    return switch (field) {
      'general' => l.searchGeneral,
      'artist' => l.searchArtist,
      'group' => l.searchGroup,
      'series' => l.searchSeries,
      'tag' => l.searchTag,
      'female' => l.searchFemale,
      'male' => l.searchMale,
      'web' => l.webSearchSourceLabel,
      'advanced' => l.searchAdvanced,
      _ => field,
    };
  }

  String _savedOnlineEditionHint(List<OnlineSearchWork> editions) {
    for (final online in editions) {
      final match = OnlineEditionGroups.savedAnchor(
          online, widget.library.works);
      if (match != null) {
        return AppLocalizations.of(context)!.onlineLinkedShelf(match.title);
      }
    }
    return '';
  }

  bool _isBlockedOnline(OnlineSearchWork work) => widget.blacklist.blocks(
    id: work.workId, title: work.title, artists: work.artists,
    groups: work.groups, tags: work.tags);

  Future<void> _showBlacklistManager() => showDialog<void>(
    context: context,
    builder: (_) => BlacklistManagerDialog(
      rules: widget.blacklist,
      onSave: widget.onSaveBlacklist,
      onExport: widget.onBlacklistExport,
      onImport: widget.onBlacklistImport,
    ),
  );

  Widget _searchContent() {
    final merged = <String, OnlineSearchWork>{
      for (final work in _remoteResults) work.workId: work,
    };
    for (final work in _webSearchResults.values) {
      merged.update(work.workId,
          (existing) => OnlineWorkSearch.combineWorks(existing, work),
          ifAbsent: () => work);
    }
    final webFieldMatches = <String, List<String>>{
      ..._remoteFieldMatches,
      for (final work in _webSearchResults.values)
        work.workId: <String>{
          ...?_remoteFieldMatches[work.workId], 'web',
        }.toList(),
    };
    final visibleRemote = merged.values.where((work) =>
        !_isBlockedOnline(work)).toList();
    final hiddenCount = merged.length - visibleRemote.length;
    // Web-captured works must be counted even if no blacklist rule hid
    // anything; the mirror's cached totals alone omit these new works.
    final visibleFieldTotals =
        OnlineWorkSearch.facetCounts(visibleRemote, webFieldMatches);
    final existingIds = widget.library.works.map((w) => w.workId).toSet();
    final remoteFiltered = visibleRemote.where((w) =>
        (_remoteFieldFilter.isEmpty ||
         (webFieldMatches[w.workId] ?? const <String>[])
             .contains(_remoteFieldFilter))).toList();
    final savedOnline = remoteFiltered.where((w) =>
        existingIds.contains(w.workId)).toList();
    final online = visibleRemote.where((w) =>
        !existingIds.contains(w.workId) &&
        (_remoteFieldFilter.isEmpty ||
         (webFieldMatches[w.workId] ?? const <String>[])
             .contains(_remoteFieldFilter))).toList();
    const facetOrder = [
      'general', 'artist', 'group', 'series', 'tag',
      'female', 'male', 'web', 'advanced',
    ];
    // Never hide a field merely because it has not yet been queried.
    final visibleFacets = facetOrder.where((field) =>
        field != 'advanced' || _searchedRemoteFields.contains('advanced') ||
        _remoteFieldFilter == 'advanced').toList();
    final showLocal = _searchScope != 'online' &&
        _search.text.trim().isNotEmpty;
    final showOnline = _searchScope != 'local';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HypSectionTitle(icon: Icons.search_rounded,
          title: HypI18n.t(context, '통합 작품 검색'),
          subtitle: HypI18n.t(context, '내 서재와 온라인 작품을 함께 찾아봐.')),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final entry in const [('all','전체'),('local','내 서재'),('online','온라인')])
            ChoiceChip(
              key: Key('search-scope-' + entry.$1),
              label: HypText(entry.$2),
              selected: _searchScope == entry.$1,
              onSelected: (_) => setState(() {
                _searchScope = entry.$1;
                _changedSearch();
              }),
            ),
          PopupMenuButton<String>(
            tooltip: AppLocalizations.of(context)!.tooltipSearchLanguage,
            onSelected: (value) {
              setState(() => _searchLanguage = value);
              _changedSearch();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: '', child: HypText('모든 언어')),
              PopupMenuItem(value: 'korean', child: Text('한국어')),
              PopupMenuItem(value: 'japanese', child: Text('日本語')),
              PopupMenuItem(value: 'english', child: HypText('English')),
              PopupMenuItem(value: 'chinese', child: HypText('中文')),
            ],
            child: Chip(label: Text(_searchLanguage.isEmpty
                ? HypI18n.t(context, '언어 전체 ▾')
                : AppLocalizations.of(context)!.searchLanguageChip(
                    _nativeLanguageName(_searchLanguage)))),
          ),
        ]),
      if (showLocal) ...[
        const SizedBox(height: 13),
        Text(AppLocalizations.of(context)!.searchLocalCount(_results.length),
            style: Theme.of(context).textTheme.titleMedium),
        Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
          key: const Key('search-select-mode'),
          onPressed: _toggleSelectionMode,
          icon: Icon(_selectingWorks ? Icons.close : Icons.checklist_outlined),
          label: HypText(_selectingWorks ? '선택 종료' : '선택'),
        )),
        _selectionControls(_results),
        if (_results.isEmpty)
          _gridOrEmpty(_results,
            emptyTitle: '내 서재에서 찾지 못했어',
            emptyMessage: '온라인 결과가 나오면 아래에서 확인해 봐.')
        else if (_selectingWorks)
          // In bulk-selection mode each physical edition is selectable.
          _gridOrEmpty(_results,
            emptyTitle: '내 서재에서 찾지 못했어',
            emptyMessage: '온라인 결과가 나오면 아래에서 확인해 봐.')
        else
          // Normal search mirrors the shelf's logical edition-stack cards.
          _editionAwareGrid(_results),
      ],
      if (showOnline) ...[
        const SizedBox(height: 18),
        Text(AppLocalizations.of(context)!.searchFetchedUnique(visibleRemote.length),
            style: Theme.of(context).textTheme.titleMedium),
        if (_webSearchResults.isNotEmpty)
          Text(AppLocalizations.of(context)!
              .webSearchImported(_webSearchResults.length)),
        if (hiddenCount > 0)
          HypText('블랙리스트로 $hiddenCount개 숨김'),
        if (_search.text.trim().isNotEmpty)
          Row(children: [
            Expanded(child: SingleChildScrollView(
              key: const Key('search-facet-scroll'),
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                FilterChip(
                  key: const Key('search-facet-all'),
                  label: Text(AppLocalizations.of(context)!.searchAllFields),
                  selected: _remoteFieldFilter.isEmpty,
                  onSelected: (_) => _selectRemoteFacet('', true),
                ),
                const SizedBox(width: 6),
                for (final field in visibleFacets) ...[
                  FilterChip(
                    key: Key('search-facet-' + field),
                    label: Text(!_searchedRemoteFields.contains(field) &&
                        !_loadingRemoteFacets.contains(field)
                        ? _searchFieldLabel(context, field) + ' · ' +
                            HypI18n.t(context, '미검색')
                        : _loadingRemoteFacets.contains(field)
                            ? _searchFieldLabel(context, field) + ' · ' +
                                HypI18n.t(context, '검색 중')
                            : AppLocalizations.of(context)!.searchFieldCount(
                                _searchFieldLabel(context, field),
                                visibleFieldTotals[field] ?? 0)),
                    selected: _remoteFieldFilter == field,
                    onSelected: (chosen) => _selectRemoteFacet(field, chosen),
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
            )),
            IconButton(
              key: const Key('search-blacklist-manage'),
              tooltip: HypI18n.t(context, '블랙리스트 관리'),
              onPressed: _showBlacklistManager,
              icon: const Icon(Icons.shield_outlined),
            ),
          ]),
        if (_remoteResults.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: HypText('분야별 수치는 현재 수집된 고유 작품 기준이야.',
                style: TextStyle(fontSize: 11)),
          ),
        if (_remoteWarnings.isNotEmpty)
          ExpansionTile(
            title: Text(AppLocalizations.of(context)!.searchPartialSources),
            children: [
              for (final warning in _remoteWarnings.take(10))
                ListTile(dense: true, title: SelectableText(warning)),
            ],
          ),
        const SizedBox(height: 8),
        if (_remoteBusy || _loadingRemoteFacets.isNotEmpty) ...[
          const LinearProgressIndicator(),
          if (_remoteBusy && _remoteProgressTotal > 0)
            Text(AppLocalizations.of(context)!.searchProgress(
                _remoteProgressDone, _remoteProgressTotal)),
          if (_loadingRemoteFacets.isNotEmpty)
            HypText('선택한 분야 추가 검색 중: ' +
                _loadingRemoteFacets.join(', ')),
        ],
        if (_remoteError != null) ...[
          HypText('온라인 검색에 실패했어. 내 서재 검색은 정상 동작해.\n' +
              _remoteError!, style: const TextStyle(color: Colors.orangeAccent)),
          TextButton.icon(onPressed: () => _fetchOnlineSearch(epoch: _searchEpoch),
            icon: const Icon(Icons.refresh), label: const HypText('다시 검색')),
        ],
        if (_remoteFacetError != null) ...[
          HypText('분야별 추가 검색 오류: ' + _remoteFacetError!,
              style: const TextStyle(color: Colors.orangeAccent)),
          TextButton.icon(
            onPressed: () => _loadRemoteFacet(_remoteFieldFilter,
                epoch: _searchEpoch,
                next: _loadedRemoteFacets.contains(_remoteFieldFilter)),
            icon: const Icon(Icons.refresh),
            label: const HypText('분야 검색 다시 시도'),
          ),
        ],
        if (!_remoteBusy && _remoteError == null &&
            _remoteResults.isEmpty && _webSearchResults.isEmpty)
          const Padding(padding: EdgeInsets.all(15),
            child: HypText('온라인 결과가 아직 없어. 제목이나 작가·태그로 검색해 줘.')),
        if (savedOnline.isNotEmpty)
          ExpansionTile(
            key: const Key('search-saved-online'),
            title: HypText('이미 서재에 있는 온라인 결과 ' +
                savedOnline.length.toString() + '개'),
            children: [for (final work in savedOnline.take(60))
              ListTile(title: HypAnimatedTitle(title: work.title),
                subtitle: Text('#' + work.workId + ' · 저장됨'))],
          ),
        HypText('새 작품 ' + online.length.toString() +
            '개 · 표시 카드 ' +
            OnlineEditionGroups.cluster(online).length.toString() + '개'),
        for (final group in OnlineEditionGroups.cluster(online)) Card(
          key: group.length > 1
              ? Key('online-edition-stack-' + group.first.workId)
              : Key('online-search-' + group.first.workId),
          child: ListTile(
            leading: Icon(group.length > 1
                ? Icons.layers_outlined : Icons.menu_book_outlined),
            title: HypAnimatedTitle(title: group.first.title),
            subtitle: Text(group.length > 1
                ? [
                    AppLocalizations.of(context)!.editionCount(group.length),
                    group.map((w) => WorkEditions.languageName(w.language))
                        .toSet().join(' · '),
                    if (_savedOnlineEditionHint(group).isNotEmpty)
                      _savedOnlineEditionHint(group),
                  ].join(' · ')
                : [
                    if (_webSearchResults.containsKey(group.first.workId))
                      AppLocalizations.of(context)!.webSearchSourceLabel,
                    if (group.first.artists.isNotEmpty)
                      group.first.artists.join(', '),
                    if (group.first.language.isNotEmpty) group.first.language,
                    '#' + group.first.workId,
                    if (_savedOnlineEditionHint(group).isNotEmpty)
                      _savedOnlineEditionHint(group),
                    if ((webFieldMatches[group.first.workId] ??
                         const <String>[]).isNotEmpty)
                      AppLocalizations.of(context)!.searchResultMatches(
                        webFieldMatches[group.first.workId]!
                          .map((field) => _searchFieldLabel(context, field))
                          .join(', ')),
                  ].join(' · '), maxLines: 3),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: Key('blacklist-online-' + group.first.workId),
                tooltip: HypI18n.t(context, '블랙리스트에 추가'),
                onPressed: () => widget.onBlacklistAdd(BlacklistRule(
                    kind: 'id', value: group.first.workId)),
                icon: const Icon(Icons.block_outlined),
              ),
              IconButton(
              tooltip: group.length > 1
                  ? AppLocalizations.of(context)!.editionChoose
                  : AppLocalizations.of(context)!.tooltipAddLibrary,
              onPressed: group.length > 1
                  ? () => _showOnlineEditionCandidates(group)
                  : () => widget.onSaveOnlineSearchWork(group.first),
              icon: Icon(group.length > 1 ? Icons.language
                  : Icons.bookmark_add_outlined),
            ),
            ]),
            onTap: group.length > 1
                ? () => _showOnlineEditionCandidates(group)
                : () => _showOnlineWork(group.first),
          ),
        ),
        if (!_remoteBusy && !_loadingRemoteFacets.contains(_remoteFieldFilter) &&
            ((_remoteFieldFilter.isEmpty ||
              _remoteFieldFilter == 'general' ||
              _remoteFieldFilter == 'advanced')
                ? _remoteHasMore && _remoteResults.isNotEmpty
                : _moreRemoteFacets.contains(_remoteFieldFilter)))
          OutlinedButton.icon(
            onPressed: () {
              final field = _remoteFieldFilter;
              if (field.isEmpty || field == 'general' || field == 'advanced') {
                _fetchOnlineSearch(epoch: _searchEpoch, next: true);
              } else {
                _loadRemoteFacet(field, epoch: _searchEpoch, next: true);
              }
            },
            icon: const Icon(Icons.expand_more),
            label: const HypText('온라인 결과 더 보기'),
          ),
      ],
    ]);
  }

  Future<void> _showOnlineEditionCandidates(
      List<OnlineSearchWork> candidates) async {
    if (!mounted) return;
    await ReaderNavigationFocus.showResult<void>(
      returnFocus: _dashboardFocus,
      isMounted: () => mounted,
      openRoute: () => showModalBottomSheet<void>(
        context: context, isScrollControlled: true,
        builder: (sheet) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(AppLocalizations.of(sheet)!.editionChoose,
              style: Theme.of(sheet).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(height: 320, child: ListView.builder(
            itemCount: candidates.length,
            itemBuilder: (_, index) {
              final work = candidates[index];
              return ListTile(
                key: Key('online-edition-choice-' + work.workId),
                title: HypAnimatedTitle(title: work.title),
                subtitle: Text(WorkEditions.languageName(work.language) +
                    ' · #' + work.workId),
                onTap: () {
                  Navigator.pop(sheet);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showOnlineWork(work);
                  });
                },
              );
            },
          )),
        ]),
      )),
      ),
    );
  }

  Future<void> _showOnlineWork(OnlineSearchWork work) async {
    await ReaderNavigationFocus.showResult<void>(
      returnFocus: _dashboardFocus,
      isMounted: () => mounted,
      openRoute: () => showModalBottomSheet<void>(
        context: context, isScrollControlled: true,
        builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HypText(work.title, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 10),
          HypText('#' + work.workId),
          if (work.artists.isNotEmpty) HypText('작가: ' + work.artists.join(', ')),
          if (work.groups.isNotEmpty) HypText('서클: ' + work.groups.join(', ')),
          if (work.tags.isNotEmpty)
            HypText('태그: ' + work.tags.take(20).join(', ')),
          const SizedBox(height: 15),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onSaveOnlineSearchWork(work);
              },
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const HypText('서재 추가'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openReaderWith(() => widget.onReadOnlineSearchWork(work));
              },
              icon: const Icon(Icons.menu_book),
              label: const HypText('서재 추가하고 읽기'),
            ),
            FilledButton.icon(
              key: const Key('online-preview-without-save'),
              onPressed: () {
                Navigator.pop(ctx);
                _openReaderWith(() => widget.onPreviewOnlineSearchWork(work));
              },
              icon: const Icon(Icons.visibility_outlined),
              label: HypText(HypI18n.t(context, '저장하지 않고 미리보기')),
            ),
            IconButton(
              tooltip: HypI18n.t(context, '블랙리스트에 추가'),
              onPressed: () {
                Navigator.pop(ctx);
                widget.onBlacklistAdd(BlacklistRule(kind: 'id',
                    value: work.workId));
              },
              icon: const Icon(Icons.block_outlined),
            ),
          ]),
        ]),
      )),
      ),
    );
  }

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
          _openReaderWith(() => widget.onOpenGallery(work));
        } else {
          _openReaderWith(() => widget.onReadOnline(work));
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
      await _openReaderWith(() => widget.onOpenGallery(work));
    } else if (action == 'online') {
      await _openReaderWith(() => widget.onReadOnline(work));
    } else if (action == 'page') {
      await _openReaderWith(() => widget.onReadWebPage(work));
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
    } else if (action == 'completed') {
      await widget.onSetCompleted(work, !work.completed);
    } else if (action == 'find_editions') {
      await _findOtherEditions(work);
    } else if (action == 'unlink_edition') {
      if (work.editionGroupId.isNotEmpty) await widget.onUnlinkEdition(work);
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
              title: HypText(purpose),
              content: SizedBox(
                width: 460, height: 380,
                child: Column(children: [
                  TextField(controller: input,
                    decoration: InputDecoration(
                      labelText: HypI18n.t(context, '작품 번호 또는 제목으로 검색')),
                    onChanged: (_) => update(() {})),
                  const SizedBox(height: 8),
                  Expanded(child: ListView.builder(
                    itemCount: works.length,
                    itemBuilder: (_, i) => ListTile(
                      title: HypAnimatedTitle(title: works[i].title),
                      subtitle: HypText('#' + works[i].workId),
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
        subtitle: AppLocalizations.of(context)!
            .downloadsStoredCount(_downloaded.length),
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
      if (widget.failedDownloads.isNotEmpty) ...[
        FailedDownloadsPanel(
          failedDownloads: widget.failedDownloads,
          onRetry: widget.onRetryFailedDownload,
          onDismiss: widget.onDismissFailedDownload,
          onClearAll: widget.onClearFailedDownloads,
        ),
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
                      title: HypAnimatedTitle(
                        title: work.title.isEmpty
                            ? '작품 ' + work.workId : work.title,
                      ),
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
      _settingsPanel('general', AppLocalizations.of(context)!.settingsGeneral, Column(
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
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('preferred-edition-language'),
            initialValue: widget.readerSettings.preferredEditionLanguage,
            decoration: InputDecoration(
                labelText: HypI18n.t(context, '선호 작품 언어')),
            items: const [
              DropdownMenuItem(value: 'auto', child: HypText('자동 선택')),
              DropdownMenuItem(value: 'recent', child: HypText('마지막 열람 언어판')),
              DropdownMenuItem(value: 'korean', child: Text('한국어')),
              DropdownMenuItem(value: 'japanese', child: Text('日本語')),
              DropdownMenuItem(value: 'english', child: Text('English')),
              DropdownMenuItem(value: 'chinese', child: Text('中文')),
            ],
            onChanged: (value) {
              if (value != null) widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(preferredEditionLanguage: value));
            },
          ),
        ],
      )),
      const SizedBox(height: 10),
      if (Platform.isWindows) ...[
         _settingsPanel('dpi', AppLocalizations.of(context)!.dpiSettingsTitle,
           const WindowsDpiSettingsPanel()),
         const SizedBox(height: 10),
       ],
       if (Platform.isAndroid) ...[
         _settingsPanel('androidDpi',
             AppLocalizations.of(context)!.androidDpiTitle,
             const AndroidDpiSettingsPanel()),
         const SizedBox(height: 10),
       ],
       _settingsPanel('hero', AppLocalizations.of(context)!.settingsHero, Column(
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
          Text(AppLocalizations.of(context)!.settingsHeroUploadNote,
              style: const TextStyle(fontSize: 12, color: HypColors.muted)),
        ],
      )),
      const SizedBox(height: 10),
      _settingsPanel('blacklist', HypI18n.t(context, '블랙리스트'),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HypText(HypI18n.t(context, '차단된 작품은 검색과 번호 검증에서 제외돼.')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('settings-blacklist-open'),
            onPressed: _showBlacklistManager,
            icon: const Icon(Icons.shield_outlined),
            label: HypText(HypI18n.t(context, '블랙리스트 관리')),
          ),
        ])),
      const SizedBox(height: 10),
      _settingsPanel('viewer', AppLocalizations.of(context)!.settingsViewer, Column(
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
              subtitle: Text(AppLocalizations.of(context)!.settingsTapZonesNote),
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
              key: const Key('reader-start-hidden-setting'),
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.settingsReaderHideOnOpen),
              subtitle: Text(AppLocalizations.of(context)!.settingsReaderHideOnOpenHint),
              value: widget.readerSettings.hideReaderUiOnOpen,
              onChanged: (v) => widget.onSaveReaderSettings(
                  widget.readerSettings.copyWith(hideReaderUiOnOpen: v)),
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('reader-complete-confirm-setting'),
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.settingsCompleteConfirmTitle),
              subtitle: Text(AppLocalizations.of(context)!.settingsCompleteConfirmHint),
              value: widget.readerSettings.confirmCompleteOnNext,
              onChanged: (v) => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(confirmCompleteOnNext: v)),
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
                title: Text(AppLocalizations.of(context)!.settingsSpreadAction),
                subtitle: Text(AppLocalizations.of(context)!.settingsSpreadActionHint),
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
            subtitle: Text(AppLocalizations.of(context)!.settingsDataSaverNote),
            value: widget.readerSettings.dataSaverMode,
            onChanged: (v) => widget.onSaveReaderSettings(
              widget.readerSettings.copyWith(dataSaverMode: v)),
          ),
          const SizedBox(height: 8),
          Text(AppLocalizations.of(context)!.settingsKeyboardHint,
            style: const TextStyle(fontSize: 12, color: HypColors.muted),
          ),
        ],
      )),
      const SizedBox(height: 10),
      _settingsPanel('cover', AppLocalizations.of(context)!.settingsCover, Column(
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
      _settingsPanel('android', AppLocalizations.of(context)!.settingsAndroid, Column(
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
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            key: const Key('volume-hold-speed-setting'),
            initialValue: widget.readerSettings.volumeHoldIntervalMs,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.settingsVolumeRepeatSpeed,
              helperText: AppLocalizations.of(context)!.settingsVolumeRepeatHint,
            ),
            items: [
              DropdownMenuItem(value: 700,
                child: Text(AppLocalizations.of(context)!.settingsVolumeSlow)),
              DropdownMenuItem(value: 400,
                child: Text(AppLocalizations.of(context)!.settingsVolumeNormal)),
              DropdownMenuItem(value: 200,
                child: Text(AppLocalizations.of(context)!.settingsVolumeFast)),
            ],
            onChanged: !widget.readerSettings.volumeKeyNavigation ? null
                : (interval) {
                    if (interval != null) widget.onSaveReaderSettings(
                      widget.readerSettings.copyWith(volumeHoldIntervalMs: interval));
                  },
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
      _settingsPanel('notices', AppLocalizations.of(context)!.settingsNotices, Column(
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
      _settingsPanel('web', AppLocalizations.of(context)!.settingsWeb, Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            key: const Key('auto-web-search-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(AppLocalizations.of(context)!.autoWebSearchEnable),
            subtitle: Text(AppLocalizations.of(context)!.autoWebSearchDescription),
            value: widget.readerSettings.autoWebSearch,
            onChanged: (value) => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(autoWebSearch: value)),
          ),
          const SizedBox(height: 8),
          Text(AppLocalizations.of(context)!.webAdBlockTitle),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'off', label: Text(AppLocalizations.of(context)!.webAdBlockOff)),
              ButtonSegment(value: 'standard', label: Text(AppLocalizations.of(context)!.webAdBlockStandard)),
              ButtonSegment(value: 'strong', label: Text(AppLocalizations.of(context)!.webAdBlockStrong)),
            ],
            selected: {widget.readerSettings.webSearchAdBlockMode},
            onSelectionChanged: (mode) => widget.onSaveReaderSettings(
              widget.readerSettings.copyWith(webSearchAdBlockMode: mode.first)),
          ),
          const SizedBox(height: 8),
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
      _settingsPanel('source', AppLocalizations.of(context)!.settingsSource, Column(
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
      _settingsPanel('deletion', '서재 삭제·Windows 종료', Column(
        children: [
          SwitchListTile.adaptive(
            key: const Key('delete-local-files-default-setting'),
            title: const HypText('로컬 파일도 함께 삭제 (기본 체크)'),
            subtitle: const HypText('단일·다중 삭제 팝업에서 체크 상태를 미리 정해. 삭제할 때마다 해제할 수 있어.'),
            value: widget.readerSettings.deleteLocalFilesByDefault,
            onChanged: (v) => widget.onSaveReaderSettings(
              widget.readerSettings.copyWith(deleteLocalFilesByDefault: v)),
          ),
          if (Platform.isWindows) SwitchListTile.adaptive(
            key: const Key('windows-close-exits-app-setting'),
            title: const HypText('X 버튼을 누르면 완전 종료'),
            subtitle: const HypText('끄면 창만 숨기고 트레이에 남아. 켜면 앱과 트레이를 종료해.'),
            value: widget.readerSettings.closeWindowExitsApp,
            onChanged: (v) => widget.onSaveReaderSettings(
              widget.readerSettings.copyWith(closeWindowExitsApp: v)),
          ),
        ],
      )),
      const SizedBox(height: 13),
      _settingsPanel('backup', AppLocalizations.of(context)!.settingsBackup, Column(
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
      _settingsPanel('updates', AppLocalizations.of(context)!.settingsUpdates, Column(
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
          SwitchListTile.adaptive(
            key: const Key('startup-update-prompt-setting'),
            contentPadding: EdgeInsets.zero,
            title: const HypText('실행 시 업데이트 알림'),
            subtitle: const HypText('새 버전이 나오면 실행 후 안내해. 버전별로 7일간 숨길 수 있어.'),
            value: widget.readerSettings.startupUpdatePrompt,
            onChanged: (enabled) => widget.onSaveReaderSettings(
              widget.readerSettings.copyWith(startupUpdatePrompt: enabled)),
          ),
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
