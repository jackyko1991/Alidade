import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'history_entry.dart';
import 'history_thumbnail.dart';

/// Native (Android/iOS/desktop) implementation: stores entries as a JSON
/// manifest + separate image files under the app's documents directory —
/// deliberately not a database, since the record shape is small and simple.
///
/// Not used directly — see `history.dart`'s conditional export. There's a
/// separate `history_store_web.dart` because this one depends on
/// `dart:io`'s `File`/`Directory` and `path_provider`, neither of which
/// work on Flutter web: `path_provider` has no web platform implementation
/// at all (see `db_manager_io.dart`'s doc comment, which hit the exact same
/// gap first), so calling `getApplicationDocumentsDirectory()` on web
/// throws `MissingPluginException` — confirmed live, driving the actual
/// deployed PWA (see `docs/web-build.md`).
class HistoryStore {
  static const _manifestFileName = 'history_manifest.json';
  static const _thumbMaxWidth = 240;

  static Future<Directory> _historyDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/history');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<HistoryEntry>> load() async {
    final dir = await _historyDir();
    final manifestFile = File('${dir.path}/$_manifestFileName');
    if (!await manifestFile.exists()) return [];
    final raw = await manifestFile.readAsString();
    final list = jsonDecode(raw) as List<dynamic>;
    final entries = list
        .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  static Future<void> _saveManifest(List<HistoryEntry> entries) async {
    final dir = await _historyDir();
    final manifestFile = File('${dir.path}/$_manifestFileName');
    await manifestFile.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// Saves the full solved image, a small thumbnail with the matched/named
  /// star markers baked in (so history rows are recognizable at a glance,
  /// not just a flat starfield), and a new history entry. Returns the
  /// updated full list.
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
    Map<String, dynamic>? target,
  }) async {
    final dir = await _historyDir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final thumbnailFileName = '$id.png';
    final imageFileName = '${id}_full.png';

    await File('${dir.path}/$imageFileName').writeAsBytes(imageBytes);
    final thumbBytes = await downscaleToPngWithMarkers(
      imageBytes,
      _thumbMaxWidth,
      matchedStarX,
      matchedStarY,
    );
    await File('${dir.path}/$thumbnailFileName').writeAsBytes(thumbBytes);

    final entries = await load();
    entries.insert(
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
        target: target,
      ),
    );
    await _saveManifest(entries);
    return entries;
  }

  static Future<List<HistoryEntry>> rename(String id, String newName) async {
    final entries = await load();
    for (final e in entries) {
      if (e.id == id) e.name = newName;
    }
    await _saveManifest(entries);
    return entries;
  }

  static Future<List<HistoryEntry>> setTarget(
    String id,
    Map<String, dynamic>? target,
  ) async {
    final entries = await load();
    for (final e in entries) {
      if (e.id == id) e.target = target;
    }
    await _saveManifest(entries);
    return entries;
  }

  static Future<List<HistoryEntry>> remove(String id) async {
    final dir = await _historyDir();
    final entries = await load();
    final removed = entries.where((e) => e.id == id);
    for (final e in removed) {
      final thumb = File('${dir.path}/${e.thumbnailFileName}');
      if (await thumb.exists()) await thumb.delete();
      final full = File('${dir.path}/${e.imageFileName}');
      if (await full.exists()) await full.delete();
    }
    entries.removeWhere((e) => e.id == id);
    await _saveManifest(entries);
    return entries;
  }

  static Future<Uint8List> thumbnailBytes(HistoryEntry entry) async {
    final dir = await _historyDir();
    return File('${dir.path}/${entry.thumbnailFileName}').readAsBytes();
  }

  static Future<Uint8List> fullImageBytes(HistoryEntry entry) async {
    final dir = await _historyDir();
    return File('${dir.path}/${entry.imageFileName}').readAsBytes();
  }
}
