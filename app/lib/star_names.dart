import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How to label stars in the overlay: a short list of famous popular names
/// (Deneb, Vega, ...) or the much denser Flamsteed/Bayer catalog-designation
/// scheme astrometry.net's own annotator uses (e.g. "13 Vul", "39 Cyg") —
/// the two are genuinely different catalogs, not a display-formatting
/// choice: popular names cover ~67 first-magnitude stars, designations
/// cover ~2,500 naked-eye stars (mag <= 6.5), so the designation style will
/// label vastly more matched stars in any given frame.
enum StarLabelStyle { popularNames, catalogDesignations }

const _styleKey = 'star_label_style_v1';

class StarLabelStylePref {
  static Future<StarLabelStyle> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_styleKey);
    return raw == 'catalogDesignations'
        ? StarLabelStyle.catalogDesignations
        : StarLabelStyle.popularNames; // default
  }

  static Future<void> save(StarLabelStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_styleKey, style.name);
  }
}

/// A star with a label to draw, regardless of which catalog it came from.
class NamedStar {
  NamedStar({required this.name, required this.raDeg, required this.decDeg});

  final String name;
  final double raDeg;
  final double decDeg;

  factory NamedStar.fromPopularNameJson(Map<String, dynamic> json) => NamedStar(
    name: json['name'] as String,
    raDeg: (json['ra_deg'] as num).toDouble(),
    decDeg: (json['dec_deg'] as num).toDouble(),
  );

  factory NamedStar.fromDesignationJson(Map<String, dynamic> json) => NamedStar(
    name: json['label'] as String,
    raDeg: (json['ra_deg'] as num).toDouble(),
    decDeg: (json['dec_deg'] as num).toDouble(),
  );
}

/// Loads whichever bundled star-label catalog the user has selected:
/// - Popular names: 67 stars bright enough (mag<4) to be Hipparcos gap-fill
///   entries in our bundled Gaia catalog, matched against the IAU Catalog
///   of Star Names (MIT licensed).
/// - Catalog designations: ~2,500 stars (mag<=6.5) from the Yale Bright
///   Star Catalog (BSC5, Hoffleit & Warren 1991 — public/freely
///   redistributable), labeled by Flamsteed number + constellation.
class StarNames {
  StarNames._(this._stars);

  final List<NamedStar> _stars;

  static StarLabelStyle? _cachedStyle;
  static StarNames? _instance;

  static Future<StarNames> load() async {
    final style = await StarLabelStylePref.load();
    final cached = _instance;
    if (cached != null && _cachedStyle == style) return cached;

    final List<NamedStar> stars;
    if (style == StarLabelStyle.catalogDesignations) {
      final raw = await rootBundle.loadString('assets/bsc5_designations.json');
      final decoded = jsonDecode(raw) as List<dynamic>;
      stars = decoded
          .map((v) => NamedStar.fromDesignationJson(v as Map<String, dynamic>))
          .toList();
    } else {
      final raw = await rootBundle.loadString('assets/star_names.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      stars = decoded.values
          .map((v) => NamedStar.fromPopularNameJson(v as Map<String, dynamic>))
          .toList();
    }

    final instance = StarNames._(stars);
    _instance = instance;
    _cachedStyle = style;
    return instance;
  }

  List<NamedStar> get all => _stars;
}
