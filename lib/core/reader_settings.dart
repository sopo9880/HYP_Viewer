import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// When set to 'left', swipe/turn to the left to advance the book.
/// 'right' reverses the swipe direction for right-to-left reading.
class ReaderSettings {
  final String nextDirection; // left or right
  final bool twoPageSpread;
  final bool verticalScrolling;
  final int preloadPages;
  final bool autoCoverEnabled;
  final bool volumeKeyNavigation;
  final bool forceLandscapeForSpreads;
  final bool receiveAnnouncements;

  const ReaderSettings({
    this.nextDirection = 'left',
    this.twoPageSpread = false,
    this.verticalScrolling = false,
    this.preloadPages = 2,
    this.autoCoverEnabled = false,
    this.volumeKeyNavigation = false,
    this.forceLandscapeForSpreads = false,
    this.receiveAnnouncements = false,
  });

  bool get reverse => nextDirection == 'right';

  ReaderSettings copyWith({
    String? nextDirection,
    bool? twoPageSpread,
    bool? verticalScrolling,
    int? preloadPages,
    bool? autoCoverEnabled,
    bool? volumeKeyNavigation,
    bool? forceLandscapeForSpreads,
    bool? receiveAnnouncements,
  }) => ReaderSettings(
    nextDirection: nextDirection ?? this.nextDirection,
    twoPageSpread: twoPageSpread ?? this.twoPageSpread,
    verticalScrolling: verticalScrolling ?? this.verticalScrolling,
    preloadPages: preloadPages ?? this.preloadPages,
    autoCoverEnabled: autoCoverEnabled ?? this.autoCoverEnabled,
    volumeKeyNavigation: volumeKeyNavigation ?? this.volumeKeyNavigation,
    forceLandscapeForSpreads: forceLandscapeForSpreads ?? this.forceLandscapeForSpreads,
    receiveAnnouncements: receiveAnnouncements ?? this.receiveAnnouncements,
  );

  Map<String, Object> toJson() => {
    'nextDirection': nextDirection,
    'twoPageSpread': twoPageSpread,
    'verticalScrolling': verticalScrolling,
    'preloadPages': preloadPages,
    'autoCoverEnabled': autoCoverEnabled,
    'volumeKeyNavigation': volumeKeyNavigation,
    'forceLandscapeForSpreads': forceLandscapeForSpreads,
    'receiveAnnouncements': receiveAnnouncements,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> data) =>
      ReaderSettings(
        nextDirection: data['nextDirection'] == 'right' ? 'right' : 'left',
        twoPageSpread: data['twoPageSpread'] == true,
        verticalScrolling: data['verticalScrolling'] == true,
        autoCoverEnabled: data['autoCoverEnabled'] == true,
        volumeKeyNavigation: data['volumeKeyNavigation'] == true,
        forceLandscapeForSpreads: data['forceLandscapeForSpreads'] == true,
        receiveAnnouncements: data['receiveAnnouncements'] == true,
        preloadPages: data['preloadPages'] is num
            ? (data['preloadPages'] as num).toInt().clamp(0, 3).toInt()
            : 2,
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
