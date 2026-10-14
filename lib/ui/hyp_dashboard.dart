import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/gallery.dart';
import '../core/cover_store.dart';
import '../core/reader_settings.dart';
import '../core/number_extractor.dart';
import '../core/work.dart';
import 'hero_banner.dart';
import 'hyp_theme.dart';
import 'shorts_finder_panel.dart';
import 'work_cards.dart';

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
  final bool downloadingUpdate;
  final double updateProgress;
  final String? downloadingGalleryKey;
  final int downloadedGalleryPages;
  final int totalGalleryPages;
  final int downloadedGalleryBytes;
  final VoidCallback onAnalyze;
  final Future<void> Function() onFetch;
  final Future<void> Function() onSaveWork;
  final Future<void> Function(List<String> codes) onSaveSelectedWorks;
  final Future<void> Function() onChooseHeroArtwork;
  final Future<void> Function() onClearHeroArtwork;
  final Future<void> Function() onSaveOnlineSource;
  final Future<void> Function() onExportJson;
  final Future<void> Function() onExportExcel;
  final Future<void> Function() onImportJson;
  final Future<void> Function() onCheckRelease;
  final Future<void> Function() onCheckAnnouncements;
  final Future<void> Function() onSecurityHelp;
  final Future<void> Function(WorkEntry) onOpenGallery;
  final Future<void> Function(WorkEntry) onReadOnline;
  final Future<void> Function(WorkEntry) onReadWebPage;
  final Future<void> Function(WorkEntry) onDownloadOnline;
  final Future<void> Function(WorkEntry) onDownloadJsonSource;
  final Future<void> Function(WorkEntry) onDeleteOffline;
  final VoidCallback onToggleDownloadPause;
  final bool downloadPaused;
  final bool downloadCanPause;
  final Future<void> Function(WorkEntry) onImportGallery;
  final Future<void> Function(WorkEntry) onUpdateWork;
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
    required this.downloadingUpdate,
    required this.updateProgress,
    required this.downloadingGalleryKey,
    required this.downloadedGalleryPages,
    required this.totalGalleryPages,
    required this.downloadedGalleryBytes,
    required this.onAnalyze,
    required this.onFetch,
    required this.onSaveWork,
    required this.onSaveSelectedWorks,
    required this.onChooseHeroArtwork,
    required this.onClearHeroArtwork,
    required this.onSaveOnlineSource,
    required this.onExportJson,
    required this.onExportExcel,
    required this.onImportJson,
    required this.onCheckRelease,
    required this.onCheckAnnouncements,
    required this.onSecurityHelp,
    required this.onOpenGallery,
    required this.onReadOnline,
    required this.onReadWebPage,
    required this.onDownloadOnline,
    required this.onDownloadJsonSource,
    required this.onDeleteOffline,
    required this.onToggleDownloadPause,
    required this.downloadPaused,
    required this.downloadCanPause,
    required this.onImportGallery,
    required this.onUpdateWork,
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
  final Set<String> _offlineKeys = <String>{};
  final Map<String, int> _pageCounts = <String, int>{};
  final Map<String, Uint8List> _coverImages = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    _search.addListener(_changedSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshOffline());
  }

  @override
  void didUpdateWidget(covariant HypDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationEpoch != widget.navigationEpoch) {
      _page = HypPage.home;
      _search.clear();
    }
    if (oldWidget.library.works.length != widget.library.works.length ||
        oldWidget.coverEpoch != widget.coverEpoch ||
        _coverSignature(oldWidget.library) != _coverSignature(widget.library)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshOffline());
    }
  }

  @override
  void dispose() {
    _search.removeListener(_changedSearch);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _changedSearch() {
    if (mounted) setState(() {});
  }

  void _navigate(HypPage page) {
    _search.clear();
    setState(() => _page = page);
  }

  String _coverSignature(LibraryBackup backup) => backup.works
      .map((w) => w.key + ':' + w.coverMode + ':' +
          w.coverPreset.toString() + ':' + w.coverPage.toString())
      .join('|');

  Future<void> _refreshOffline() async {
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
    if (!mounted) return;
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
    });
  }

  List<WorkEntry> get _works => [...widget.library.works]
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<WorkEntry> get _favorites => _works.where((w) => w.favorite).toList();

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
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _onKeyboardShortcut,
    child: LayoutBuilder(builder: (context, size) {
    final desktop = size.maxWidth >= 940;
    return Scaffold(
      backgroundColor: HypColors.background,
      drawer: desktop ? null : Drawer(
        backgroundColor: HypColors.background,
        child: SafeArea(child: _sidebar(closeDrawer: true)),
      ),
      appBar: desktop ? null : AppBar(
        backgroundColor: HypColors.background,
        title: const Text('HYP Viewer'),
        actions: [
          IconButton(
            tooltip: '관리자 공지 확인',
            onPressed: widget.onCheckAnnouncements,
            icon: const Icon(Icons.notifications_outlined),
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
              child: _contents(),
            ),
          ),
        ])),
      ]),
      bottomNavigationBar: desktop ? null : NavigationBar(
        backgroundColor: HypColors.surface,
        indicatorColor: HypColors.primary.withValues(alpha: 0.45),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        selectedIndex: [
          HypPage.home, HypPage.library, HypPage.favorites,
          HypPage.downloads, HypPage.settings,
        ].indexOf(_page).clamp(0, 4).toInt(),
        onDestinationSelected: (index) => _navigate([
          HypPage.home, HypPage.library, HypPage.favorites,
          HypPage.downloads, HypPage.settings,
        ][index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded), label: '홈'),
          NavigationDestination(icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books), label: '서재'),
          NavigationDestination(icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite), label: '즐겨찾기'),
          NavigationDestination(icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download), label: '다운로드'),
          NavigationDestination(icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }),
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
            Text('HYP Viewer', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800)),
            SizedBox(height: 3),
            Text('좋아하는 이야기를,\n더 가까이',
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
                  Text(page.label, style: TextStyle(
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
      const Text('오프라인 보관함',
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
      Text(
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
    PopupMenuItem(value: 'import', child: Text('JSON 서재 가져오기')),
    PopupMenuItem(value: 'export', child: Text('JSON 내보내기')),
    PopupMenuItem(value: 'excel', child: Text('Excel 내보내기')),
    PopupMenuItem(value: 'history', child: Text('열람 기록')),
    PopupMenuItem(value: 'settings', child: Text('설정')),
  ];

  void _toolsAction(String value) {
    if (value == 'import') {
      widget.onImportJson();
    } else if (value == 'export') {
      widget.onExportJson();
    } else if (value == 'excel') {
      widget.onExportExcel();
    } else if (value == 'history') {
      _navigate(HypPage.history);
    } else if (value == 'settings') {
      _navigate(HypPage.settings);
    }
  }

  Widget _searchField() => TextField(
    key: const Key('library-search-input'),
    focusNode: _searchFocus,
    controller: _search,
    decoration: const InputDecoration(
      hintText: '작품 제목, 작가, 번호, 목록으로 검색하세요...',
      prefixIcon: Icon(Icons.search_rounded, color: HypColors.muted),
    ),
  );

  Widget _contents() {
    final pageContent = _search.text.trim().isNotEmpty
        ? _searchContent()
        : switch (_page) {
            HypPage.home => _homeContent(),
            HypPage.library => _fullPage('내 서재',
                '추가한 작품과 읽기 진행도를 관리하세요.',
                HypPage.library.icon, _works),
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
      children: [
        if (widget.message.isNotEmpty) ...[
          HypPanel(
            color: HypColors.raised,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                color: HypColors.lightPurple, size: 19),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.message, maxLines: 3,
                overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: '알림 닫기',
                onPressed: widget.onDismissMessage,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        pageContent,
      ],
    );
  }

  Widget _homeContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HypHeroBanner(
        artwork: widget.heroArtwork,
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
        onSaveSelectedWorks: widget.onSaveSelectedWorks,
      ),
      const SizedBox(height: 24),
      HypSectionTitle(
        icon: Icons.library_books_rounded,
        title: '최근 본 작품',
        subtitle: '최근 열람한 작품을 이어서 감상하세요.',
        actionLabel: '전체 보기',
        onAction: () => _navigate(HypPage.history),
      ),
      const SizedBox(height: 12),
      _gridOrEmpty(
        _recent.take(5).toList(),
        emptyTitle: '아직 열람 기록이 없어',
        emptyMessage: '서재에 작품을 추가하고 읽기를 시작하면 여기에 표시돼.',
      ),
      const SizedBox(height: 24),
      HypSectionTitle(
        icon: Icons.star_rounded,
        title: '추천 작품',
        subtitle: '즐겨찾기한 작품 중 다시 살펴볼 작품이야.',
        actionLabel: '더보기',
        onAction: () => _navigate(HypPage.favorites),
      ),
      const SizedBox(height: 12),
      _gridOrEmpty(
        _favorites.take(5).toList(),
        emptyTitle: '아직 추천할 서재 작품이 없어',
        emptyMessage: '임의 추천 대신 실제 즐겨찾기한 작품만 표시해.',
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

  Widget _searchContent() => _fullPage(
    '검색 결과',
    '"' + _search.text + '" · ' + _results.length.toString() + '개 작품',
    Icons.search_rounded,
    _results,
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
    } else if (action == 'import') {
      await widget.onImportGallery(work);
      await _refreshOffline();
    } else if (action == 'cover') {
      await widget.onChooseCover(work);
      await _refreshOffline();
    } else if (action == 'favorite') {
      await widget.onUpdateWork(work.copyWith(favorite: !work.favorite));
    } else if (action == 'original') {
      await widget.onOpenOriginal(work);
    }
  }

  Widget _downloadsContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HypSectionTitle(
        icon: Icons.download_rounded,
        title: '다운로드',
        subtitle: '내 기기에 저장된 작품 ' + _downloaded.length.toString() + '개',
      ),
      const SizedBox(height: 15),
      if (widget.downloadingGalleryKey != null) ...[
        HypPanel(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('작품 다운로드 중',
              style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: widget.totalGalleryPages > 0
                  ? widget.downloadedGalleryPages / widget.totalGalleryPages
                  : null,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(
                widget.downloadedGalleryPages.toString() + ' / ' +
                widget.totalGalleryPages.toString() + '장 · ' +
                (widget.downloadedGalleryBytes / 1048576).toStringAsFixed(1) +
                ' MB',
              )),
              if (widget.downloadCanPause)
                TextButton.icon(
                  onPressed: widget.onToggleDownloadPause,
                  icon: Icon(widget.downloadPaused ? Icons.play_arrow : Icons.pause),
                  label: Text(widget.downloadPaused ? '계속' : '일시정지'),
                ),
              TextButton.icon(
                onPressed: widget.onCancelGalleryDownload,
                icon: const Icon(Icons.close),
                label: const Text('취소'),
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
            title: const Text('표지를 바꿀 작품 선택'),
            content: SizedBox(
              width: 500,
              height: 420,
              child: Column(children: [
                TextField(
                  key: const Key('cover-work-search'),
                  controller: search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '작품 번호 또는 제목',
                  ),
                  onChanged: (_) => refresh(() {}),
                ),
                const SizedBox(height: 10),
                Expanded(child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, index) {
                    final work = filtered[index];
                    return ListTile(
                      title: Text(work.title.isEmpty ? '작품 ' + work.workId : work.title),
                      subtitle: Text('번호 ' + work.workId),
                      onTap: () => Navigator.pop(ctx, work),
                    );
                  },
                )),
              ]),
            ),
            actions: [TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
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

  Widget _settingsContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const HypSectionTitle(
        icon: Icons.settings_rounded,
        title: '설정',
        subtitle: '뷰어 조작, 기본 표지, 추가 다운로드 소스와 앱 데이터를 관리해.',
      ),
      const SizedBox(height: 14),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('홈 배너 일러스트',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 9),
          const Text('첫 화면의 "좋아하는 이야기를, 언제 어디서나" '
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
              label: Text(widget.heroArtwork == null
                  ? '일러스트 업로드' : '일러스트 교체'),
            ),
            if (widget.heroArtwork != null)
              TextButton.icon(
                key: const Key('hero-artwork-reset'),
                onPressed: widget.onClearHeroArtwork,
                icon: const Icon(Icons.restore_rounded),
                label: const Text('기본 배경으로 되돌리기'),
              ),
          ]),
          const SizedBox(height: 7),
          const Text('PNG · JPG · WebP (최대 12MB). 이미지 자체는 '
              '이 기기에 저장되며 서재 JSON 백업에는 포함되지 않아.',
              style: TextStyle(fontSize: 12, color: HypColors.muted)),
        ],
      )),
      const SizedBox(height: 10),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('이미지 뷰어 설정', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('읽기 방향을 정하면 화면 스와이프와 방향키도 함께 적용돼.',
            style: TextStyle(fontSize: 12, color: HypColors.muted)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const Key('reader-direction-setting'),
            initialValue: widget.readerSettings.nextDirection,
            decoration: const InputDecoration(labelText: '다음 페이지로 넘기는 방향'),
            items: const [
              DropdownMenuItem(value: 'left',
                  child: Text('왼쪽으로 넘기기 (→ 다음 페이지)')),
              DropdownMenuItem(value: 'right',
                  child: Text('오른쪽으로 넘기기 (← 다음 페이지)')),
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
              key: const Key('reader-two-page-setting'),
              contentPadding: EdgeInsets.zero,
              title: const Text('2쪽 모아보기'),
              subtitle: const Text('1-2, 3-4처럼 두 페이지를 한 화면에 표시'),
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
              title: const Text('세로로 페이지 넘기기'),
              subtitle: const Text('뷰어 오른쪽 위의 가로/세로 전환 버튼과 '
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
            title: const Text('뷰어 오른쪽 위 아이콘 구성'),
            subtitle: const Text('각 버튼을 표시하거나 숨길 수 있어. 기본값은 모두 표시야.'),
            children: [
              SwitchListTile.adaptive(
                key: const Key('reader-show-download-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('다운로드 버튼 표시'),
                subtitle: const Text('온라인 이미지 저장 버튼'),
                value: widget.readerSettings.showDownloadAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showDownloadAction: v)),
              ),
              SwitchListTile.adaptive(
                key: const Key('reader-show-cover-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('표지 지정 버튼 표시'),
                subtitle: const Text('현재 페이지를 표지로 등록하는 버튼'),
                value: widget.readerSettings.showCoverAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showCoverAction: v)),
              ),
              SwitchListTile.adaptive(
                key: const Key('reader-show-page-controls-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('페이지 도구 버튼 표시'),
                subtitle: const Text('하단 페이지 바 표시/숨기기 버튼'),
                value: widget.readerSettings.showPageControlsAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showPageControlsAction: v)),
              ),
              SwitchListTile.adaptive(
                key: const Key('reader-show-web-reader-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('웹 리더 버튼 표시'),
                subtitle: const Text('현재 페이지를 브라우저에서 열기'),
                value: widget.readerSettings.showWebReaderAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showWebReaderAction: v)),
              ),
              SwitchListTile.adaptive(
                key: const Key('reader-show-orientation-action-setting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('가로/세로 전환 버튼 표시'),
                subtitle: const Text('뷰어 오른쪽 위 전환 버튼'),
                value: widget.readerSettings.showOrientationAction,
                onChanged: (v) => widget.onSaveReaderSettings(
                    widget.readerSettings.copyWith(showOrientationAction: v)),
              ),
            ],
          )),
          const SizedBox(height: 9),
          DropdownButtonFormField<int>(
            key: const Key('reader-preload-setting'),
            initialValue: widget.readerSettings.preloadPages,
            decoration: const InputDecoration(labelText: '앞뒤 미리 로딩 페이지'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('끄기')),
              DropdownMenuItem(value: 1, child: Text('1장씩')),
              DropdownMenuItem(value: 2, child: Text('2장씩 (추천)')),
              DropdownMenuItem(value: 3, child: Text('3장씩')),
            ],
            onChanged: (v) {
              if (v != null) widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(preloadPages: v));
            },
          ),
          const SizedBox(height: 8),
          const Text(
            '키보드(뷰어): ← / →, PageUp / PageDown, Space, Home / End, '
            'Esc(닫기). 서재의 작품 메뉴에서 표지 선택 가능.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
        ],
      )),
      const SizedBox(height: 10),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('표지 자동 설정 및 편집', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Material(color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('automatic-cover-setting'),
              contentPadding: EdgeInsets.zero,
              title: const Text('새 작품의 첫 페이지를 자동 표지로 사용'),
              subtitle: const Text('끄면 새 작품은 기본 디자인 표지로 시작해. '
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
            label: const Text('서재 작품 표지 편집 · 이미지 업로드 및 자르기'),
          ),
          const SizedBox(height: 8),
          const Text('이미지를 선택하거나 작품 페이지를 불러온 뒤, '
              '미리보기 영역에서 드래그·확대·축소하여 표지를 만들 수 있어.',
              style: TextStyle(fontSize: 12, color: HypColors.muted)),
        ],
      )),
      const SizedBox(height: 13),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Android 뷰어 동작', style: Theme.of(context).textTheme.titleMedium),
          Material(color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('volume-keys-setting'),
              contentPadding: EdgeInsets.zero,
              title: const Text('볼륨키로 페이지 넘기기'),
              subtitle: const Text('뷰어가 열려 있을 때 볼륨+는 이전, '
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
              title: const Text('2쪽 보기에서 가로 화면 고정'),
              subtitle: const Text('Android에서 2쪽 모아보기일 때만 가로 방향으로 열어. '
                  '끄면 휴대폰을 돌려 자유롭게 회전할 수 있어.'),
              value: widget.readerSettings.forceLandscapeForSpreads,
              onChanged: (v) => widget.onSaveReaderSettings(
                widget.readerSettings.copyWith(forceLandscapeForSpreads: v)),
            ),
          ),
        ],
      )),
      const SizedBox(height: 13),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('관리자 공지', style: Theme.of(context).textTheme.titleMedium),
          Material(color: Colors.transparent,
            child: SwitchListTile.adaptive(
              key: const Key('announcements-setting'),
              contentPadding: EdgeInsets.zero,
              title: const Text('관리자 공지 수신 (동의)'),
              subtitle: const Text('앱 실행 중이나 재실행 시 공개 공지를 확인해. '
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
            label: const Text('공지 목록 확인'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('android-security-help'),
            onPressed: widget.onSecurityHelp,
            icon: const Icon(Icons.security),
            label: const Text('Android 설치 및 보안 위험 자동 차단 안내'),
          ),
        ],
      )),
      const SizedBox(height: 13),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('기본 웹 리더 (주소 고정)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 7),
          const Text(
            '기본 온라인 읽기는 이미지 메타데이터를 이용해 앱 안에서 열어. '
            '작품 메뉴의 웹 리더를 선택하면 브라우저에서 고정 링크를 열 수 있어. '
            '1페이지는 #1-, 2페이지부터는 #2-3 형식이야.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
          const SizedBox(height: 8),
          const SelectableText('https://hitomi.la/reader/{작품번호}.html#1-'),
          const SizedBox(height: 4),
          const Text(
            '앱 안에서 읽는 경우에는 페이지 진행도가 저장돼. '
            '외부 브라우저에서 넘긴 페이지는 자동 기록되지 않아.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
        ],
      )),
      const SizedBox(height: 13),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('추가 JSON 이미지 소스 (선택)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 7),
          const Text(
            '자체 보유하거나 이용 허가된 JSON 이미지 서버를 통해 오프라인 저장하려는 경우에만 설정해줘. 기본 온라인 읽기나 웹 리더에 필요하지 않아.',
            style: TextStyle(fontSize: 12, color: HypColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('online-source-input'),
            controller: widget.onlineSourceInput,
            decoration: const InputDecoration(
              labelText: '추가 JSON 소스 URL 패턴',
              hintText: 'https://gallery.example/galleries/{workId}.json',
              helperText: '추가 JSON 소스로 다운로드할 때만 사용하는 고급 설정이야.',
            ),
          ),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: widget.onSaveOnlineSource,
              icon: const Icon(Icons.save_outlined),
              label: const Text('소스 설정 저장'),
            )),
        ],
      )),
      const SizedBox(height: 13),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('서재 데이터', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('JSON은 백업·기기 이전용, Excel은 확인용이야.',
            style: TextStyle(fontSize: 12, color: HypColors.muted)),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
              onPressed: widget.onExportJson,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('JSON 백업'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onImportJson,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('JSON 가져오기'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onExportExcel,
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Excel 내보내기'),
            ),
          ]),
        ],
      )),
      const SizedBox(height: 13),
      HypPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('업데이트', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('최신 0.x 업데이트 · GitHub Releases',
            style: TextStyle(color: HypColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onCheckRelease,
            icon: const Icon(Icons.system_update_alt_rounded),
            label: const Text('업데이트 확인'),
          ),
        ],
      )),
    ],
  );
}
