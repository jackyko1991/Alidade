/// Local Sidereal Time, Hour Angle, and time-to-meridian-flip — the math
/// behind the target picker's "how long until a German-equatorial mount
/// needs to flip sides" display. Pure Dart, no location/permission
/// handling here (see observer_location.dart for that).
library;

/// Sidereal rotation rate, degrees per solar hour: the sidereal day
/// (360.98564736629 deg/solar day, IAU 1982) is a hair shorter than the
/// 24h solar day, so Hour Angle advances slightly faster than the clock.
const siderealDegPerSolarHour = 360.98564736629 / 24;

double _normalizeDeg360(double deg) {
  var d = deg % 360.0;
  if (d < 0) d += 360.0;
  return d;
}

/// Greenwich Mean Sidereal Time, in degrees, for a given UTC instant —
/// the IAU 1982 formula (e.g. Meeus, "Astronomical Algorithms" ch. 12;
/// cross-checked against the well-known GMST at J2000.0 epoch,
/// 2000-01-01 12:00 UT = 18h41m50.5s = 280.4606 deg).
double greenwichMeanSiderealTimeDeg(DateTime utc) {
  final jd = utc.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5;
  final d = jd - 2451545.0;
  final t = d / 36525.0;
  final gmst =
      280.46061837 +
      360.98564736629 * d +
      0.000387933 * t * t -
      (t * t * t) / 38710000.0;
  return _normalizeDeg360(gmst);
}

/// Local Sidereal Time, in degrees: Greenwich Mean Sidereal Time plus the
/// observer's east longitude (west longitude is negative).
double localSiderealTimeDeg(DateTime utc, double longitudeDeg) =>
    _normalizeDeg360(greenwichMeanSiderealTimeDeg(utc) + longitudeDeg);

/// Hour Angle, in degrees, normalized to (-180, 180]: 0 at meridian
/// transit, negative before transit (object still rising toward the
/// meridian, east of it), positive after (object past the meridian,
/// west of it — the case that needs a German-equatorial mount's
/// meridian flip to keep tracking).
double hourAngleDeg(double raDeg, DateTime utc, double longitudeDeg) {
  final lst = localSiderealTimeDeg(utc, longitudeDeg);
  var ha = lst - raDeg;
  ha = ha % 360.0;
  if (ha <= -180) ha += 360;
  if (ha > 180) ha -= 360;
  return ha;
}

/// Wall-clock time until the target crosses the meridian (Hour Angle
/// reaches 0), given its current [hourAngleDeg]. Negative means the
/// target already crossed that long ago (a flip may already be needed).
Duration timeToMeridian(double hourAngleDeg) {
  final hours = -hourAngleDeg / siderealDegPerSolarHour;
  return Duration(milliseconds: (hours * 3600000).round());
}
