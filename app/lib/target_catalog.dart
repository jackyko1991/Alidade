import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ephemeris.dart';
import 'sky_math.dart';
import 'sky_target.dart';

/// Loads every static and dynamic sky-target source and answers the
/// picker's search queries. Static-cached like `ObjectNameCatalog`/
/// `StarNames` (see object_names.dart, star_names.dart), but the ~1.5MB of
/// bundled JSON is decoded off the UI thread (see [_load]) since that part
/// alone runs 150-250ms - long enough to jank the picker's open animation
/// if left on the main isolate.
class TargetCatalog {
  TargetCatalog._(this._targets) : _index = _TargetSearchIndex(_targets);

  final List<SkyTarget> _targets;
  final _TargetSearchIndex _index;

  static TargetCatalog? _instance;
  static Future<TargetCatalog>? _inFlight;

  static Future<TargetCatalog> load() {
    final cached = _instance;
    if (cached != null) return Future.value(cached);
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = _load();
    _inFlight = future;
    return future;
  }

  static Future<TargetCatalog> _load() async {
    final deepSkyRaw = await rootBundle.loadString('assets/deepsky.json');
    final doubleStarsRaw = await rootBundle.loadString(
      'assets/double_stars.json',
    );
    final starNamesRaw = await rootBundle.loadString('assets/star_names.json');
    final bsc5Raw = await rootBundle.loadString(
      'assets/bsc5_designations.json',
    );

    // rootBundle.loadString already ran on the main isolate (rootBundle
    // isn't isolate-safe); only the actual JSON decode plus the star-merge
    // pass below - a few thousand comparisons - moves off it via compute().
    final targets = await compute(_decodeAllTargets, [
      deepSkyRaw,
      doubleStarsRaw,
      starNamesRaw,
      bsc5Raw,
    ]);

    final instance = TargetCatalog._(targets);
    _instance = instance;
    return instance;
  }

  /// Every static (non-solar-system) target, sorted by magnitude ascending
  /// (nulls last).
  List<SkyTarget> get all => _targets;

  List<SkyTarget>? _solarSystemCache;
  DateTime? _solarSystemCacheAt;

  /// Sun + Moon + 7 planets "now", memoised for 5 minutes - see
  /// ephemeris.dart's doc comment for why that's a safe window (the Moon,
  /// the fastest-moving body, drifts under 3' in that time).
  List<SkyTarget> solarSystem(DateTime now) {
    final cachedAt = _solarSystemCacheAt;
    final cached = _solarSystemCache;
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt).abs() < const Duration(minutes: 5)) {
      return cached;
    }
    final bodies = computeSolarSystem(now).map(_bodyToTarget).toList();
    _solarSystemCache = bodies;
    _solarSystemCacheAt = now;
    return bodies;
  }

  /// Ranked matches for [query], merging in the solar-system bodies before
  /// ranking so e.g. "ju" can surface Jupiter alongside catalog entries.
  /// An empty/whitespace query returns the catalog's brightest entries
  /// (still capped at [limit]) rather than nothing, so opening the picker
  /// with an empty field isn't a blank list.
  List<SkyTarget> search(
    String query, {
    int limit = 50,
    DateTime? now,
    TargetKind? category,
  }) {
    final dynamicTargets = solarSystem(now ?? DateTime.now());
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      final combined = [...dynamicTargets, ..._targets];
      final filtered = category == null
          ? combined
          : combined.where((t) => t.kind == category);
      return filtered.take(limit).toList();
    }
    return _index.search(
      trimmed,
      dynamicTargets,
      limit: limit,
      category: category,
    );
  }
}

SkyTarget _bodyToTarget(BodyPosition body) {
  final kind = body.body == SolarSystemBody.sun
      ? TargetKind.sun
      : body.body == SolarSystemBody.moon
      ? TargetKind.moon
      : TargetKind.planet;
  final name = _solarSystemDisplayName[body.body]!;
  return SkyTarget(
    id: name,
    displayName: name,
    kind: kind,
    typeLabel: kind == TargetKind.sun
        ? 'Star'
        : kind == TargetKind.moon
        ? 'Natural Satellite'
        : 'Planet',
    raDeg: body.raDeg,
    decDeg: body.decDeg,
    magnitude: body.magnitude,
    isDynamic: true,
  );
}

const _solarSystemDisplayName = {
  SolarSystemBody.sun: 'Sun',
  SolarSystemBody.moon: 'Moon',
  SolarSystemBody.mercury: 'Mercury',
  SolarSystemBody.venus: 'Venus',
  SolarSystemBody.mars: 'Mars',
  SolarSystemBody.jupiter: 'Jupiter',
  SolarSystemBody.saturn: 'Saturn',
  SolarSystemBody.uranus: 'Uranus',
  SolarSystemBody.neptune: 'Neptune',
};

/// Runs on a background isolate via [compute]: decodes all four bundled
/// assets and merges the two star catalogs into one deduplicated list.
/// A top-level function (required by `compute`), with no Flutter-binding
/// dependency - only `dart:convert` and the plain-Dart `sky_math.dart`.
List<SkyTarget> _decodeAllTargets(List<String> raw) {
  final deepSkyRows = jsonDecode(raw[0]) as List<dynamic>;
  final doubleStarRows = jsonDecode(raw[1]) as List<dynamic>;
  final popularStars = jsonDecode(raw[2]) as Map<String, dynamic>;
  final bsc5Rows = jsonDecode(raw[3]) as List<dynamic>;

  final targets = <SkyTarget>[
    for (final row in deepSkyRows) SkyTarget.fromRow(row as List<dynamic>),
    for (final row in doubleStarRows)
      SkyTarget.fromDoubleStarJson(row as Map<String, dynamic>),
    ..._mergeStars(popularStars, bsc5Rows),
  ];
  targets.sort((a, b) {
    final magA = a.magnitude ?? double.infinity;
    final magB = b.magnitude ?? double.infinity;
    return magA.compareTo(magB);
  });
  return targets;
}

/// Merges star_names.json's ~67 popular names (no magnitude) with
/// bsc5_designations.json's ~2,500 Flamsteed/Bayer designations (has
/// magnitude, down to naked-eye limit) into one star list: a popular star
/// found within 36" of a BSC5 entry takes that entry's magnitude and gets
/// the BSC5 designation as a searchable alias, rather than appearing as
/// two separate rows for the same star.
List<SkyTarget> _mergeStars(
  Map<String, dynamic> popularStars,
  List<dynamic> bsc5Rows,
) {
  final bsc5 = bsc5Rows.cast<Map<String, dynamic>>();
  final matchedBsc5Indices = <int>{};
  final merged = <SkyTarget>[];

  for (final entry in popularStars.entries) {
    final star = entry.value as Map<String, dynamic>;
    final raDeg = (star['ra_deg'] as num).toDouble();
    final decDeg = (star['dec_deg'] as num).toDouble();
    final name = star['name'] as String;

    var bestIndex = -1;
    var bestSepDeg = double.infinity;
    for (var i = 0; i < bsc5.length; i++) {
      final candidate = bsc5[i];
      final sep = angularSeparationDeg(
        raDeg,
        decDeg,
        (candidate['ra_deg'] as num).toDouble(),
        (candidate['dec_deg'] as num).toDouble(),
      );
      if (sep < bestSepDeg) {
        bestSepDeg = sep;
        bestIndex = i;
      }
    }

    if (bestIndex >= 0 && bestSepDeg * 3600 < 36) {
      final match = bsc5[bestIndex];
      matchedBsc5Indices.add(bestIndex);
      merged.add(
        SkyTarget(
          id: 'HR ${match['hr']}',
          displayName: name,
          kind: TargetKind.star,
          typeLabel: 'Star',
          raDeg: (match['ra_deg'] as num).toDouble(),
          decDeg: (match['dec_deg'] as num).toDouble(),
          magnitude: (match['mag'] as num).toDouble(),
          aliases: [match['label'] as String],
        ),
      );
    } else {
      // No BSC5 match within tolerance (shouldn't normally happen - every
      // popular-name star is bright enough for BSC5's mag<=6.5 cutoff) -
      // still include it, just without a magnitude, rather than lose it.
      merged.add(
        SkyTarget(
          id: 'star-${name.toLowerCase()}',
          displayName: name,
          kind: TargetKind.star,
          typeLabel: 'Star',
          raDeg: raDeg,
          decDeg: decDeg,
        ),
      );
    }
  }

  for (var i = 0; i < bsc5.length; i++) {
    if (matchedBsc5Indices.contains(i)) continue;
    final star = bsc5[i];
    merged.add(
      SkyTarget(
        id: 'HR ${star['hr']}',
        displayName: star['label'] as String,
        kind: TargetKind.star,
        typeLabel: 'Star',
        raDeg: (star['ra_deg'] as num).toDouble(),
        decDeg: (star['dec_deg'] as num).toDouble(),
        magnitude: (star['mag'] as num).toDouble(),
      ),
    );
  }

  return merged;
}

/// Ranking tiers, most to least specific - see [_TargetSearchIndex.search].
class _Score {
  static const exactId = 0;
  static const exactName = 1;
  static const idPrefix = 2;
  static const namePrefix = 3;
  static const wordPrefix = 4;
  static const substring = 5;
}

/// A search index over every static target: two normalised key forms per
/// row (squashed - lowercase, punctuation stripped, so "M 31"/"m31"/"NGC
/// 224" all key the same way regardless of spacing; and spaced - lowercase,
/// punctuation -> single space, plus one extra key per interior word so a
/// mid-name word like "nebula" ranks as a prefix hit rather than a bare
/// substring one), with a bounded top-[limit] scan and a prefix-refinement
/// cache so retyping a search only rescans the previous keystroke's
/// candidates rather than the whole ~34,000-key corpus.
class _TargetSearchIndex {
  _TargetSearchIndex(this._targets) {
    for (var i = 0; i < _targets.length; i++) {
      final target = _targets[i];
      _addIdKey(_squash(target.id), i);
      for (final alias in target.aliases) {
        _addIdKey(_squash(alias), i);
      }
      final spacedName = _spaced(target.displayName);
      _addNameKey(spacedName, i);
      for (final word in spacedName.split(' ')) {
        if (word.length > 2) _addWordKey(word, i);
      }
    }
  }

  final List<SkyTarget> _targets;

  // Three parallel maps rather than one keyed-by-everything structure:
  // the ranking rule cares which role a key played (id/alias vs full name
  // vs a bare interior word), so keeping them separate avoids re-deriving
  // that role at query time.
  final Map<String, List<int>> _idKeys = {};
  final Map<String, List<int>> _nameKeys = {};
  final Map<String, List<int>> _wordKeys = {};

  void _addIdKey(String key, int i) {
    if (key.isEmpty) return;
    _idKeys.putIfAbsent(key, () => []).add(i);
  }

  void _addNameKey(String key, int i) {
    if (key.isEmpty) return;
    _nameKeys.putIfAbsent(key, () => []).add(i);
  }

  void _addWordKey(String key, int i) {
    _wordKeys.putIfAbsent(key, () => []).add(i);
  }

  static String _squash(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _spaced(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  String? _lastSquashed;
  List<int>? _lastCandidates;

  List<SkyTarget> search(
    String rawQuery,
    List<SkyTarget> dynamicTargets, {
    required int limit,
    TargetKind? category,
  }) {
    final squashed = _squash(rawQuery);
    final spaced = _spaced(rawQuery);

    List<int> candidates;
    final lastSquashed = _lastSquashed;
    if (lastSquashed != null &&
        squashed.startsWith(lastSquashed) &&
        _lastCandidates != null &&
        squashed.length > lastSquashed.length) {
      // Prefix refinement: `contains` is monotone under prefix extension,
      // so re-scanning only the previous keystroke's candidates is exact,
      // not a heuristic - the result equals a fresh full scan.
      candidates = _rescan(_lastCandidates!, squashed, spaced);
    } else {
      candidates = _fullScan(squashed, spaced);
    }
    _lastSquashed = squashed;
    _lastCandidates = candidates;

    final scored = <(int target, int score)>[];
    final singleChar = squashed.length <= 1 && spaced.length <= 1;
    for (final i in candidates) {
      final score = _scoreOf(i, squashed, spaced);
      if (score == null) continue;
      if (singleChar && score > _Score.namePrefix) continue;
      scored.add((i, score));
    }

    // Dynamic (solar-system) targets aren't in the static index at all -
    // score them directly against the same rules so a query like "ju"
    // ranks Jupiter alongside any static-catalog hits.
    for (var i = 0; i < dynamicTargets.length; i++) {
      final t = dynamicTargets[i];
      final idSquash = _squash(t.id);
      final nameSpaced = _spaced(t.displayName);
      int? score;
      if (idSquash == squashed || nameSpaced == spaced) {
        score = idSquash == squashed ? _Score.exactId : _Score.exactName;
      } else if (idSquash.startsWith(squashed)) {
        score = _Score.idPrefix;
      } else if (nameSpaced.startsWith(spaced)) {
        score = _Score.namePrefix;
      } else if (nameSpaced.contains(spaced)) {
        score = _Score.substring;
      }
      if (score == null) continue;
      if (singleChar && score > _Score.namePrefix) continue;
      scored.add((-(i + 1), score)); // negative index flags "dynamic"
    }

    SkyTarget resolve(int encodedIndex) => encodedIndex < 0
        ? dynamicTargets[-encodedIndex - 1]
        : _targets[encodedIndex];

    scored.sort((a, b) {
      final scoreCmp = a.$2.compareTo(b.$2);
      if (scoreCmp != 0) return scoreCmp;
      final targetA = resolve(a.$1), targetB = resolve(b.$1);
      final magA = targetA.magnitude ?? double.infinity;
      final magB = targetB.magnitude ?? double.infinity;
      final magCmp = magA.compareTo(magB);
      if (magCmp != 0) return magCmp;
      final kindCmp = _kindPriority(targetA.kind)
          .compareTo(_kindPriority(targetB.kind));
      if (kindCmp != 0) return kindCmp;
      return targetA.id.compareTo(targetB.id);
    });

    final results = <SkyTarget>[];
    for (final entry in scored) {
      final target = resolve(entry.$1);
      if (category != null && target.kind != category) continue;
      results.add(target);
      if (results.length >= limit) break;
    }
    return results;
  }

  List<int> _fullScan(String squashed, String spaced) {
    final hits = <int>{};
    for (final key in _idKeys.keys) {
      if (key.contains(squashed)) hits.addAll(_idKeys[key]!);
    }
    for (final key in _nameKeys.keys) {
      if (key.contains(spaced)) hits.addAll(_nameKeys[key]!);
    }
    for (final key in _wordKeys.keys) {
      if (key.contains(spaced)) hits.addAll(_wordKeys[key]!);
    }
    return hits.toList();
  }

  List<int> _rescan(List<int> previous, String squashed, String spaced) {
    return previous
        .where((i) => _scoreOf(i, squashed, spaced) != null)
        .toList();
  }

  int? _scoreOf(int i, String squashed, String spaced) {
    final target = _targets[i];
    final idSquash = _squash(target.id);
    final aliasSquashes = target.aliases.map(_squash);
    final nameSpaced = _spaced(target.displayName);

    if (idSquash == squashed || aliasSquashes.contains(squashed)) {
      return _Score.exactId;
    }
    if (nameSpaced == spaced) return _Score.exactName;
    if (idSquash.startsWith(squashed) ||
        aliasSquashes.any((a) => a.startsWith(squashed))) {
      return _Score.idPrefix;
    }
    if (nameSpaced.startsWith(spaced)) return _Score.namePrefix;
    for (final word in nameSpaced.split(' ')) {
      if (word.startsWith(spaced)) return _Score.wordPrefix;
    }
    if (idSquash.contains(squashed) ||
        nameSpaced.contains(spaced) ||
        aliasSquashes.any((a) => a.contains(squashed))) {
      return _Score.substring;
    }
    return null;
  }
}

int _kindPriority(TargetKind kind) {
  switch (kind) {
    case TargetKind.sun:
    case TargetKind.moon:
    case TargetKind.planet:
      return 0;
    case TargetKind.messier:
      return 1;
    case TargetKind.caldwell:
      return 2;
    case TargetKind.doubleStar:
      return 3;
    case TargetKind.star:
      return 4;
    case TargetKind.ngc:
      return 5;
    case TargetKind.ic:
      return 6;
  }
}
