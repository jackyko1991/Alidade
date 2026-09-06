import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// A saved camera+lens combination, or a direct FOV entry.
///
/// Stores both sensor width and height because `tetra3`'s FOV estimate is
/// for the image's *current pixel width* — and after EXIF-orientation
/// normalization, a portrait photo's pixel width corresponds to the
/// sensor's physical *height* (the short axis), not its width. Use
/// [fovDegForImage] with the actual decoded image dimensions rather than
/// [fovDeg] directly whenever the image's orientation isn't already known
/// to be landscape.
class LensPreset {
  LensPreset({
    required this.name,
    this.focalLengthMm,
    this.sensorWidthMm,
    this.sensorHeightMm,
    // ignore: prefer_initializing_formals — public param name intentionally
    // differs from the private field it sets.
    double? fovDegOverride,
  }) : _fovDegOverride = fovDegOverride;

  final String name;
  final double? focalLengthMm;
  final double? sensorWidthMm;
  final double? sensorHeightMm;
  final double? _fovDegOverride;

  /// True if this preset stores a direct FOV rather than focal length/sensor.
  bool get isDirectFov => _fovDegOverride != null;

  /// Horizontal FOV assuming a landscape-oriented image (pixel width maps to
  /// [sensorWidthMm]). Prefer [fovDegForImage] once you know the actual
  /// image dimensions.
  double get fovDeg => _fovFor(sensorWidthMm);

  /// FOV for whichever sensor dimension currently maps to the image's pixel
  /// *width*: [sensorWidthMm] if landscape/square, [sensorHeightMm] (falling
  /// back to width if height wasn't recorded) if portrait.
  double fovDegForImage({required bool isPortrait}) {
    if (_fovDegOverride != null) return _fovDegOverride;
    if (!isPortrait) return fovDeg;
    return _fovFor(sensorHeightMm ?? sensorWidthMm);
  }

  double _fovFor(double? sensorDimMm) {
    if (_fovDegOverride != null) return _fovDegOverride;
    final f = focalLengthMm;
    if (f == null || sensorDimMm == null || f <= 0) return 15.2;
    return 2 * math.atan(sensorDimMm / (2 * f)) * 180 / math.pi;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'focalLengthMm': focalLengthMm,
    'sensorWidthMm': sensorWidthMm,
    'sensorHeightMm': sensorHeightMm,
    'fovDegOverride': _fovDegOverride,
  };

  factory LensPreset.fromJson(Map<String, dynamic> json) => LensPreset(
    name: json['name'] as String,
    focalLengthMm: (json['focalLengthMm'] as num?)?.toDouble(),
    sensorWidthMm: (json['sensorWidthMm'] as num?)?.toDouble(),
    sensorHeightMm: (json['sensorHeightMm'] as num?)?.toDouble(),
    fovDegOverride: (json['fovDegOverride'] as num?)?.toDouble(),
  );
}

/// Common sensor sizes (width mm, height mm), for the "add lens" quick-pick.
const Map<String, (double, double)> commonSensorSizes = {
  'Full frame (35mm)': (36.0, 24.0),
  'APS-C (Sony/Nikon/Fuji)': (23.5, 15.6),
  'APS-C (Canon)': (22.3, 14.9),
  'Micro Four Thirds': (17.3, 13.0),
  'APS-H': (27.9, 18.6),
};

const _prefsKey = 'lens_presets_v1';

class LensPresetStore {
  /// No auto-created default here (there used to be a silent "135mm, full
  /// frame" fallback) — with per-lens FOV-bucketed databases now
  /// downloaded on demand, a made-up default would either point at the
  /// wrong bucket for the user's actual lens or need its database
  /// downloaded for no reason. An empty list is a real, valid state the
  /// UI handles directly (see SolveScreen's empty-profiles reminder)
  /// rather than something to paper over here.
  static Future<List<LensPreset>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    return raw
        .map((s) => LensPreset.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(List<LensPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      presets.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }
}
