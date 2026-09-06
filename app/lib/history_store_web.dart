import 'dart:typed_data';

import 'history_entry.dart';
import 'history_thumbnail.dart';

/// Web implementation: keeps history entries and image bytes in memory for
/// the lifetime of the page — not persisted across reloads or restarts.
/// Not used directly, see `history.dart`'s conditional export.
///
/// There's no native-style file-backed manifest here for the same reason
/// `db_manager_web.dart` has no persistent database cache: `path_provider`
/// (which the native `history_store_io.dart` uses for its documents
/// directory) has no web platform implementation at all, so calling it on
/// web throws `MissingPluginException` rather than silently no-opping —
/// confirmed live, driving the actual deployed PWA (see
/// `docs/web-build.md`). A real persistent web store (IndexedDB) is
/// possible later; re-solving after a reload is the honest, working
/// starting point instead of a broken persistent one.
class HistoryStore {
  static final List<HistoryEntry> _entries = [];
  static final Map<String, Uint8List> _thumbnails = {};
  static final Map<String, Uint8List> _fullImages = {};

  static Future<List<HistoryEntry>> load() async => List.unmodifiable(_entries);

  static Future<List<HistoryEntry>> add({
    required Uint8List imageBytes,
    required String name,
    required int imageWidth,
    required int imageHeight,
    required double raDeg,
    required double decDeg,
    required double fovDeg,
    required double rollDeg,
    required int matchedStars,
    required double rmseArcsec,
    required double solveTimeMs,
    required List<double> matchedStarX,
    required List<double> matchedStarY,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final thumbnailFileName = '$id.png';
    final imageFileName = '${id}_full.png';

    _fullImages[id] = imageBytes;
    _thumbnails[id] = await downscaleToPngWithMarkers(
      imageBytes,
      240,
      matchedStarX,
      matchedStarY,
    );

    _entries.insert(
      0,
      HistoryEntry(
        id: id,
        timestamp: DateTime.now(),
        name: name,
        thumbnailFileName: thumbnailFileName,
        imageFileName: imageFileName,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        raDeg: raDeg,
        decDeg: decDeg,
        fovDeg: fovDeg,
        rollDeg: rollDeg,
        matchedStars: matchedStars,
        rmseArcsec: rmseArcsec,
        solveTimeMs: solveTimeMs,
        matchedStarX: matchedStarX,
        matchedStarY: matchedStarY,
      ),
    );
    return List.unmodifiable(_entries);
  }

  static Future<List<HistoryEntry>> rename(String id, String newName) async {
    for (final e in _entries) {
      if (e.id == id) e.name = newName;
    }
    return List.unmodifiable(_entries);
  }

  static Future<List<HistoryEntry>> remove(String id) async {
    _thumbnails.remove(id);
    _fullImages.remove(id);
    _entries.removeWhere((e) => e.id == id);
    return List.unmodifiable(_entries);
  }

  static Future<Uint8List> thumbnailBytes(HistoryEntry entry) async {
    final bytes = _thumbnails[entry.id];
    if (bytes == null) throw StateError('${entry.id} has no thumbnail');
    return bytes;
  }

  static Future<Uint8List> fullImageBytes(HistoryEntry entry) async {
    final bytes = _fullImages[entry.id];
    if (bytes == null) throw StateError('${entry.id} has no full image');
    return bytes;
  }
}
