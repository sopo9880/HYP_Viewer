import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// When set to 'left', swipe/turn to the left to advance the book.
/// 'right' reverses the swipe direction for right-to-left reading.
class ReaderSettings {
  final String nextDirection; // left or right
  final bool twoPageSpread;
  final bool verticalScrolling;
  final bool showDownloadAction;
  final bool showCoverAction;
  final bool showPageControlsAction;
  final bool showWebReaderAction;
  final bool showOrientationAction;
  final int preloadPages; // -1: whole gallery to bounded disk cache
  final bool tapNavigation;
  final bool webtoonMode;
  final bool autoDownloadOnSave;
  final bool dataSaverMode;
  final String librarySort;
  final String popularityPeriod; // today, week, month, year
  final bool librarySortDescending;
  final bool recentCollapsed;
  final List<String> expandedSettings;
  final bool autoCoverEnabled;
  final bool volumeKeyNavigation;
  final bool forceLandscapeForSpreads;
  final bool receiveAnnouncements;
  final bool openAfterSave;
  final String languageCode; // ko, en, ja
  final String heroArtworkSource; // default, custom, random

  const ReaderSettings({
    this.nextDirection = 'left',
    this.twoPageSpread = false,
    this.verticalScrolling = false,
    this.showDownloadAction = true,
    this.showCoverAction = true,
    this.showPageControlsAction = true,
    this.showWebReaderAction = true,
    this.showOrientationAction = true,
    this.preloadPages = -1,
    this.tapNavigation = true,
    this.webtoonMode = false,
    this.autoDownloadOnSave = false,
    this.dataSaverMode = false,
    this.librarySort = 'newest',
    this.popularityPeriod = 'month',
    this.librarySortDescending = false,
    this.recentCollapsed = false,
    this.expandedSettings = const [],
    this.autoCoverEnabled = false,
    this.volumeKeyNavigation = false,
    this.forceLandscapeForSpreads = false,
    this.receiveAnnouncements = false,
    this.openAfterSave = false,
    this.languageCode = 'ko',
    this.heroArtworkSource = 'custom',
  });

  bool get reverse => nextDirection == 'right';

  ReaderSettings copyWith({
    String? nextDirection,
    bool? twoPageSpread,
    bool? verticalScrolling,
    bool? showDownloadAction,
    bool? showCoverAction,
    bool? showPageControlsAction,
    bool? showWebReaderAction,
    bool? showOrientationAction,
    int? preloadPages,
    bool? tapNavigation,
    bool? webtoonMode,
    bool? autoDownloadOnSave,
    bool? dataSaverMode,
    String? librarySort,
    String? popularityPeriod,
    bool? librarySortDescending,
    bool? recentCollapsed,
    List<String>? expandedSettings,
    bool? autoCoverEnabled,
    bool? volumeKeyNavigation,
    bool? forceLandscapeForSpreads,
    bool? receiveAnnouncements,
    bool? openAfterSave,
    String? languageCode,
    String? heroArtworkSource,
  }) => ReaderSettings(
    nextDirection: nextDirection ?? this.nextDirection,
    twoPageSpread: twoPageSpread ?? this.twoPageSpread,
    verticalScrolling: verticalScrolling ?? this.verticalScrolling,
    showDownloadAction: showDownloadAction ?? this.showDownloadAction,
    showCoverAction: showCoverAction ?? this.showCoverAction,
    showPageControlsAction: showPageControlsAction ?? this.showPageControlsAction,
    showWebReaderAction: showWebReaderAction ?? this.showWebReaderAction,
    showOrientationAction: showOrientationAction ?? this.showOrientationAction,
    preloadPages: preloadPages ?? this.preloadPages,
    tapNavigation: tapNavigation ?? this.tapNavigation,
    webtoonMode: webtoonMode ?? this.webtoonMode,
    autoDownloadOnSave: autoDownloadOnSave ?? this.autoDownloadOnSave,
    dataSaverMode: dataSaverMode ?? this.dataSaverMode,
    librarySort: librarySort ?? this.librarySort,
    popularityPeriod: popularityPeriod ?? this.popularityPeriod,
    librarySortDescending: librarySortDescending ?? this.librarySortDescending,
    recentCollapsed: recentCollapsed ?? this.recentCollapsed,
    expandedSettings: expandedSettings ?? this.expandedSettings,
    autoCoverEnabled: autoCoverEnabled ?? this.autoCoverEnabled,
    volumeKeyNavigation: volumeKeyNavigation ?? this.volumeKeyNavigation,
    forceLandscapeForSpreads: forceLandscapeForSpreads ?? this.forceLandscapeForSpreads,
    receiveAnnouncements: receiveAnnouncements ?? this.receiveAnnouncements,
    openAfterSave: openAfterSave ?? this.openAfterSave,
    languageCode: languageCode ?? this.languageCode,
    heroArtworkSource: heroArtworkSource ?? this.heroArtworkSource,
  );

  Map<String, Object> toJson() => {
    'nextDirection': nextDirection,
    'twoPageSpread': twoPageSpread,
    'verticalScrolling': verticalScrolling,
    'showDownloadAction': showDownloadAction,
    'showCoverAction': showCoverAction,
    'showPageControlsAction': showPageControlsAction,
    'showWebReaderAction': showWebReaderAction,
    'showOrientationAction': showOrientationAction,
    'preloadPages': preloadPages,
    'tapNavigation': tapNavigation,
    'webtoonMode': webtoonMode,
    'autoDownloadOnSave': autoDownloadOnSave,
    'dataSaverMode': dataSaverMode,
    'librarySort': librarySort,
    'popularityPeriod': popularityPeriod,
    'librarySortDescending': librarySortDescending,
    'recentCollapsed': recentCollapsed,
    'expandedSettings': expandedSettings,
    'autoCoverEnabled': autoCoverEnabled,
    'volumeKeyNavigation': volumeKeyNavigation,
    'forceLandscapeForSpreads': forceLandscapeForSpreads,
    'receiveAnnouncements': receiveAnnouncements,
    'openAfterSave': openAfterSave,
    'languageCode': languageCode,
    'heroArtworkSource': heroArtworkSource,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> data) =>
      ReaderSettings(
        nextDirection: data['nextDirection'] == 'right' ? 'right' : 'left',
        twoPageSpread: data['twoPageSpread'] == true,
        verticalScrolling: data['verticalScrolling'] == true,
        showDownloadAction: data['showDownloadAction'] != false,
        showCoverAction: data['showCoverAction'] != false,
        showPageControlsAction: data['showPageControlsAction'] != false,
        showWebReaderAction: data['showWebReaderAction'] != false,
        showOrientationAction: data['showOrientationAction'] != false,
        autoCoverEnabled: data['autoCoverEnabled'] == true,
        volumeKeyNavigation: data['volumeKeyNavigation'] == true,
        forceLandscapeForSpreads: data['forceLandscapeForSpreads'] == true,
        receiveAnnouncements: data['receiveAnnouncements'] == true,
        openAfterSave: data['openAfterSave'] == true,
        languageCode: {'ko', 'en', 'ja'}.contains(data['languageCode'])
            ? data['languageCode'] as String : 'ko',
        tapNavigation: data['tapNavigation'] != false,
        webtoonMode: data['webtoonMode'] == true,
        autoDownloadOnSave: data['autoDownloadOnSave'] == true,
        dataSaverMode: data['dataSaverMode'] == true,
        popularityPeriod: const {'today', 'week', 'month', 'year'}
                .contains(data['popularityPeriod'])
            ? data['popularityPeriod'] as String : 'month',
        librarySort: const {'newest', 'published', 'hitomiPopular',
                'mostRead', 'title', 'number'}
                .contains(data['librarySort'])
            ? data['librarySort'] as String : 'newest',
        librarySortDescending: data['librarySortDescending'] == true,
        recentCollapsed: data['recentCollapsed'] == true,
        expandedSettings: data['expandedSettings'] is List
            ? (data['expandedSettings'] as List).whereType<String>()
                .take(25).toSet().toList() : const [],
        heroArtworkSource: {'default', 'custom', 'random'}
                .contains(data['heroArtworkSource'])
            ? data['heroArtworkSource'] as String : 'custom',
        preloadPages: data['preloadPages'] is num
            ? (data['preloadPages'] as num).toInt().clamp(-1, 1500).toInt()
            : -1,
      );
}

class ReaderSettingsStorage {
  final Directory? baseDirectory;
  const ReaderSettingsStorage({this.baseDirectory});

  Future<File> get _file async {
    final dir = baseDirectory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(dir.path + Platform.pathSeparator + 'hyp_reader_settings.json');
  }

  Future<ReaderSettings> load() async {
    final f = await _file;
    if (!await f.exists()) return const ReaderSettings();
    final data = jsonDecode(await f.readAsString());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('뷰어 설정을 읽을 수 없어.');
    }
    return ReaderSettings.fromJson(data);
  }

  Future<void> save(ReaderSettings settings) async {
    final f = await _file;
    await f.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }
}
