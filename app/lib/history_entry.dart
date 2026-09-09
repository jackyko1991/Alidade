/// One saved solve, with a small thumbnail (matched/named stars baked in as
/// small markers, so it's recognizable at a glance) for the history list,
/// plus the full solved image and star pixel positions so tapping the entry
/// can restore the exact result without re-solving.
///
/// Platform-independent — deliberately kept separate from `HistoryStore`
/// (see `history.dart`'s conditional export), which persists entries
/// differently on native vs. web.
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
    this.target,
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
  // The target the user chose before solving, if any — a SkyTarget.toJson()
  // map (see sky_target.dart), stored as a plain Map here rather than a
  // typed SkyTarget so history_entry.dart (platform-independent, no other
  // dependencies) doesn't need to depend on the picker's model. Mutable
  // like `name` — picking or clearing a target after a solve still sticks.
  Map<String, dynamic>? target;

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
    if (target != null) 'target': target,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    name: json['name'] as String,
    thumbnailFileName: json['thumbnailFileName'] as String,
    // Older entries (saved before the full image / marker data was added)
    // fall back to the thumbnail and empty marker lists rather than
    // failing to load entirely.
    imageFileName:
        json['imageFileName'] as String? ?? json['thumbnailFileName'] as String,
    imageWidth: (json['imageWidth'] as num?)?.toInt() ?? 0,
    imageHeight: (json['imageHeight'] as num?)?.toInt() ?? 0,
    raDeg: (json['raDeg'] as num).toDouble(),
    decDeg: (json['decDeg'] as num).toDouble(),
    fovDeg: (json['fovDeg'] as num).toDouble(),
    rollDeg: (json['rollDeg'] as num).toDouble(),
    matchedStars: json['matchedStars'] as int,
    rmseArcsec: (json['rmseArcsec'] as num).toDouble(),
    solveTimeMs: (json['solveTimeMs'] as num?)?.toDouble() ?? 0,
    matchedStarX:
        (json['matchedStarX'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
    matchedStarY:
        (json['matchedStarY'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [],
    // Null for every entry saved before this field existed - the same
    // older-entries fallback discipline as imageFileName/imageWidth above.
    target: (json['target'] as Map<String, dynamic>?),
  );
}
