import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// When set to 'left', swipe/turn to the left to advance the book.
/// 'right' reverses the swipe direction for right-to-left reading.
class ReaderSettings {
  final String nextDirection; // left or right
  final bool twoPageSpread;
  /// Hide chrome at entry; tap center or press Space to reveal.
  final bool hideReaderUiOnOpen;
  /// ON: reaching the last page does not mark complete; explicit next asks.
  final bool confirmCompleteOnNext;
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
  final bool completedHidden;
  final bool analyticsEnabled;
  final List<String> expandedSettings;
  final bool autoCoverEnabled;
  final bool volumeKeyNavigation;
  /// Android volume long-press repeat: 200/400/700 milliseconds.
  final int volumeHoldIntervalMs;
  final bool forceLandscapeForSpreads;
  final bool receiveAnnouncements;
  final bool openAfterSave;
  final String languageCode; // ko, en, ja
  final String heroArtworkSource; // default, custom, random
  final bool startupUpdatePrompt;
  final String snoozedUpdateVersion;
  final String snoozedUpdateUntil;
  final String preferredEditionLanguage; // auto, recent, korean, japanese, english, chinese

  const ReaderSettings({
    this.nextDirection = 'left',
    this.twoPageSpread = false,
    this.hideReaderUiOnOpen = true,
    this.confirmCompleteOnNext = true,
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
    this.completedHidden = false,
    this.analyticsEnabled = true,
    this.expandedSettings = const [],
    this.autoCoverEnabled = false,
    this.volumeKeyNavigation = false,
    this.volumeHoldIntervalMs = 400,
    this.forceLandscapeForSpreads = false,
    this.receiveAnnouncements = false,
    this.openAfterSave = false,
    this.languageCode = 'ko',
    this.heroArtworkSource = 'custom',
    this.startupUpdatePrompt = true,
    this.snoozedUpdateVersion = '',
    this.snoozedUpdateUntil = '',
    this.preferredEditionLanguage = 'auto',
  });

  bool get reverse => nextDirection == 'right';

  ReaderSettings copyWith({
    String? nextDirection,
    bool? twoPageSpread,
    bool? hideReaderUiOnOpen,
    bool? confirmCompleteOnNext,
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
    bool? completedHidden,
    bool? analyticsEnabled,
    List<String>? expandedSettings,
    bool? autoCoverEnabled,
    bool? volumeKeyNavigation,
    int? volumeHoldIntervalMs,
    bool? forceLandscapeForSpreads,
    bool? receiveAnnouncements,
    bool? openAfterSave,
    String? languageCode,
    String? heroArtworkSource,
    bool? startupUpdatePrompt,
    String? snoozedUpdateVersion,
    String? snoozedUpdateUntil,
    String? preferredEditionLanguage,
  }) => ReaderSettings(
    nextDirection: nextDirection ?? this.nextDirection,
    twoPageSpread: twoPageSpread ?? this.twoPageSpread,
    hideReaderUiOnOpen: hideReaderUiOnOpen ?? this.hideReaderUiOnOpen,
    confirmCompleteOnNext: confirmCompleteOnNext ?? this.confirmCompleteOnNext,
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
    completedHidden: completedHidden ?? this.completedHidden,
    analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
    expandedSettings: expandedSettings ?? this.expandedSettings,
    autoCoverEnabled: autoCoverEnabled ?? this.autoCoverEnabled,
    volumeKeyNavigation: volumeKeyNavigation ?? this.volumeKeyNavigation,
    volumeHoldIntervalMs: volumeHoldIntervalMs ?? this.volumeHoldIntervalMs,
    forceLandscapeForSpreads: forceLandscapeForSpreads ?? this.forceLandscapeForSpreads,
    receiveAnnouncements: receiveAnnouncements ?? this.receiveAnnouncements,
    openAfterSave: openAfterSave ?? this.openAfterSave,
    languageCode: languageCode ?? this.languageCode,
    heroArtworkSource: heroArtworkSource ?? this.heroArtworkSource,
    startupUpdatePrompt: startupUpdatePrompt ?? this.startupUpdatePrompt,
    snoozedUpdateVersion: snoozedUpdateVersion ?? this.snoozedUpdateVersion,
    snoozedUpdateUntil: snoozedUpdateUntil ?? this.snoozedUpdateUntil,
    preferredEditionLanguage: preferredEditionLanguage ?? this.preferredEditionLanguage,
  );

  Map<String, Object> toJson() => {
    'nextDirection': nextDirection,
    'twoPageSpread': twoPageSpread,
    'hideReaderUiOnOpen': hideReaderUiOnOpen,
    'confirmCompleteOnNext': confirmCompleteOnNext,
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
    'completedHidden': completedHidden,
    'analyticsEnabled': analyticsEnabled,
    'expandedSettings': expandedSettings,
    'autoCoverEnabled': autoCoverEnabled,
    'volumeKeyNavigation': volumeKeyNavigation,
    'volumeHoldIntervalMs': volumeHoldIntervalMs,
    'forceLandscapeForSpreads': forceLandscapeForSpreads,
    'receiveAnnouncements': receiveAnnouncements,
    'openAfterSave': openAfterSave,
    'languageCode': languageCode,
    'heroArtworkSource': heroArtworkSource,
    'startupUpdatePrompt': startupUpdatePrompt,
    'snoozedUpdateVersion': snoozedUpdateVersion,
    'snoozedUpdateUntil': snoozedUpdateUntil,
    'preferredEditionLanguage': preferredEditionLanguage,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> data) =>
      ReaderSettings(
        nextDirection: data['nextDirection'] == 'right' ? 'right' : 'left',
        twoPageSpread: data['twoPageSpread'] == true,
        hideReaderUiOnOpen: data['hideReaderUiOnOpen'] != false,
        confirmCompleteOnNext: data['confirmCompleteOnNext'] != false,
        verticalScrolling: data['verticalScrolling'] == true,
        showDownloadAction: data['showDownloadAction'] != false,
        showCoverAction: data['showCoverAction'] != false,
        showPageControlsAction: data['showPageControlsAction'] != false,
        showWebReaderAction: data['showWebReaderAction'] != false,
        showOrientationAction: data['showOrientationAction'] != false,
        startupUpdatePrompt: data['startupUpdatePrompt'] != false,
        snoozedUpdateVersion: data['snoozedUpdateVersion'] is String && (data['snoozedUpdateVersion'] as String).length <= 40 ? data['snoozedUpdateVersion'] as String : '',
        snoozedUpdateUntil: DateTime.tryParse(data['snoozedUpdateUntil'] is String ? data['snoozedUpdateUntil'] as String : '')?.toUtc().toIso8601String() ?? '',
        preferredEditionLanguage: const {'auto', 'recent', 'korean', 'japanese', 'english', 'chinese'}.contains(data['preferredEditionLanguage']) ? data['preferredEditionLanguage'] as String : 'auto',
        autoCoverEnabled: data['autoCoverEnabled'] == true,
        volumeKeyNavigation: data['volumeKeyNavigation'] == true,
        volumeHoldIntervalMs: data['volumeHoldIntervalMs'] is int &&
            const {200, 400, 700}.contains(data['volumeHoldIntervalMs'])
            ? (data['volumeHoldIntervalMs'] as int) : 400,
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
                'mostRead', 'title', 'number', 'chapter'}
                .contains(data['librarySort'])
            ? data['librarySort'] as String : 'newest',
        librarySortDescending: data['librarySortDescending'] == true,
        recentCollapsed: data['recentCollapsed'] == true,
        completedHidden: data['completedHidden'] == true,
        analyticsEnabled: data['analyticsEnabled'] != false,
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
