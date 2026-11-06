import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'gallery.dart';
import 'gallery_download_limits.dart';
import 'online_gallery.dart';
import 'web_page_capture.dart';

class WebSiteBookmark {
  final String name, url;
  const WebSiteBookmark(this.name, this.url);
  Map<String, dynamic> toJson() => {'name': name, 'url': url};
  factory WebSiteBookmark.fromJson(Map<String, dynamic> raw) =>
      WebSiteBookmark((raw['name'] ?? '').toString(),
          (raw['url'] ?? '').toString());
}

class WebSavedWork {
  final String id, title, author, sourceUrl, publishedAt;
  final int pages, currentPage;
  final DateTime savedAt;
  const WebSavedWork(this.id, this.title, this.author, this.sourceUrl,
      this.publishedAt, this.pages, this.currentPage, this.savedAt);
  WebSavedWork withPage(int page) => WebSavedWork(id, title, author, sourceUrl,
      publishedAt, pages, page.clamp(1, pages).toInt(), savedAt);
  WebSavedWork renamed(String title) => WebSavedWork(id, title, author,
      sourceUrl, publishedAt, pages, currentPage, savedAt);
  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'author': author, 'sourceUrl': sourceUrl,
    'publishedAt': publishedAt, 'pages': pages, 'currentPage': currentPage,
    'savedAt': savedAt.toUtc().toIso8601String(),
  };
  factory WebSavedWork.fromJson(Map<String, dynamic> data) {
    final count = (data['pages'] is int ? data['pages'] as int : 1)
        .clamp(1, GalleryArchive.maxPages).toInt();
    return WebSavedWork(
      (data['id'] ?? '').toString(), (data['title'] ?? '').toString(),
      (data['author'] ?? '').toString(), (data['sourceUrl'] ?? '').toString(),
      (data['publishedAt'] ?? '').toString(), count,
      (data['currentPage'] is int ? data['currentPage'] as int : 1)
          .clamp(1, count).toInt(),
      DateTime.tryParse((data['savedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Separate WEB library: never modifies existing HYP gallery files.
class WebViewerStore extends ChangeNotifier {
  final Directory? baseDirectory;
  WebViewerStore({this.baseDirectory});
  final sites = <WebSiteBookmark>[];
  final works = <WebSavedWork>[];
  final pending = <String>[];
  final captures = <String, WebPageCapture>{};
  final progress = <String, int>{};
  final errors = <String, String>{};
  bool isReady = false, downloading = false, paused = false;
  bool autoSelectImages = true;
  String? activeId;
  bool _disposed = false, _cancelRequested = false;
  Future<void>? _loading;
  Future<void> _lastWrite = Future<void>.value();
  int _sequence = 0;
  void _notify() { if (!_disposed) notifyListeners(); }

  Future<Directory> get root async {
    final base = baseDirectory ?? await getApplicationSupportDirectory();
    final dir = Directory(base.path + Platform.pathSeparator + 'web_viewer');
    await dir.create(recursive: true);
    return dir;
  }
  Future<GalleryStore> get galleries async =>
      GalleryStore(baseDirectory: await root);
  Future<File> get _file async => File(
      (await root).path + Platform.pathSeparator + 'web_library.json');

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final file = await _file;
    final backup = File(file.path + '.previous');
    for (final candidate in [file, backup]) {
      if (!await candidate.exists()) continue;
      try {
        final data = jsonDecode(await candidate.readAsString());
        if (data is! Map || data['schemaVersion'] != 1) {
          throw const FormatException('Invalid WEB library');
        }
        sites..clear()..addAll((data['sites'] as List? ?? [])
            .whereType<Map>().map((v) =>
                WebSiteBookmark.fromJson(Map<String, dynamic>.from(v)))
            .where((v) => safeUrl(v.url) != null));
        autoSelectImages = data['autoSelectImages'] != false;
        works..clear()..addAll((data['works'] as List? ?? [])
            .whereType<Map>().map((v) =>
                WebSavedWork.fromJson(Map<String, dynamic>.from(v)))
            .where((v) => RegExp(r'^\d{1,12}$').hasMatch(v.id)));
        break;
      } catch (_) {
        if (candidate.path == backup.path || !await backup.exists()) rethrow;
      }
    }
    isReady = true;
    _notify();
  }
  static Uri? safeUrl(String raw) {
    final url = Uri.tryParse(raw.trim());
    if (url == null || raw.length > 2048 ||
        !OnlineSourcePolicy.isHttpsPublic(url)) return null;
    return url;
  }
  Future<void> _save() {
    final next = _lastWrite.then((_) async {
      final file = await _file;
      final previous = File(file.path + '.previous');
      final temp = File(file.path + '.tmp');
      await temp.writeAsString(jsonEncode({
        'schemaVersion': 1, 'sites': sites.map((v) => v.toJson()).toList(),
        'works': works.map((v) => v.toJson()).toList(),
        'autoSelectImages': autoSelectImages,
      }), flush: true);
      if (await file.exists()) {
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
      }
      try { await temp.rename(file.path); }
      catch (_) {
        if (!await file.exists() && await previous.exists()) {
          await previous.rename(file.path);
        }
        rethrow;
      }
    });
    _lastWrite = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
  Future<void> addSite(String name, String rawUrl) async {
    await load();
    final uri = safeUrl(rawUrl);
    if (uri == null) throw const FormatException('Public HTTPS URL required');
    if (sites.any((v) => v.url == uri.toString())) return;
    sites.add(WebSiteBookmark(
      name.trim().isEmpty ? uri.host : name.trim(), uri.toString()));
    await _save();
    _notify();
  }
  Future<void> setAutoSelectImages(bool enabled) async {
    autoSelectImages = enabled;
    await _save();
    _notify();
  }
  Future<void> removeSite(String url) async {
    sites.removeWhere((v) => v.url == url);
    await _save();
    _notify();
  }
  String? findExisting(Uri url) {
    final identity = url.replace(query: '', fragment: '').toString();
    for (final work in works) {
      if (Uri.tryParse(work.sourceUrl)
          ?.replace(query: '', fragment: '').toString() == identity) {
        return work.id;
      }
    }
    return null;
  }
  String _newId() {
    for (var i = 0; i < 1000; i++) {
      final id = (100000000000 +
          (DateTime.now().microsecondsSinceEpoch + _sequence++ + i) %
              900000000000).toString();
      if (!works.any((v) => v.id == id) && !captures.containsKey(id)) return id;
    }
    throw StateError('WEB gallery ID exhausted');
  }
  Future<String> enqueue(WebPageCapture capture, List<int> selected,
      {String? title}) async {
    await load();
    if (selected.isEmpty) throw const FormatException('No selected images');
    final existing = findExisting(capture.sourceUrl);
    if (existing != null) throw StateError('Already saved: ' + existing);
    final images = <WebPageImage>[];
    for (final i in selected.toSet().toList()..sort()) {
      if (i < 0 || i >= capture.images.length) throw RangeError.index(i, capture.images);
      images.add(capture.images[i]);
    }
    final id = _newId();
    captures[id] = WebPageCapture(
      sourceUrl: capture.sourceUrl, title: title ?? capture.title,
      author: capture.author, publishedAt: capture.publishedAt, images: images);
    pending.add(id);
    progress[id] = 0;
    _notify();
    unawaited(_drain());
    return id;
  }
  Future<void> _drain() async {
    if (downloading) return;
    downloading = true;
    _notify();
    while (pending.isNotEmpty && !_disposed) {
      final id = pending.first;
      final capture = captures[id]!;
      activeId = id; _cancelRequested = false; _notify();
      try {
        final archive = await _download(id, capture);
        works.insert(0, WebSavedWork(id, capture.title, capture.author,
          capture.sourceUrl.toString(), capture.publishedAt,
          archive.pageCount, 1, DateTime.now()));
        await _save(); errors.remove(id);
      } catch (error) { errors[id] = error.toString(); }
      finally {
        pending.removeAt(0); captures.remove(id); activeId = null; _notify();
      }
    }
    downloading = false;
    _notify();
  }
  Future<GalleryArchive> _download(String id, WebPageCapture source) async {
    final folder = Directory((await root).path + Platform.pathSeparator +
        'staging' + Platform.pathSeparator + id);
    await folder.create(recursive: true);
    final zip = File(folder.path + Platform.pathSeparator + 'archive.cbz');
    final client = http.Client();
    final encoder = ZipFileEncoder();
    var opened = false, total = 0;
    try {
      if (await zip.exists()) await zip.delete();
      encoder.create(zip.path, level: ZipFileEncoder.store);
      opened = true;
      for (var i = 0; i < source.images.length; i++) {
        while (paused && !_cancelRequested && !_disposed) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (_cancelRequested || _disposed) throw StateError('Cancelled');
        final data = await BoundedWebImages.load(client,
            source.images[i].url,
            headers: {'Referer': source.sourceUrl.toString()},
            maxBytes: GalleryDownloadLimits.defaultImageMiB *
                GalleryDownloadLimits.mib);
        total += data.length;
        if (total > GalleryDownloadLimits.hardTotalMiB *
                GalleryDownloadLimits.mib) {
          throw const FormatException('Gallery size limit');
        }
        final ext = imageExtension(data);
        if (ext == null) throw const FormatException('Invalid image bytes');
        final name = 'page_' + (i + 1).toString().padLeft(5, '0') + '.' + ext;
        final file = File(folder.path + Platform.pathSeparator + name);
        await file.writeAsBytes(data, flush: true);
        await encoder.addFile(file, name, ZipFileEncoder.store);
        progress[id] = i + 1; _notify();
      }
      await encoder.close(); opened = false;
      final gallery = await galleries;
      final result = await gallery.importFile(id, zip.path);
      await folder.delete(recursive: true);
      return result;
    } finally {
      if (opened) { try { await encoder.close(); } catch (_) {} }
      client.close();
    }
  }
  static String? imageExtension(Uint8List data) {
    if (data.length < 12) return null;
    if (data[0] == 255 && data[1] == 216 && data[2] == 255) return 'jpg';
    if (data[0] == 137 && data[1] == 80 &&
        data[2] == 78 && data[3] == 71) return 'png';
    if (ascii.decode(data.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(data.sublist(8, 12), allowInvalid: true) == 'WEBP') return 'webp';
    if (ascii.decode(data.sublist(0, 3), allowInvalid: true) == 'GIF') return 'gif';
    if (data[0] == 66 && data[1] == 77) return 'bmp';
    return null;
  }
  void togglePause() { paused = !paused; _notify(); }
  void cancelCurrent() { _cancelRequested = true; paused = false; _notify(); }
  Future<void> updatePage(String id, int page) async {
    final index = works.indexWhere((v) => v.id == id);
    if (index < 0) return;
    works[index] = works[index].withPage(page);
    await _save(); _notify();
  }
  Future<void> renameWork(String id, String title) async {
    final index = works.indexWhere((v) => v.id == id);
    if (index < 0 || title.trim().isEmpty) return;
    works[index] = works[index].renamed(title.trim());
    await _save(); _notify();
  }
  Future<void> removeWork(String id) async {
    final gallery = await galleries;
    await gallery.delete(id);
    works.removeWhere((v) => v.id == id);
    await _save(); _notify();
  }
  @override void dispose() {
    _cancelRequested = true; _disposed = true; super.dispose();
  }
}
