import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// One saved solve, with a small thumbnail (matched/named stars baked in as
/// small markers, so it's recognizable at a glance) for the history list,
/// plus the full solved image and star pixel positions so tapping the entry
/// can restore the exact result without re-solving. Stored as a JSON
/// manifest + separate image files under the app's documents directory —
/// deliberately not a database: the record shape is small and simple, and
/// this avoids an extra dependency.
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.timestamp,
    required this.name,
    required this.thumbnailFileName,
    required this.imageFileName,
    required this.imageWidth,
    required this.imageHeight,
    required this.raDeg,
    required this.decDeg,
    required this.fovDeg,
    required this.rollDeg,
    required this.matchedStars,
    required this.rmseArcsec,
    required this.solveTimeMs,
    required this.matchedStarX,
    required this.matchedStarY,
  });

  final String id;
  final DateTime timestamp;
  String name;
  final String thumbnailFileName;
  final String imageFileName;
  final int imageWidth;
  final int imageHeight;
  final double raDeg;
  final double decDeg;
  final double fovDeg;
  final double rollDeg;
  final int matchedStars;
  final double rmseArcsec;
  final double solveTimeMs;
  final List<double> matchedStarX;
  final List<double> matchedStarY;

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'name': name,
    'thumbnailFileName': thumbnailFileName,
    'imageFileName': imageFileName,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'raDeg': raDeg,
    'decDeg': decDeg,
    'fovDeg': fovDeg,
    'rollDeg': rollDeg,
    'matchedStars': matchedStars,
    'rmseArcsec': rmseArcsec,
    'solveTimeMs': solveTimeMs,
    'matchedStarX': matchedStarX,
    'matchedStarY': matchedStarY,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    name: json['name'] as String,
    thumbnailFileName: json['thumbnailFileName'] as String,
    // Older entries (saved before the full image / marker data was added)
    // fall back to the thumbnail and empty marker lists rather than
    // failing to load entirely.
    imageFileName: json['imageFileName'] as String? ?? json['thumbnailFileName'] as String,
    imageWidth: (json['imageWidth'] as num?)?.toInt() ?? 0,
    imageHeight: (json['imageHeight'] as num?)?.toInt() ?? 0,
    raDeg: (json['raDeg'] as num).toDouble(),
    decDeg: (json['decDeg'] as num).toDouble(),
    fovDeg: (json['fovDeg'] as num).toDouble(),
    rollDeg: (json['rollDeg'] as num).toDouble(),
    matchedStars: json['matchedStars'] as int,
    rmseArcsec: (json['rmseArcsec'] as num).toDouble(),
    solveTimeMs: (json['solveTimeMs'] as num?)?.toDouble() ?? 0,
    matchedStarX: (json['matchedStarX'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
    matchedStarY: (json['matchedStarY'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
  );
}

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
  }) async {
    final dir = await _historyDir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final thumbnailFileName = '$id.png';
    final imageFileName = '${id}_full.png';

    await File('${dir.path}/$imageFileName').writeAsBytes(imageBytes);
    final thumbBytes = await _downscaleToPngWithMarkers(
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

  static Future<Uint8List> _downscaleToPngWithMarkers(
    Uint8List bytes,
    int maxWidth,
    List<double> matchedStarX,
    List<double> matchedStarY,
  ) async {
    // Every `ui.Image` decoded here owns native/GPU memory that isn't
    // managed by Flutter's own image cache (that cache only covers images
    // loaded through an `ImageProvider`) — each one must be disposed
    // explicitly, or repeated solves slowly exhaust the GPU's descriptor
    // pool until the app crashes natively (confirmed on-device: repeated
    // solving crashed with Impeller's "ErrorOutOfPoolMemory" right before a
    // native SIGSEGV, traced back to leaked images from this function and
    // from decodes elsewhere in the app).
    final fullCodec = await ui.instantiateImageCodec(bytes);
    final fullFrame = await fullCodec.getNextFrame();
    final originalWidth = fullFrame.image.width;
    fullFrame.image.dispose();

    final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
    final frame = await codec.getNextFrame();
    final thumbWidth = frame.image.width.toDouble();
    final thumbHeight = frame.image.height.toDouble();
    final scale = originalWidth == 0 ? 1.0 : thumbWidth / originalWidth;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(frame.image, ui.Offset.zero, ui.Paint());
    final markerPaint = ui.Paint()
      ..color = const ui.Color(0xFF33E07A)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = thumbWidth / 220;
    final markerRadius = thumbWidth / 110;
    for (var i = 0; i < matchedStarX.length && i < matchedStarY.length; i++) {
      canvas.drawCircle(
        ui.Offset(matchedStarX[i] * scale, matchedStarY[i] * scale),
        markerRadius,
        markerPaint,
      );
    }
    final picture = recorder.endRecording();
    final composited = await picture.toImage(thumbWidth.round(), thumbHeight.round());
    frame.image.dispose();
    final byteData = await composited.toByteData(format: ui.ImageByteFormat.png);
    composited.dispose();
    return byteData!.buffer.asUint8List();
  }
}
