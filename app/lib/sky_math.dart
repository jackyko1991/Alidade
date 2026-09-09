import 'dart:math' as math;

/// Great-circle angular separation between two J2000 equatorial positions,
/// in degrees. Shared by [ObjectNameCatalog.nearestTo] (reverse lookup —
/// solved position to catalog name) and `TargetCatalog` (forward lookup —
/// catalog search to solved position), which is why this lives in its own
/// file rather than either of theirs.
double angularSeparationDeg(double ra1, double dec1, double ra2, double dec2) {
  final r1 = dec1 * math.pi / 180;
  final r2 = dec2 * math.pi / 180;
  final dRa = (ra1 - ra2) * math.pi / 180;
  final cosD =
      math.sin(r1) * math.sin(r2) + math.cos(r1) * math.cos(r2) * math.cos(dRa);
  final clamped = cosD.clamp(-1.0, 1.0);
  return math.acos(clamped) * 180 / math.pi;
}
