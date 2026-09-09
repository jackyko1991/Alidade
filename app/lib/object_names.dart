import 'dart:convert';

import 'package:flutter/services.dart';

import 'sky_math.dart';

/// A named deep-sky object from the bundled catalog (currently just Messier
/// — the free tier's small curated list; a full-OpenNGC IAP tier can read
/// through the same [nearestTo] interface later by merging in more objects).
class NamedObject {
  NamedObject({
    required this.id,
    required this.ngc,
    required this.name,
    required this.type,
    required this.constellation,
    required this.raDeg,
    required this.decDeg,
    this.mag,
  });

  final String id;
  final String? ngc;
  final String? name;
  final String? type;
  final String? constellation;
  final double raDeg;
  final double decDeg;
  final double? mag;

  /// Best display label: popular nickname if there is one (e.g. "Dumbbell
  /// Nebula"), else the catalog id with its type (e.g. "M76 — Planetary
  /// Nebula").
  String get displayName {
    if (name != null) return name!;
    final t = type;
    return t == null ? id : '$id — $t';
  }

  factory NamedObject.fromJson(Map<String, dynamic> json) => NamedObject(
    id: json['id'] as String,
    ngc: json['ngc'] as String?,
    name: json['name'] as String?,
    type: json['type'] as String?,
    constellation: json['constellation'] as String?,
    raDeg: (json['ra_deg'] as num).toDouble(),
    decDeg: (json['dec_deg'] as num).toDouble(),
    mag: (json['mag'] as num?)?.toDouble(),
  );
}

/// Looks up the nearest bundled catalog object to a solved RA/Dec — the
/// "what am I looking at" suggestion offered after a successful solve.
class ObjectNameCatalog {
  ObjectNameCatalog._(this._objects);

  final List<NamedObject> _objects;

  static ObjectNameCatalog? _instance;

  static Future<ObjectNameCatalog> load() async {
    final cached = _instance;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/messier.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    final objects = decoded
        .map((e) => NamedObject.fromJson(e as Map<String, dynamic>))
        .toList();
    final instance = ObjectNameCatalog._(objects);
    _instance = instance;
    return instance;
  }

  /// The closest catalog object to (raDeg, decDeg), or null if none falls
  /// within [maxSeparationDeg] (default: generous enough to catch an object
  /// anywhere in a typical solved frame, not just dead-center).
  NamedObject? nearestTo(
    double raDeg,
    double decDeg, {
    double maxSeparationDeg = 10.0,
  }) {
    NamedObject? best;
    var bestSep = double.infinity;
    for (final obj in _objects) {
      final sep = angularSeparationDeg(raDeg, decDeg, obj.raDeg, obj.decDeg);
      if (sep < bestSep) {
        bestSep = sep;
        best = obj;
      }
    }
    if (best == null || bestSep > maxSeparationDeg) return null;
    return best;
  }
}
