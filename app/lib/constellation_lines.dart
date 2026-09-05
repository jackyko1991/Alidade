import 'dart:convert';

import 'package:flutter/services.dart';

/// One point in a constellation's line pattern.
class ConstellationPoint {
  const ConstellationPoint(this.raDeg, this.decDeg);

  final double raDeg;
  final double decDeg;
}

/// One constellation's line pattern: a set of polylines (point sequences
/// connected by straight segments) — most constellations need more than one
/// polyline since their star pattern isn't a single unbroken path.
class Constellation {
  const Constellation(this.id, this.polylines);

  final String id;
  final List<List<ConstellationPoint>> polylines;
}

/// Loads the bundled constellation-line asset (source: d3-celestial by Olaf
/// Frohn, BSD-3-Clause — see spike/data/catalogs/build_constellation_lines.py
/// for the conversion from GeoJSON to this compact RA/Dec form, and the About
/// screen for the on-screen attribution this license requires).
class ConstellationLines {
  ConstellationLines._(this.all);

  final List<Constellation> all;

  static ConstellationLines? _instance;

  static Future<ConstellationLines> load() async {
    final cached = _instance;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString('assets/constellation_lines.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    final constellations = decoded.map((entry) {
      final map = entry as Map<String, dynamic>;
      final lines = (map['lines'] as List<dynamic>).map((line) {
        return (line as List<dynamic>).map((point) {
          final p = point as List<dynamic>;
          return ConstellationPoint((p[0] as num).toDouble(), (p[1] as num).toDouble());
        }).toList();
      }).toList();
      return Constellation(map['id'] as String, lines);
    }).toList();

    final instance = ConstellationLines._(constellations);
    _instance = instance;
    return instance;
  }
}
