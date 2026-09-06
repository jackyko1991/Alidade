import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'db_manifest.dart';

/// Web implementation: downloads and caches per-lens solver databases
/// in memory for the lifetime of the page (not persisted across reloads
/// or restarts) — not used directly, see `db_manager.dart`'s conditional
/// export.
///
/// There's no native-style file cache here because there's nowhere safe
/// to put one: `path_provider` (which the native `db_manager_io.dart`
/// uses for its cache directory) has no web platform implementation at
/// all (confirmed in its own pubspec.yaml), so calling it on web throws
/// `MissingPluginException` rather than silently no-opping — confirmed
/// live, driving the actual deployed PWA (see `docs/web-build.md`). A
/// real persistent web cache (IndexedDB or the Origin Private File
/// System) is possible later but adds real complexity for a database
/// that's a few hundred KB to ~130MB; re-fetching once per page load is
/// the honest, working starting point instead of a broken persistent one.
class DbManager {
  static final Map<String, Uint8List> _cache = {};

  static Future<bool> isDownloaded(DbBucket bucket) async => _cache.containsKey(bucket.id);

  static Future<void> download(
    DbBucket bucket, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(bucket.downloadUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }
      final total = response.contentLength ?? bucket.sizeBytes;
      final bytes = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      _cache[bucket.id] = bytes.takeBytes();
    } finally {
      client.close();
    }
  }

  static Future<void> delete(DbBucket bucket) async {
    _cache.remove(bucket.id);
  }

  /// Removes [bucket]'s cached bytes if none of [remainingFovDegs] (the
  /// lens presets left after a deletion) still map to it.
  static Future<void> deleteIfUnused(DbBucket bucket, List<double> remainingFovDegs) async {
    final stillNeeded = remainingFovDegs.any((fov) => bucketForFovDeg(fov).id == bucket.id);
    if (!stillNeeded) await delete(bucket);
  }

  static Future<Uint8List> readBytes(DbBucket bucket) async {
    final bytes = _cache[bucket.id];
    if (bytes == null) throw StateError('${bucket.id} was not downloaded');
    return bytes;
  }
}
