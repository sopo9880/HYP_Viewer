import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// When set to 'left', swipe/turn to the left to advance the book.
/// 'right' reverses the swipe direction for right-to-left reading.
class ReaderSettings {
  final String nextDirection; // left or right
  final bool twoPageSpread;
  final int preloadPages;

  const ReaderSettings({
    this.nextDirection = 'left',
    this.twoPageSpread = false,
    this.preloadPages = 2,
  });

  bool get reverse => nextDirection == 'right';

  ReaderSettings copyWith({
    String? nextDirection,
    bool? twoPageSpread,
    int? preloadPages,
  }) => ReaderSettings(
    nextDirection: nextDirection ?? this.nextDirection,
    twoPageSpread: twoPageSpread ?? this.twoPageSpread,
    preloadPages: preloadPages ?? this.preloadPages,
  );

  Map<String, Object> toJson() => {
    'nextDirection': nextDirection,
    'twoPageSpread': twoPageSpread,
    'preloadPages': preloadPages,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> data) =>
      ReaderSettings(
        nextDirection: data['nextDirection'] == 'right' ? 'right' : 'left',
        twoPageSpread: data['twoPageSpread'] == true,
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
