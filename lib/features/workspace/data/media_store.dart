import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What kind of media an entry holds.
enum MediaType { image, gif, video }

/// One media item belonging to a story and a chapter.
class MediaEntry {
  MediaEntry({
    required this.id,
    required this.storyId,
    required this.chapter,
    required this.source,
    required this.type,
    this.caption = '',
    this.saved = false,
    required this.createdAt,
  });

  final String id;
  final String storyId;
  final int chapter;

  /// Either an `http(s)://` URL or a `file://` path inside app storage.
  final String source;
  final MediaType type;
  String caption;
  bool saved;
  final int createdAt;

  bool get isUrl => source.startsWith('http');
  bool get isFile => source.startsWith('file://');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'storyId': storyId,
        'chapter': chapter,
        'source': source,
        'type': type.name,
        'caption': caption,
        'saved': saved,
        'createdAt': createdAt,
      };

  static MediaEntry fromJson(Map<String, dynamic> j) => MediaEntry(
        id: (j['id'] ?? '') as String,
        storyId: (j['storyId'] ?? '') as String,
        chapter: (j['chapter'] as num?)?.toInt() ?? 1,
        source: (j['source'] ?? '') as String,
        type: MediaType.values.firstWhere(
          (MediaType t) => t.name == j['type'],
          orElse: () => MediaType.image,
        ),
        caption: (j['caption'] ?? '') as String,
        saved: (j['saved'] ?? false) as bool,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// Local media table.
///
/// Every story's media lives in one JSON document in shared_preferences.
/// Device images are **copied into app storage** first, so the entry survives
/// the gallery file being moved or deleted. URLs are stored as URLs and load
/// live from the network.
class MediaStore {
  MediaStore._();
  static final MediaStore instance = MediaStore._();

  static const String _key = 'rino.media.v1';

  List<MediaEntry> _all = <MediaEntry>[];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
        _all = list
            .map((dynamic e) => MediaEntry.fromJson(Map<String, dynamic>.from(e as Map<dynamic, dynamic>)))
            .toList();
      } catch (_) {
        _all = <MediaEntry>[];
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_all.map((MediaEntry e) => e.toJson()).toList()));
  }

  /// All media for a story, newest first.
  List<MediaEntry> forStory(String storyId) {
    final List<MediaEntry> list =
        _all.where((MediaEntry e) => e.storyId == storyId).toList()
          ..sort((MediaEntry a, MediaEntry b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<MediaEntry> forChapter(String storyId, int chapter) =>
      forStory(storyId).where((MediaEntry e) => e.chapter == chapter).toList();

  int chapterCount(String storyId) {
    final Set<int> chapters =
        _all.where((MediaEntry e) => e.storyId == storyId).map((MediaEntry e) => e.chapter).toSet();
    return chapters.isEmpty ? 0 : chapters.reduce((int a, int b) => a > b ? a : b);
  }

  /// Guess the media type from a URL or path.
  static MediaType typeFromSource(String s) {
    final String lower = s.toLowerCase();
    if (RegExp(r'\.(mp4|webm|mov|m4v|ogv)(\?|#|$)').hasMatch(lower)) return MediaType.video;
    if (RegExp(r'\.gif(\?|#|$)').hasMatch(lower)) return MediaType.gif;
    return MediaType.image;
  }

  /// Add a URL entry. Loads live from the internet.
  Future<MediaEntry> addUrl({
    required String storyId,
    required int chapter,
    required String url,
    String caption = '',
  }) async {
    await load();
    final MediaEntry e = MediaEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      storyId: storyId,
      chapter: chapter,
      source: url,
      type: typeFromSource(url),
      caption: caption,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _all.add(e);
    await _persist();
    return e;
  }

  /// Copy a picked device file into app storage, then record it.
  Future<MediaEntry> addFile({
    required String storyId,
    required int chapter,
    required String sourcePath,
    String caption = '',
  }) async {
    await load();
    final Directory dir = await getApplicationDocumentsDirectory();
    final Directory mediaDir = Directory('${dir.path}/media/$storyId');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    final String name = sourcePath.split(Platform.pathSeparator).last;
    final String target = '${mediaDir.path}/${DateTime.now().millisecondsSinceEpoch}_$name';
    await File(sourcePath).copy(target);

    final MediaEntry e = MediaEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      storyId: storyId,
      chapter: chapter,
      source: 'file://$target',
      type: typeFromSource(target),
      caption: caption,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _all.add(e);
    await _persist();
    return e;
  }

  Future<void> toggleSaved(MediaEntry e) async {
    await load();
    for (final MediaEntry x in _all) {
      if (x.id == e.id) {
        x.saved = !x.saved;
        e.saved = x.saved;
      }
    }
    await _persist();
  }

  Future<void> setCaption(MediaEntry e, String caption) async {
    await load();
    for (final MediaEntry x in _all) {
      if (x.id == e.id) {
        x.caption = caption;
        e.caption = caption;
      }
    }
    await _persist();
  }

  Future<void> remove(MediaEntry e) async {
    await load();
    _all.removeWhere((MediaEntry x) => x.id == e.id);
    if (e.isFile) {
      try {
        await File(e.source.substring('file://'.length)).delete();
      } catch (_) {}
    }
    await _persist();
  }
}
