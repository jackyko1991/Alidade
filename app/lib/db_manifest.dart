import 'package:flutter/foundation.dart' show kIsWeb;

/// One downloadable solver database, covering a range of horizontal FOV
/// (and so, roughly, a range of focal lengths). Sizes come from the
/// `databases-v1` GitHub Release — built via `spike/data/catalogs`'s
/// `build-db` step at the given max FOV; see spike/data for how these
/// were generated and measured.
///
/// Deliberately excludes sub-1° FOV (very long telephoto / heavy crop):
/// that regime needs much bigger databases (a single-scale 1°-max
/// database measured 918MB during testing) and is planned for a later
/// paid/online tier rather than a direct download here.
class DbBucket {
  const DbBucket({
    required this.id,
    required this.maxFovDeg,
    required this.focalLengthRange,
    required this.sizeBytes,
  });

  final String id;
  final double maxFovDeg;
  final String focalLengthRange;
  final int sizeBytes;

  String get fileName => 'db_$id.bin';

  // Native builds fetch straight from the GitHub Release. The web build
  // can't: confirmed live (headless Chrome against the deployed PWA) that
  // fetching a release asset from a GitHub Pages origin fails with
  // "TypeError: Failed to fetch" — GitHub's release-asset host
  // (release-assets.githubusercontent.com) sends no
  // Access-Control-Allow-Origin header, so the browser blocks the
  // cross-origin response entirely. Serving the same files same-origin
  // instead (copied into the Pages build's own `dbs/` folder by
  // .github/workflows/deploy-pwa.yml) sidesteps CORS altogether. This is
  // a relative URL, resolved by the browser against the page's own
  // `<base href>` — works whether that's `/Alidade/` (GitHub Pages) or
  // `/` (a future custom domain) without needing to know it here.
  String get downloadUrl => kIsWeb
      ? 'dbs/$fileName'
      : 'https://github.com/jackyko1991/Alidade/releases/download/databases-v1/$fileName';

  String get sizeLabel {
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).round()} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Sorted ascending by maxFovDeg — [bucketForFovDeg] relies on that order.
const dbBuckets = <DbBucket>[
  DbBucket(id: 'fov4', maxFovDeg: 4, focalLengthRange: '350-600mm', sizeBytes: 132244320),
  DbBucket(id: 'fov8', maxFovDeg: 8, focalLengthRange: '180-350mm', sizeBytes: 31371299),
  DbBucket(id: 'fov16', maxFovDeg: 16, focalLengthRange: '100-180mm', sizeBytes: 7722703),
  DbBucket(id: 'fov28', maxFovDeg: 28, focalLengthRange: '50-100mm', sizeBytes: 2505692),
  DbBucket(id: 'fov55', maxFovDeg: 55, focalLengthRange: '24-50mm', sizeBytes: 615590),
  DbBucket(id: 'fov130', maxFovDeg: 130, focalLengthRange: '10-24mm', sizeBytes: 104767),
];

/// The narrowest bucket whose max FOV still covers [fovDeg] — the
/// smallest (and so fastest-to-search) database that should actually be
/// able to solve an image at that field of view. Falls back to the
/// widest bucket for anything wider than 130° (very rare, e.g. sub-10mm
/// fisheyes) and to the narrowest for anything under 4° (outside the
/// declared 10-600mm range — not guaranteed to solve reliably; that's the
/// sub-1°-style regime reserved for a future tier, just without a hard
/// cutoff at exactly 4°).
DbBucket bucketForFovDeg(double fovDeg) {
  for (final bucket in dbBuckets) {
    if (fovDeg <= bucket.maxFovDeg) return bucket;
  }
  return dbBuckets.last;
}
