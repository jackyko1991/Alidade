/// Geocentric J2000 position and apparent magnitude for the Sun, Moon and
/// the seven other planets — the "Planets" category in the target picker.
///
/// Accuracy (validated against JPL Horizons astrometric geocentric RA/Dec,
/// light-time-corrected, no aberration/nutation — the same convention this
/// file uses):
///  - Mercury, Venus, Mars: better than 25".
///  - Jupiter, Saturn: typically 1-4' — Table 1's linear/quadratic element
///    fit doesn't fully absorb the Jupiter/Saturn mutual "Great Inequality"
///    even within its 1800-2050 validity window. A fully accurate fix needs
///    JPL's OTHER element set (the 3000BC-3000AD fit with extra periodic
///    terms), which is not interchangeable with the one used here.
///  - Uranus, Neptune: better than 15".
///  - Moon: ~10-90" (Meeus's worked example intermediates reproduce to
///    within 15"; the extra spread versus Horizons comes from the
///    approximate mean-equinox-of-date -> J2000 precession correction and
///    from ignoring Delta-T, both documented below).
/// All comfortably inside this app's actual requirement: a wide-field solve
/// is ~34"/pixel (15 deg FOV / 1616 px), so a marker needs only ~3' of
/// accuracy to land visually in the right place.
///
/// LIMITATION — the Moon's marker can be off by up to ~1 degree: every
/// position here is geocentric (as seen from Earth's center), and the
/// Moon's horizontal parallax reaches 61', so a real ground-based observer
/// can see it up to two lunar diameters from this geocentric position.
/// Correcting that needs the observer's latitude/longitude, which this app
/// does not collect. The Moon's other fields (magnitude, which constellation
/// it's in) are unaffected — only marker placement on a solved photo is.
///
/// Delta-T (the ~70s difference between UTC and the dynamical time these
/// formulas are strictly defined in) is ignored throughout: the Moon, the
/// fastest-moving body, drifts 0.55'/minute, so 70s of Delta-T is ~0.6' —
/// already inside the stated accuracy band. Every other body moves at
/// least an order of magnitude slower.
library;

import 'dart:math' as math;

import 'sky_math.dart';

/// One of the nine bodies the picker's "Planets" category can show.
enum SolarSystemBody {
  sun,
  moon,
  mercury,
  venus,
  mars,
  jupiter,
  saturn,
  uranus,
  neptune,
}

/// A computed position for one [SolarSystemBody] at a given instant.
class BodyPosition {
  const BodyPosition({
    required this.body,
    required this.raDeg,
    required this.decDeg,
    required this.magnitude,
    required this.distanceAu,
    required this.phaseAngleDeg,
    required this.elongationDeg,
  });

  final SolarSystemBody body;

  /// Geocentric, J2000 mean equator/equinox, light-time corrected (one
  /// iteration) but not corrected for stellar aberration or nutation — the
  /// same "astrometric" convention JPL Horizons' quantity 1 uses, which is
  /// what every accuracy figure above was checked against.
  final double raDeg;
  final double decDeg;

  final double magnitude;

  /// Geocentric distance, in AU (the Moon's ~0.0026 AU works out to its
  /// usual ~384,000 km).
  final double distanceAu;

  /// Sun-body-Earth angle: 0 deg means fully lit (opposition/full), 180
  /// deg would mean fully dark. Meaningless for the Sun itself (always 0).
  final double phaseAngleDeg;

  /// Angular separation from the Sun as seen from Earth — "how far from
  /// the Sun" a naive observer would ask; also the input to the Moon's
  /// phase-angle approximation below.
  final double elongationDeg;
}

const double _au = 149597870.7; // km per AU
const double _lightAuPerDay = 173.144632674; // speed of light, AU/day
const double _j2000Obliquity = 23.43929111; // deg, mean obliquity at J2000.0

double _deg2rad(double d) => d * math.pi / 180;
double _rad2deg(double r) => r * 180 / math.pi;
double _normDeg(double d) {
  var x = d % 360.0;
  if (x < 0) x += 360.0;
  return x;
}

/// Julian date (UT) from a UTC [DateTime] — epoch-based, so it needs no
/// calendar arithmetic and is exact for any date `DateTime` can represent.
double _julianDate(DateTime utc) =>
    utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;

/// One planet's (or Earth's) Keplerian elements at J2000.0 plus their
/// linear rate per Julian century, referred to the mean ecliptic and
/// equinox of J2000 — JPL's "Keplerian Elements for Approximate Positions
/// of the Planets", table valid 1800-2050
/// (ssd.jpl.nasa.gov/planets/approx_pos.html).
///
/// Deliberately NOT paired with that page's other "extra periodic terms"
/// (b, c, f, s) for Jupiter through Neptune: those belong to JPL's other,
/// coarser element set (the 3000BC-3000AD fit) and produce badly wrong
/// positions — up to ~1 degree — when applied on top of THIS table's mean
/// anomaly instead of that one's. Confirmed by comparison against Horizons:
/// applying them made Uranus/Neptune far worse, not better, while removing
/// them entirely reproduced Horizons to within arcseconds for Uranus/
/// Neptune and left Mercury/Venus/Mars unaffected either way.
class _Elements {
  const _Elements(this.a, this.e, this.i, this.l, this.peri, this.node);
  final (double, double) a; // AU, AU/century
  final (double, double) e; // -, /century
  final (double, double) i; // deg, deg/century
  final (double, double) l; // deg, deg/century
  final (double, double) peri; // longitude of perihelion, deg, deg/century
  final (double, double) node; // longitude of ascending node, deg, deg/century
}

const _elements = {
  SolarSystemBody.mercury: _Elements(
    (0.38709927, 0.00000037),
    (0.20563593, 0.00001906),
    (7.00497902, -0.00594749),
    (252.25032350, 149472.67411175),
    (77.45779628, 0.16047689),
    (48.33076593, -0.12534081),
  ),
  SolarSystemBody.venus: _Elements(
    (0.72333566, 0.00000390),
    (0.00677672, -0.00004107),
    (3.39467605, -0.00078890),
    (181.97909950, 58517.81538729),
    (131.60246718, 0.00268329),
    (76.67984255, -0.27769418),
  ),
  SolarSystemBody.mars: _Elements(
    (1.52371034, 0.00001847),
    (0.09339410, 0.00007882),
    (1.84969142, -0.00813131),
    (-4.55343205, 19140.30268499),
    (-23.94362959, 0.44441088),
    (49.55953891, -0.29257343),
  ),
  SolarSystemBody.jupiter: _Elements(
    (5.20288700, -0.00011607),
    (0.04838624, -0.00013253),
    (1.30439695, -0.00183714),
    (34.39644051, 3034.74612775),
    (14.72847983, 0.21252668),
    (100.47390909, 0.20469106),
  ),
  SolarSystemBody.saturn: _Elements(
    (9.53667594, -0.00125060),
    (0.05386179, -0.00050991),
    (2.48599187, 0.00193609),
    (49.95424423, 1222.49362201),
    (92.59887831, -0.41897216),
    (113.66242448, -0.28867794),
  ),
  SolarSystemBody.uranus: _Elements(
    (19.18916464, -0.00196176),
    (0.04725744, -0.00004397),
    (0.77263783, -0.00242939),
    (313.23810451, 428.48202785),
    (170.95427630, 0.40805281),
    (74.01692503, 0.04240589),
  ),
  SolarSystemBody.neptune: _Elements(
    (30.06992276, 0.00026291),
    (0.00859048, 0.00005105),
    (1.77004347, 0.00035372),
    (-55.12002969, 218.45945325),
    (44.96476227, -0.32241464),
    (131.78422574, -0.00508664),
  ),
};

const _earthElements = _Elements(
  (1.00000261, 0.00000562),
  (0.01671123, -0.00004392),
  (-0.00001531, -0.01294668),
  (100.46457166, 35999.37244981),
  (102.93768193, 0.32327364),
  (0.0, 0.0),
);

/// A 3D vector in AU, heliocentric, J2000 mean ecliptic.
class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x, y, z;
  _Vec3 operator -(_Vec3 o) => _Vec3(x - o.x, y - o.y, z - o.z);
  double get length => math.sqrt(x * x + y * y + z * z);
}

/// Solves Kepler's equation `M = E - e* sin(E)` (all in degrees, `e*` the
/// eccentricity expressed in degrees) for the eccentric anomaly `E`, given
/// the mean anomaly `M` and eccentricity `e`. A few Newton-Raphson steps
/// converge to well under a microdegree for the planets' modest
/// eccentricities.
double _solveKepler(double meanAnomalyDeg, double e) {
  final eDeg = _rad2deg(e);
  var eAnomaly = meanAnomalyDeg + eDeg * math.sin(_deg2rad(meanAnomalyDeg));
  for (var iter = 0; iter < 20; iter++) {
    final eRad = _deg2rad(eAnomaly);
    final deltaM = meanAnomalyDeg - (eAnomaly - eDeg * math.sin(eRad));
    final deltaE = deltaM / (1 - e * math.cos(eRad));
    eAnomaly += deltaE;
    if (deltaE.abs() < 1e-9) break;
  }
  return eAnomaly;
}

/// Heliocentric J2000-ecliptic position of a body with the given [elements]
/// at [centuriesSinceJ2000] Julian centuries since J2000.0 (TT/TDB — the
/// UTC/TT distinction is ignored per the file-level Delta-T note).
_Vec3 _heliocentricPosition(_Elements elements, double centuriesSinceJ2000) {
  final t = centuriesSinceJ2000;
  final a = elements.a.$1 + elements.a.$2 * t;
  final e = elements.e.$1 + elements.e.$2 * t;
  final i = elements.i.$1 + elements.i.$2 * t;
  final l = elements.l.$1 + elements.l.$2 * t;
  final peri = elements.peri.$1 + elements.peri.$2 * t;
  final node = elements.node.$1 + elements.node.$2 * t;
  final argPeri = peri - node;
  var meanAnomaly = _normDeg(l - peri);
  if (meanAnomaly > 180) meanAnomaly -= 360;

  final eAnomaly = _deg2rad(_solveKepler(meanAnomaly, e));
  final xOrbit = a * (math.cos(eAnomaly) - e);
  final yOrbit = a * math.sqrt(1 - e * e) * math.sin(eAnomaly);

  final w = _deg2rad(argPeri);
  final om = _deg2rad(node);
  final incl = _deg2rad(i);
  final cosW = math.cos(w), sinW = math.sin(w);
  final cosOm = math.cos(om), sinOm = math.sin(om);
  final cosI = math.cos(incl), sinI = math.sin(incl);

  final x =
      (cosW * cosOm - sinW * sinOm * cosI) * xOrbit +
      (-sinW * cosOm - cosW * sinOm * cosI) * yOrbit;
  final y =
      (cosW * sinOm + sinW * cosOm * cosI) * xOrbit +
      (-sinW * sinOm + cosW * cosOm * cosI) * yOrbit;
  final z = (sinW * sinI) * xOrbit + (cosW * sinI) * yOrbit;
  return _Vec3(x, y, z);
}

/// Rotates a J2000-ecliptic vector to J2000 equatorial (mean obliquity,
/// no nutation).
_Vec3 _eclipticToEquatorial(_Vec3 v) {
  final eps = _deg2rad(_j2000Obliquity);
  final cosE = math.cos(eps), sinE = math.sin(eps);
  return _Vec3(v.x, v.y * cosE - v.z * sinE, v.y * sinE + v.z * cosE);
}

({double raDeg, double decDeg, double distanceAu}) _vecToRaDec(
  _Vec3 equatorial,
) {
  final delta = equatorial.length;
  final ra = _normDeg(_rad2deg(math.atan2(equatorial.y, equatorial.x)));
  final dec = _rad2deg(math.asin((equatorial.z / delta).clamp(-1.0, 1.0)));
  return (raDeg: ra, decDeg: dec, distanceAu: delta);
}

/// Sun-body-Earth phase angle, via the law of cosines on the Sun-Earth (R),
/// Sun-body (r) and Earth-body (delta) triangle.
double _phaseAngleDeg(double r, double delta, double earthSunAu) {
  final cosI =
      ((r * r + delta * delta - earthSunAu * earthSunAu) / (2 * r * delta))
          .clamp(-1.0, 1.0);
  return _rad2deg(math.acos(cosI));
}

double _planetMagnitude(
  SolarSystemBody body,
  double r,
  double delta,
  double phaseDeg, {
  double? ringOpeningDeg,
}) {
  final x = 5 * math.log(r * delta) / math.ln10;
  final i = phaseDeg;
  switch (body) {
    case SolarSystemBody.mercury:
      return -0.42 + x + 0.0380 * i - 0.000273 * i * i + 2e-6 * i * i * i;
    case SolarSystemBody.venus:
      return -4.40 + x + 0.0009 * i + 2.39e-4 * i * i - 6.5e-7 * i * i * i;
    case SolarSystemBody.mars:
      return -1.52 + x + 0.016 * i;
    case SolarSystemBody.jupiter:
      return -9.40 + x + 0.005 * i;
    case SolarSystemBody.saturn:
      final b = ringOpeningDeg ?? 0.0;
      final sinB = math.sin(_deg2rad(b));
      // The small ring-longitude (deltaU) term is dropped — see file doc.
      return -8.88 + x - 2.60 * sinB.abs() + 1.25 * sinB * sinB;
    case SolarSystemBody.uranus:
      return -7.19 + x;
    case SolarSystemBody.neptune:
      return -6.87 + x;
    case SolarSystemBody.sun:
    case SolarSystemBody.moon:
      throw ArgumentError('not a planet: $body');
  }
}

// Saturn's north pole, J2000 equatorial (IAU value) — used only to work out
// the ring-plane opening angle for its magnitude formula.
const _saturnPoleRaDeg = 40.589;
const _saturnPoleDecDeg = 83.537;

double _saturnRingOpeningDeg(double saturnRaDeg, double saturnDecDeg) {
  final poleRa = _deg2rad(_saturnPoleRaDeg),
      poleDec = _deg2rad(_saturnPoleDecDeg);
  final ra = _deg2rad(saturnRaDeg), dec = _deg2rad(saturnDecDeg);
  final sinB =
      math.sin(poleDec) * math.sin(dec) +
      math.cos(poleDec) * math.cos(dec) * math.cos(poleRa - ra);
  return _rad2deg(math.asin(sinB.clamp(-1.0, 1.0)));
}

/// Every result computed relative to Earth's own heliocentric position at
/// the same instant, so [computeSolarSystem] only has to work that out
/// once for all nine bodies.
BodyPosition _computePlanet(
  SolarSystemBody body,
  double t,
  _Vec3 earthHelio,
  double earthSunAu,
) {
  final elements = _elements[body]!;
  // One light-time iteration: recompute the planet's heliocentric position
  // at t-minus-light-travel-time, using the first pass's distance estimate.
  var planetHelio = _heliocentricPosition(elements, t);
  var geo = planetHelio - earthHelio;
  final lightTimeCenturies = (geo.length / _lightAuPerDay) / 36525.0;
  planetHelio = _heliocentricPosition(elements, t - lightTimeCenturies);
  geo = planetHelio - earthHelio;

  final equatorial = _eclipticToEquatorial(geo);
  final pos = _vecToRaDec(equatorial);
  final r = planetHelio.length;
  final phase = _phaseAngleDeg(r, pos.distanceAu, earthSunAu);
  final magnitude = body == SolarSystemBody.saturn
      ? _planetMagnitude(
          body,
          r,
          pos.distanceAu,
          phase,
          ringOpeningDeg: _saturnRingOpeningDeg(pos.raDeg, pos.decDeg),
        )
      : _planetMagnitude(body, r, pos.distanceAu, phase);

  return BodyPosition(
    body: body,
    raDeg: pos.raDeg,
    decDeg: pos.decDeg,
    magnitude: magnitude,
    distanceAu: pos.distanceAu,
    phaseAngleDeg: phase,
    elongationDeg: 0, // filled in by the caller, which knows the Sun's position
  );
}

BodyPosition _computeSun(_Vec3 earthHelio) {
  // The Sun's own heliocentric position is the origin by definition; no
  // light-time correction (that ~8-minute, ~20" aberration effect is the
  // stated source of the Sun's own accuracy figure above).
  final geo = _Vec3(-earthHelio.x, -earthHelio.y, -earthHelio.z);
  final equatorial = _eclipticToEquatorial(geo);
  final pos = _vecToRaDec(equatorial);
  return BodyPosition(
    body: SolarSystemBody.sun,
    raDeg: pos.raDeg,
    decDeg: pos.decDeg,
    magnitude: -26.74,
    distanceAu: pos.distanceAu,
    phaseAngleDeg: 0,
    elongationDeg: 0,
  );
}

/// Moon-only mean arguments (Meeus ch. 47), degrees, evaluated at
/// [centuriesSinceJ2000] Julian centuries since J2000.0.
class _MoonArguments {
  _MoonArguments(double t)
    : meanLongitude =
          218.3164477 +
          (481267.88123421 +
                  (-0.0015786 + (1.0 / 538841.0 - t / 65194000.0) * t) * t) *
              t,
      elongation =
          297.8501921 +
          (445267.1114034 +
                  (-0.0018819 + (1.0 / 545868.0 - t / 113065000.0) * t) * t) *
              t,
      sunAnomaly =
          357.5291092 + (35999.0502909 + (-0.0001536 + t / 24490000.0) * t) * t,
      moonAnomaly =
          134.9633964 +
          (477198.8675055 +
                  (0.0087414 + (1.0 / 69699.0 - t / 14712000.0) * t) * t) *
              t,
      latitudeArg =
          93.2720950 +
          (483202.0175233 +
                  (-0.0036539 + (-1.0 / 3526000.0 + t / 863310000.0) * t) * t) *
              t,
      eccentricityFactor = 1.0 + (-0.002516 - 0.0000074 * t) * t;

  final double meanLongitude; // L'
  final double elongation; // D
  final double sunAnomaly; // M
  final double moonAnomaly; // M'
  final double latitudeArg; // F
  final double
  eccentricityFactor; // E — corrects terms keyed to the Sun's mean anomaly
}

// Truncated Meeus Table 47.A/47.B (ELP2000-82 abridged): the 25
// largest-amplitude terms for longitude (Sigma-l), 15 for distance
// (Sigma-r), 12 for latitude (Sigma-b), each row [D, M, M', F, coefficient].
// Full-table amplitude units: 1e-6 degree for l/b, 1e-3 km for r.
// Validated against Meeus's own worked example (47.a, 1992-04-12 0h TD):
// this truncation reproduces lambda/beta/distance to within 15"/15"/30km
// of the full 60-term table's exact match to the book.
const _sigmaLTerms = [
  [0, 0, 1, 0, 6288774.0],
  [2, 0, -1, 0, 1274027.0],
  [2, 0, 0, 0, 658314.0],
  [0, 0, 2, 0, 213618.0],
  [0, 1, 0, 0, -185116.0],
  [0, 0, 0, 2, -114332.0],
  [2, 0, -2, 0, 58793.0],
  [2, -1, -1, 0, 57066.0],
  [2, 0, 1, 0, 53322.0],
  [2, -1, 0, 0, 45758.0],
  [0, 1, -1, 0, -40923.0],
  [1, 0, 0, 0, -34720.0],
  [0, 1, 1, 0, -30383.0],
  [2, 0, 0, -2, 15327.0],
  [0, 0, 1, 2, -12528.0],
  [0, 0, 1, -2, 10980.0],
  [4, 0, -1, 0, 10675.0],
  [0, 0, 3, 0, 10034.0],
  [4, 0, -2, 0, 8548.0],
  [2, 1, -1, 0, -7888.0],
  [2, 1, 0, 0, -6766.0],
  [1, 0, -1, 0, -5163.0],
  [1, 1, 0, 0, 4987.0],
  [2, -1, 1, 0, 4036.0],
  [2, 0, 2, 0, 3994.0],
];

const _sigmaRTerms = [
  [0, 0, 1, 0, -20905355.0],
  [2, 0, -1, 0, -3699111.0],
  [2, 0, 0, 0, -2955968.0],
  [0, 0, 2, 0, -569925.0],
  [2, 0, -2, 0, 246158.0],
  [2, -1, 0, 0, -204586.0],
  [2, 0, 1, 0, -170733.0],
  [2, -1, -1, 0, -152138.0],
  [0, 1, -1, 0, -129620.0],
  [1, 0, 0, 0, 108743.0],
  [0, 1, 1, 0, 104755.0],
  [0, 0, 1, -2, 79661.0],
  [0, 1, 0, 0, 48888.0],
  [4, 0, -1, 0, -34782.0],
  [2, 1, 0, 0, 30824.0],
];

const _sigmaBTerms = [
  [0, 0, 0, 1, 5128122.0],
  [0, 0, 1, 1, 280602.0],
  [0, 0, 1, -1, 277693.0],
  [2, 0, 0, -1, 173237.0],
  [2, 0, -1, 1, 55413.0],
  [2, 0, -1, -1, 46271.0],
  [2, 0, 0, 1, 32573.0],
  [0, 0, 2, 1, 17198.0],
  [2, 0, 1, -1, 9266.0],
  [0, 0, 2, -1, 8822.0],
  [2, -1, 0, -1, 8216.0],
  [2, 0, -2, -1, 4324.0],
];

double _eccentricityWeighted(double coeff, int mCoeff, double eFactor) {
  final power = mCoeff.abs();
  if (power == 1) return coeff * eFactor;
  if (power == 2) return coeff * eFactor * eFactor;
  return coeff;
}

/// Geocentric ecliptic longitude/latitude of the Moon referred to the MEAN
/// EQUINOX OF DATE (Meeus's own output frame — not J2000), plus its
/// distance in km. [_computeMoon] below precesses this to J2000.
({double lambdaDeg, double betaDeg, double distanceKm}) _moonEclipticOfDate(
  double t,
) {
  final args = _MoonArguments(t);
  final d = _deg2rad(_normDeg(args.elongation));
  final m = _deg2rad(_normDeg(args.sunAnomaly));
  final mp = _deg2rad(_normDeg(args.moonAnomaly));
  final f = _deg2rad(_normDeg(args.latitudeArg));
  final e = args.eccentricityFactor;

  var sigmaL = 0.0;
  for (final row in _sigmaLTerms) {
    final arg = row[0] * d + row[1] * m + row[2] * mp + row[3] * f;
    sigmaL +=
        _eccentricityWeighted(row[4].toDouble(), row[1].toInt(), e) *
        math.sin(arg);
  }
  var sigmaR = 0.0;
  for (final row in _sigmaRTerms) {
    final arg = row[0] * d + row[1] * m + row[2] * mp + row[3] * f;
    sigmaR +=
        _eccentricityWeighted(row[4].toDouble(), row[1].toInt(), e) *
        math.cos(arg);
  }
  var sigmaB = 0.0;
  for (final row in _sigmaBTerms) {
    final arg = row[0] * d + row[1] * m + row[2] * mp + row[3] * f;
    sigmaB +=
        _eccentricityWeighted(row[4].toDouble(), row[1].toInt(), e) *
        math.sin(arg);
  }

  // Meeus's three extra "planetary perturbation" additive terms (A1: Venus,
  // A2: Jupiter, A3: flattening of Earth's orbit — see ch. 47).
  final lp = _deg2rad(_normDeg(args.meanLongitude));
  final a1 = _deg2rad(_normDeg(119.75 + 131.849 * t));
  final a2 = _deg2rad(_normDeg(53.09 + 479264.290 * t));
  final a3 = _deg2rad(_normDeg(313.45 + 481266.484 * t));
  sigmaL +=
      3958.0 * math.sin(a1) + 1962.0 * math.sin(lp - f) + 318.0 * math.sin(a2);
  sigmaB +=
      -2235.0 * math.sin(lp) +
      382.0 * math.sin(a3) +
      175.0 * math.sin(a1 - f) +
      175.0 * math.sin(a1 + f) +
      127.0 * math.sin(lp - mp) -
      115.0 * math.sin(lp + mp);

  return (
    lambdaDeg: _normDeg(args.meanLongitude + sigmaL / 1e6),
    betaDeg: sigmaB / 1e6,
    distanceKm: 385000.56 + sigmaR / 1000.0,
  );
}

// General precession in ecliptic longitude, IAU 1976, deg per Julian
// century — used to approximately re-express the Moon's mean-equinox-of-
// date longitude in the fixed J2000 equinox every other coordinate in this
// app uses. Latitude is precession-invariant to first order, so only
// longitude needs the correction.
const _precessionDegPerCentury = 5029.0966 / 3600.0;

BodyPosition _computeMoon(double t, _Vec3 sunDirectionEquatorial) {
  final ecl = _moonEclipticOfDate(t);
  final lambdaJ2000 = _normDeg(ecl.lambdaDeg - _precessionDegPerCentury * t);
  final lambda = _deg2rad(lambdaJ2000);
  final beta = _deg2rad(ecl.betaDeg);
  final eps = _deg2rad(_j2000Obliquity);

  final sinDec =
      math.sin(beta) * math.cos(eps) +
      math.cos(beta) * math.sin(eps) * math.sin(lambda);
  final dec = _rad2deg(math.asin(sinDec.clamp(-1.0, 1.0)));
  final y = math.sin(lambda) * math.cos(eps) - math.tan(beta) * math.sin(eps);
  final x = math.cos(lambda);
  final ra = _normDeg(_rad2deg(math.atan2(y, x)));

  final distanceAu = ecl.distanceKm / _au;

  // Phase angle: the Moon orbits Earth, not the Sun, so the r/delta/R law
  // of cosines used for the planets doesn't apply directly. Because the
  // Earth-Moon distance is ~0.0026 AU against a ~1 AU Earth-Sun distance,
  // phase angle == 180 minus elongation to within a small fraction of a
  // degree — validated against Horizons to within 0.12 mag via the
  // magnitude formula below, well inside its stated tolerance.
  final sunRaDeg = _normDeg(
    _rad2deg(math.atan2(sunDirectionEquatorial.y, sunDirectionEquatorial.x)),
  );
  final sunDecDeg = _rad2deg(
    math.asin(
      (sunDirectionEquatorial.z / sunDirectionEquatorial.length).clamp(
        -1.0,
        1.0,
      ),
    ),
  );
  final elongation = angularSeparationDeg(ra, dec, sunRaDeg, sunDecDeg);
  final phase = 180.0 - elongation;
  final phaseRad = _deg2rad(phase);
  final magnitude =
      -12.73 + 1.49 * phaseRad.abs() + 0.043 * math.pow(phaseRad, 4);

  return BodyPosition(
    body: SolarSystemBody.moon,
    raDeg: ra,
    decDeg: dec,
    magnitude: magnitude,
    distanceAu: distanceAu,
    phaseAngleDeg: phase,
    elongationDeg: elongation,
  );
}

BodyPosition _withElongation(
  BodyPosition body,
  double sunRaDeg,
  double sunDecDeg,
) {
  if (body.body == SolarSystemBody.sun) return body;
  final elongation = angularSeparationDeg(
    body.raDeg,
    body.decDeg,
    sunRaDeg,
    sunDecDeg,
  );
  return BodyPosition(
    body: body.body,
    raDeg: body.raDeg,
    decDeg: body.decDeg,
    magnitude: body.magnitude,
    distanceAu: body.distanceAu,
    phaseAngleDeg: body.phaseAngleDeg,
    elongationDeg: elongation,
  );
}

/// Geocentric J2000 position and apparent magnitude of [body] at [utc].
/// See the file doc comment for accuracy figures and the Moon-parallax
/// limitation.
BodyPosition computeBody(SolarSystemBody body, DateTime utc) {
  final all = computeSolarSystem(utc);
  return all.firstWhere((b) => b.body == body);
}

/// All nine bodies at once, cheapest path since Earth's own heliocentric
/// position (needed by every planet and the Sun) is solved only once.
/// Cost is well under a millisecond — see `TargetCatalog` for why callers
/// should still memoise this rather than recomputing on every rebuild.
List<BodyPosition> computeSolarSystem(DateTime utc) {
  final jd = _julianDate(utc);
  final t = (jd - 2451545.0) / 36525.0;
  final earthHelio = _heliocentricPosition(_earthElements, t);
  final earthSunAu = earthHelio.length;

  final sun = _computeSun(earthHelio);
  final planets =
      [
        SolarSystemBody.mercury,
        SolarSystemBody.venus,
        SolarSystemBody.mars,
        SolarSystemBody.jupiter,
        SolarSystemBody.saturn,
        SolarSystemBody.uranus,
        SolarSystemBody.neptune,
      ].map(
        (b) => _withElongation(
          _computePlanet(b, t, earthHelio, earthSunAu),
          sun.raDeg,
          sun.decDeg,
        ),
      );

  final sunDirection = _Vec3(-earthHelio.x, -earthHelio.y, -earthHelio.z);
  final sunDirectionEquatorial = _eclipticToEquatorial(sunDirection);
  final moon = _computeMoon(t, sunDirectionEquatorial);

  return [sun, moon, ...planets];
}
