import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'db_manifest.dart';

/// Downloads, caches, and cleans up per-lens solver databases. Each
/// [DbBucket] is stored as its own file under the app's own support
/// directory, keyed by bucket id — several lens presets that map to the
/// same bucket share one downloaded file, and [deleteIfUnused] removes it
/// again once no remaining preset needs it.
class DbManager {
  static Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/dbs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> fileFor(DbBucket bucket) async {
    final dir = await _dir();
    return File('${dir.path}/${bucket.fileName}');
  }

  static Future<bool> isDownloaded(DbBucket bucket) async {
    final f = await fileFor(bucket);
    return f.exists();
  }

  /// Downloads [bucket] to its cache slot, reporting progress as bytes
  /// received out of the total (falling back to the manifest's recorded
  /// size if the server doesn't send a content-length). Writes to a
  /// `.part` file first and renames on completion, so a failed/killed
  /// download can't leave a corrupt file mistaken for a good one.
  static Future<void> download(
    DbBucket bucket, {
    void Function(int received, int total)? onProgress,
  }) async {
    final file = await fileFor(bucket);
    final tmp = File('${file.path}.part');
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(bucket.downloadUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }
      final total = response.contentLength ?? bucket.sizeBytes;
      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      await tmp.rename(file.path);
    } finally {
      client.close();
    }
  }

  static Future<void> delete(DbBucket bucket) async {
    final f = await fileFor(bucket);
    if (await f.exists()) await f.delete();
  }

  /// Deletes [bucket]'s cached file if none of [remainingFovDegs] (the
  /// lens presets left after a deletion) still map to it.
  static Future<void> deleteIfUnused(DbBucket bucket, List<double> remainingFovDegs) async {
    final stillNeeded = remainingFovDegs.any((fov) => bucketForFovDeg(fov).id == bucket.id);
    if (!stillNeeded) await delete(bucket);
  }

  static Future<Uint8List> readBytes(DbBucket bucket) async {
    final f = await fileFor(bucket);
    return f.readAsBytes();
  }
}
