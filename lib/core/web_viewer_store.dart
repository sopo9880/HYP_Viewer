import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'gallery.dart';
import 'cover_store.dart';
import 'gallery_download_limits.dart';
import 'online_gallery.dart';
import 'web_page_capture.dart';
import 'web_series_capture.dart';
import 'web_series_library.dart';

class WebSiteBookmark {
  final String name, url;
  const WebSiteBookmark(this.name, this.url);
  Map<String, dynamic> toJson() => {'name': name, 'url': url};
  factory WebSiteBookmark.fromJson(Map<String, dynamic> raw) =>
      WebSiteBookmark((raw['name'] ?? '').toString(),
          (raw['url'] ?? '').toString());
}

/// Last opened tabs, stored separately from user-selected site bookmarks.
class WebVisitedPage {
  final String name, url;
  final DateTime? visitedAt;
  const WebVisitedPage(this.name, this.url, {this.visitedAt});
  Map<String, dynamic> toJson() => {
    'name': name, 'url': url,
    if (visitedAt != null) 'visitedAt': visitedAt!.toUtc().toIso8601String(),
  };
  factory WebVisitedPage.fromJson(Map<String, dynamic> raw) => WebVisitedPage(
    (raw['name'] ?? '').toString(), (raw['url'] ?? '').toString(),
    visitedAt: DateTime.tryParse((raw['visitedAt'] ?? '').toString()),
  );
}

class WebSavedWork {
  final String id, title, author, sourceUrl, publishedAt;
  final String? seriesUrl, episodeUrl;
  final int pages, currentPage;
  final DateTime savedAt;
  const WebSavedWork(this.id, this.title, this.author, this.sourceUrl,
      this.publishedAt, this.pages, this.currentPage, this.savedAt,
      {this.seriesUrl, this.episodeUrl});
  WebSavedWork withPage(int page) => WebSavedWork(id, title, author, sourceUrl,
      publishedAt, pages, page.clamp(1, pages).toInt(), savedAt,
      seriesUrl: seriesUrl, episodeUrl: episodeUrl);
  WebSavedWork renamed(String title) => WebSavedWork(id, title, author,
      sourceUrl, publishedAt, pages, currentPage, savedAt,
      seriesUrl: seriesUrl, episodeUrl: episodeUrl);
  WebSavedWork grouped(String parent, String episode) => WebSavedWork(
      id, title, author, sourceUrl, publishedAt, pages, currentPage,
      savedAt, seriesUrl: parent, episodeUrl: episode);
  /// Detach a CBZ from a deleted series while keeping the book and progress.
  WebSavedWork ungrouped() => WebSavedWork(
      id, title, author, sourceUrl, publishedAt, pages, currentPage,
      savedAt);
  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'author': author, 'sourceUrl': sourceUrl,
    'publishedAt': publishedAt, 'pages': pages, 'currentPage': currentPage,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'seriesUrl': seriesUrl, 'episodeUrl': episodeUrl,
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
      seriesUrl: data['seriesUrl'] is String ? data['seriesUrl'] as String : null,
      episodeUrl: data['episodeUrl'] is String ? data['episodeUrl'] as String : null,
    );
  }
}

/// Separate WEB library: never modifies existing HYP gallery files.
class WebViewerStore extends ChangeNotifier {
  final Directory? baseDirectory;
  WebViewerStore({this.baseDirectory});
  final sites = <WebSiteBookmark>[];
  final recentPages = <WebVisitedPage>[];
  WebVisitedPage? get lastTab => recentPages.isEmpty ? null : recentPages.first;
  final works = <WebSavedWork>[];
  final series = <WebSeriesRecord>[];
  final _pendingSeriesJobs = <String, List<String>>{};
  final _jobCompletions = <String, Completer<bool>>{};
  final _seriesFailedJobs = <String, String>{};
  final _coverFutures = <String, Future<Uint8List?>>{};
  Future<void> _coverTail = Future<void>.value();
  final pending = <String>[];
  final captures = <String, WebPageCapture>{};
  final progress = <String, int>{};
  final errors = <String, String>{};
  final failureTitles = <String, String>{};
  bool isReady = false, downloading = false, paused = false;
  bool autoSelectImages = true;
  // SERIES preferences are separate from the legacy HYP and WEB settings.
  bool seriesOldestFirst = true;
  bool seriesSelectUnsaved = true;
  bool seriesHideCompleted = false;
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

  /// Local thumbnails share the WEB tree, never the HYP cover folder.
  /// Legacy archives are decoded lazily one at a time to bound peak memory.
  Future<Uint8List?> coverFor(String workId) {
    if (!RegExp(r'^\d{1,12}$').hasMatch(workId)) {
      return Future<Uint8List?>.value(null);
    }
    return _coverFutures.putIfAbsent(workId, () async {
      final covers = CoverStore(baseDirectory: await root);
      try {
        final saved = await covers.read(workId);
        if (saved != null) return saved;
      } catch (_) {}
      final job = _coverTail.then((_) async {
        try {
          final saved = await covers.read(workId);
          if (saved != null) return saved;
          final archive = await (await galleries).read(workId);
          return await covers.save(workId, archive.pageBytes(0));
        } catch (_) {
          return null;
        }
      });
      _coverTail = job.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      return job;
    });
  }

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
        seriesOldestFirst = data['seriesOldestFirst'] != false;
        seriesSelectUnsaved = data['seriesSelectUnsaved'] != false;
        seriesHideCompleted = data['seriesHideCompleted'] == true;
        recentPages..clear()..addAll((data['recentPages'] as List? ?? [])
            .whereType<Map>()
            .map((v) => WebVisitedPage.fromJson(Map<String, dynamic>.from(v)))
            .where((v) => safeUrl(v.url) != null)
            .take(20));
        series..clear()..addAll((data['series'] as List? ?? [])
            .whereType<Map>()
            .map((v) => WebSeriesRecord.fromJson(Map<String, dynamic>.from(v)))
            .where((v) => safeUrl(v.url) != null));
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
        'seriesOldestFirst': seriesOldestFirst,
        'seriesSelectUnsaved': seriesSelectUnsaved,
        'seriesHideCompleted': seriesHideCompleted,
        'recentPages': recentPages.map((v) => v.toJson()).toList(),
        'series': series.map((v) => v.toJson()).toList(),
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
  Future<void> updateSite(
      String previousUrl, String name, String rawUrl) async {
    await load();
    final index = sites.indexWhere((v) => v.url == previousUrl);
    if (index < 0) throw StateError('Saved site not found');
    final uri = safeUrl(rawUrl);
    if (uri == null) throw const FormatException('Public HTTPS URL required');
    final nextUrl = uri.toString();
    if (sites.any((v) => v.url == nextUrl && v.url != previousUrl)) {
      throw StateError('Site URL is already saved');
    }
    sites[index] = WebSiteBookmark(
      name.trim().isEmpty ? uri.host : name.trim().substring(
        0, name.trim().length.clamp(0, 120).toInt()), nextUrl);
    await _save();
    _notify();
  }

  /// Save a browser navigation, not a new bookmark. Never persist
  /// query fields typically used for authentication or temporary signing.
  static Uri? safeHistoryUrl(String value) {
    // Splitting the raw URI removes the fragment completely. Creating an
    // empty fragment with Uri.replace(fragment: '') can retain a '#' marker.
    final uri = safeUrl(value.split('#').first);
    if (uri == null) return null;
    final filtered = <String, String>{};
    for (final entry in uri.queryParameters.entries) {
      if (RegExp(r'token|auth|secret|session|signature|'
          r'password|credential|nonce|key|code|jwt|sig',
          caseSensitive: false).hasMatch(entry.key)) continue;
      filtered[entry.key] = entry.value;
    }
    // Dart's Uri.replace(queryParameters: {}) serializes an empty query
    // as a trailing '?'. Reparse the canonical URL without that marker.
    final serialized = uri.replace(queryParameters: filtered).toString();
    final normalized = serialized.endsWith('?')
        ? serialized.substring(0, serialized.length - 1) : serialized;
    return safeUrl(normalized);
  }

  Future<void> recordVisitedPage(String rawUrl, String title) async {
    await load();
    final uri = safeHistoryUrl(rawUrl);
    if (uri == null) return;
    final url = uri.toString();
    final cleanTitle = title.trim().isEmpty ? uri.host :
        title.trim().substring(0, title.trim().length.clamp(0, 120).toInt());
    if (recentPages.isNotEmpty &&
        recentPages.first.url == url &&
        recentPages.first.name == cleanTitle) return;
    recentPages.removeWhere((v) => v.url == url);
    recentPages.insert(0, WebVisitedPage(cleanTitle, url,
        visitedAt: DateTime.now().toUtc()));
    if (recentPages.length > 200) {
      recentPages.removeRange(200, recentPages.length);
    }
    await _save();
    _notify();
  }

  Future<void> clearRecentPages() async {
    recentPages.clear();
    await _save();
    _notify();
  }

  Future<void> removeRecentPage(String url) async {
    await load();
    recentPages.removeWhere((page) => page.url == url);
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
  /// Failure dismissal never removes downloaded work data or any CBZ.
  void clearFailedDownload(String id) {
    failureTitles.remove(id);
    _seriesFailedJobs.remove(id);
    if (errors.remove(id) != null) _notify();
  }

  void clearAllFailedDownloads() {
    if (errors.isEmpty) return;
    errors.clear();
    failureTitles.clear();
    _seriesFailedJobs.clear();
    _notify();
  }

  WebSeriesRecord? getSeries(String sourceUrl) {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null) return null;
    final key = uri.replace(query: '', fragment: '').toString();
    for (final entry in series) {
      final existing = Uri.tryParse(entry.url);
      if (existing?.replace(query: '', fragment: '').toString() == key) {
        return entry;
      }
    }
    return null;
  }

  /// Rename only this group, preserving original chapter URLs and CBZ data.
  Future<void> renameSeries(String url, String title) async {
    await load();
    final group = getSeries(url);
    final value = title.trim();
    if (group == null || value.isEmpty) return;
    group.title = value;
    group.titleCustomized = true;
    await _save();
    _notify();
  }

  bool _seriesTransferActive(WebSeriesRecord group) =>
    group.episodes.any((episode) => episode.state == 'downloading') ||
    _pendingSeriesJobs.values.any((pair) => pair.first == group.url);

  /// Remove a whole group; by default its CBZs remain in WEB as ungrouped works.
  Future<void> removeSeries(String url, {bool deleteFiles = false}) async {
    await load();
    final group = getSeries(url);
    if (group == null) return;
    if (_seriesTransferActive(group)) {
      throw StateError('먼저 진행 중인 시리즈 다운로드를 중지해줘.');
    }
    final ids = group.episodes.map((e) => e.workId)
        .whereType<String>().toSet();
    if (deleteFiles) {
      for (final id in ids) {
        await removeWork(id);
      }
    } else {
      for (var i = 0; i < works.length; i++) {
        if (works[i].seriesUrl == group.url) {
          works[i] = works[i].ungrouped();
        }
      }
    }
    series.remove(group);
    await _save();
    _notify();
  }

  /// Remove a row from a series without touching other chapters.
  Future<void> removeSeriesEpisode(String url, String chapterUrl,
      {bool deleteFile = false}) async {
    await load();
    final group = getSeries(url);
    final episode = group?.episode(chapterUrl);
    if (group == null || episode == null) return;
    if (episode.state == 'downloading' ||
        _pendingSeriesJobs.values.any((pair) =>
            pair.first == group.url && pair.last == episode.url)) {
      throw StateError('다운로드 중인 회차는 중지한 다음 삭제해줘.');
    }
    final id = episode.workId;
    if (id != null && deleteFile) {
      await removeWork(id);
    } else if (id != null) {
      for (var i = 0; i < works.length; i++) {
        if (works[i].id == id) works[i] = works[i].ungrouped();
      }
    }
    group.episodes.remove(episode);
    await _save();
    _notify();
  }

  Future<int> saveSeries(WebSeriesCapture capture) async {
    await load();
    final existing = getSeries(capture.url.toString());
    final added = existing == null
        ? capture.episodes.length : existing.merge(capture);
    if (existing == null) series.insert(0, WebSeriesRecord.fromCapture(capture));
    final group = getSeries(capture.url.toString())!;
    // Reuse single-episode CBZs saved before series support was introduced.
    for (final episode in group.episodes) {
      if (episode.workId != null) continue;
      final uri = Uri.tryParse(episode.url);
      if (uri == null) continue;
      final id = findExisting(uri);
      if (id == null) continue;
      final index = works.indexWhere((w) => w.id == id);
      if (index < 0) continue;
      episode.workId = id;
      episode.state = 'saved';
      episode.error = null;
      if (works[index].seriesUrl == null) {
        works[index] = works[index].grouped(group.url, episode.url);
      }
    }
    await _save();
    _notify();
    return added;
  }

  /// Persist only selected source links, never short-lived image addresses.
  Future<int> queueSeriesEpisodes(
      String sourceUrl, Iterable<String> selectedUrls) async {
    await load();
    final entry = getSeries(sourceUrl);
    if (entry == null) throw StateError('Series is not saved');
    final selected = selectedUrls.toSet();
    var added = 0;
    for (final episode in entry.episodes) {
      if (!selected.contains(episode.url) || episode.state == 'saved' ||
          episode.state == 'downloading' || episode.state == 'queued') continue;
      episode.state = 'queued';
      episode.error = null;
      added++;
    }
    if (added > 0) {
      await _save();
      _notify();
    }
    return added;
  }

  Future<void> markEpisodeNeedsAttention(
      String seriesUrl, String episodeUrl, String reason) async {
    final episode = getSeries(seriesUrl)?.episode(episodeUrl);
    if (episode == null || episode.state == 'saved') return;
    episode.state = 'needs_browser';
    episode.error = reason.length > 500 ? reason.substring(0, 500) : reason;
    await _save();
    _notify();
  }

  Future<bool> waitForSeriesJob(String id) async {
    final completion = _jobCompletions[id];
    if (completion == null) return false;
    final result = await completion.future;
    _jobCompletions.remove(id);
    return result;
  }

  bool isSeriesDownload(String id) => _pendingSeriesJobs.containsKey(id);
  bool isSeriesFailure(String id) => _seriesFailedJobs.containsKey(id);
  String? seriesForDownload(String id) => _pendingSeriesJobs[id]?.first;

  WebSeriesEpisodeRecord? nextSeriesEpisode(String sourceUrl) {
    final group = getSeries(sourceUrl);
    if (group == null) return null;
    final entries = seriesOldestFirst
        ? group.episodes.reversed : group.episodes;
    for (final item in entries) {
      if (item.state == 'queued') return item;
    }
    return null;
  }

  Future<void> setSeriesOldestFirst(bool enabled) async {
    await load();
    seriesOldestFirst = enabled;
    await _save();
    _notify();
  }

  Future<void> setSeriesSelectUnsaved(bool enabled) async {
    await load();
    seriesSelectUnsaved = enabled;
    await _save();
    _notify();
  }

  Future<void> setSeriesHideCompleted(bool enabled) async {
    await load();
    seriesHideCompleted = enabled;
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
      {String? title, String? seriesUrl, String? episodeUrl}) async {
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
      author: capture.author, publishedAt: capture.publishedAt,
      expectedImages: capture.expectedImages, images: images);
    if (seriesUrl != null && episodeUrl != null) {
      final episode = getSeries(seriesUrl)?.episode(episodeUrl);
      if (episode == null) throw StateError('Unknown series episode');
      episode.state = 'downloading';
      episode.error = null;
      _pendingSeriesJobs[id] = [seriesUrl, episodeUrl];
      _jobCompletions[id] = Completer<bool>();
      await _save();
    }
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
        final parent = _pendingSeriesJobs[id];
        works.insert(0, WebSavedWork(id, capture.title, capture.author,
          capture.sourceUrl.toString(), capture.publishedAt,
          archive.pageCount, 1, DateTime.now(),
          seriesUrl: parent?.first, episodeUrl: parent?.last));
        if (parent != null) {
          final episode = getSeries(parent.first)?.episode(parent.last);
          episode?.state = 'saved';
          episode?.workId = id;
          episode?.error = null;
        }
        await _save();
        errors.remove(id); failureTitles.remove(id);
        _seriesFailedJobs.remove(id);
        final completion = _jobCompletions[id];
        if (completion != null && !completion.isCompleted) {
          completion.complete(true);
        }
      } catch (error) {
        errors[id] = error.toString();
        failureTitles[id] = capture.title;
        final parent = _pendingSeriesJobs[id];
        if (parent != null) {
          final episode = getSeries(parent.first)?.episode(parent.last);
          episode?.state = 'failed';
          episode?.error = 'Download failed. See the SERIES download log.';
          _seriesFailedJobs[id] = parent.first;
          try { await _save(); } catch (_) {}
        }
        final completion = _jobCompletions[id];
        if (completion != null && !completion.isCompleted) {
          completion.complete(false);
        }
      }
      finally {
        pending.removeAt(0); captures.remove(id);
        _pendingSeriesJobs.remove(id);
        activeId = null; _notify();
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
        final data = await _loadImageWithRetry(
            client, source.images[i], source.sourceUrl);
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
      try {
        await CoverStore(baseDirectory: await root)
            .save(id, result.pageBytes(0));
      } catch (_) {
        // Preview failures must not invalidate successfully stored CBZs.
      }
      _coverFutures.remove(id);
      await folder.delete(recursive: true);
      return result;
    } finally {
      if (opened) { try { await encoder.close(); } catch (_) {} }
      client.close();
      // Avoid accumulating incomplete archives after a failed transfer.
      try {
        if (await folder.exists()) await folder.delete(recursive: true);
      } catch (_) {}
    }
  }
  /// Retry only transient transport failures; HTTP access denials and
  /// invalid/non-image responses remain hard failures.
  Future<Uint8List> _loadImageWithRetry(
      http.Client client, WebPageImage page, Uri sourceUrl) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_cancelRequested || _disposed) throw StateError('Cancelled');
      try {
        return await BoundedWebImages.load(
          client, page.url,
          headers: page.noReferrer ? null :
              {'Referer': sourceUrl.toString()},
          maxBytes: GalleryDownloadLimits.defaultImageMiB *
              GalleryDownloadLimits.mib,
        );
      } on http.ClientException {
        if (attempt >= 2) rethrow;
      } on SocketException {
        if (attempt >= 2) rethrow;
      } on TimeoutException {
        if (attempt >= 2) rethrow;
      }
      await Future<void>.delayed(
          Duration(milliseconds: 400 * (attempt + 1)));
    }
    throw StateError('Image transport retries exhausted');
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
    _coverFutures.remove(id);
    try {
      await CoverStore(baseDirectory: await root).deleteAllForWork(id);
    } catch (_) {
      // Preview cleanup is best-effort, independent of saved metadata.
    }
    works.removeWhere((v) => v.id == id);
    for (final group in series) {
      for (final episode in group.episodes) {
        if (episode.workId == id) {
          episode.workId = null;
          episode.state = 'available';
          episode.error = null;
        }
      }
    }
    await _save(); _notify();
  }
  @override void dispose() {
    _cancelRequested = true; _disposed = true; super.dispose();
  }
}
