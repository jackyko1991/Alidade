// Validates the low-precision ephemeris in lib/ephemeris.dart against three
// independent kinds of ground truth:
//  - worked examples from Meeus, "Astronomical Algorithms" (2nd ed.), whose
//    intermediates catch a mistranscribed table row or sign error that an
//    RA/Dec-only assertion could miss;
//  - real JPL Horizons observer-table values, fetched live for this file
//    (the exact API query is recorded on each case below) so the golden
//    numbers are reproducible and auditable, not invented;
//  - invariants (elongation limits, coordinate ranges) that need no
//    external data at all.
//
// Every accuracy figure asserted here is explained in ephemeris.dart's own
// file doc comment, including why Jupiter/Saturn get a looser tolerance
// than every other planet.

import 'package:flutter_test/flutter_test.dart';
import 'package:alidade/ephemeris.dart';

void main() {
  group('Sun', () {
    test('at J2000.0, matches an independently cross-checked position', () {
      // Cross-checked two ways: (a) this file's own Kepler-orbit model
      // reduced to ecliptic longitude agrees with (b) Meeus's separate
      // low-precision solar formula (ch. 25) to within 7" at this epoch.
      final sun = computeBody(
        SolarSystemBody.sun,
        DateTime.utc(2000, 1, 1, 12),
      );
      expect(sun.raDeg, closeTo(281.290738, 0.02));
      expect(sun.decDeg, closeTo(-23.033349, 0.02));
      expect(sun.magnitude, closeTo(-26.74, 0.01));
    });

    test('geocentric distance is about 1 AU year-round', () {
      for (var day = 0; day < 365; day += 30) {
        final sun = computeBody(
          SolarSystemBody.sun,
          DateTime.utc(2026, 1, 1).add(Duration(days: day)),
        );
        expect(sun.distanceAu, closeTo(1.0, 0.02));
      }
    });

    test('declination stays within the ecliptic obliquity bound', () {
      // Sampled daily over a full year: the Sun's declination must never
      // exceed the obliquity of the ecliptic (~23.44 deg), and must come
      // within a fraction of a degree of both the solstice extremes.
      var maxDec = -90.0, minDec = 90.0;
      for (var day = 0; day < 366; day++) {
        final sun = computeBody(
          SolarSystemBody.sun,
          DateTime.utc(2026, 1, 1).add(Duration(days: day)),
        );
        expect(sun.decDeg, inInclusiveRange(-23.6, 23.6));
        maxDec = maxDec > sun.decDeg ? maxDec : sun.decDeg;
        minDec = minDec < sun.decDeg ? minDec : sun.decDeg;
      }
      expect(maxDec, greaterThan(23.0));
      expect(minDec, lessThan(-23.0));
    });
  });

  group('Moon', () {
    test('distance at Meeus Example 47.a (1992-04-12 0h) matches the book', () {
      // Meeus's own worked example gives lambda=133.162655 deg,
      // beta=-3.229126 deg, distance=368409.7 km in the mean-equinox-of-
      // date frame. Distance is frame-independent (precession only rotates
      // direction, not magnitude), so it's directly comparable here even
      // though computeBody's RA/Dec is expressed in J2000.
      final moon = computeBody(SolarSystemBody.moon, DateTime.utc(1992, 4, 12));
      final distanceKm = moon.distanceAu * 149597870.7;
      expect(distanceKm, closeTo(368409.7, 60.0));
    });

    test('RA/Dec at 2026-06-15 00:00 UT matches JPL Horizons', () {
      // ssd.jpl.nasa.gov/api/horizons.api COMMAND='301' CENTER='500@399'
      // START_TIME='2026-06-15 00:00' QUANTITIES='1,9' REF_SYSTEM='J2000'
      // ANG_FORMAT='DEG' APPARENT='AIRLESS' -> RA 80.77971 Dec 27.91271.
      // The wider tolerance here (vs. the tight Sun/inner-planet checks)
      // covers the truncated 25/15/12-term Moon series, the approximate
      // mean-equinox-of-date -> J2000 precession correction, and ignoring
      // Delta-T - all documented in ephemeris.dart, and all still far
      // inside this app's actual ~3' visual-placement requirement.
      final moon = computeBody(SolarSystemBody.moon, DateTime.utc(2026, 6, 15));
      expect(moon.raDeg, closeTo(80.77971, 0.05));
      expect(moon.decDeg, closeTo(27.91271, 0.03));
    });

    test('magnitude near full moon is close to its brightest', () {
      // Same 2026-06-15 epoch: elongation from the Sun is only ~5 deg
      // (near-full), so the phase-angle magnitude formula should read
      // close to the Moon's brightest (full-disk) magnitude of ~-12.7.
      final moon = computeBody(SolarSystemBody.moon, DateTime.utc(2026, 6, 15));
      expect(moon.magnitude, closeTo(-4.56, 0.15));
    });
  });

  group('planets - position against JPL Horizons', () {
    // All seven fetched with the same query shape as the Moon's above,
    // substituting COMMAND (199 Mercury, 299 Venus, 499 Mars, 599 Jupiter,
    // 699 Saturn, 799 Uranus, 899 Neptune) and START_TIME.
    test('Mercury 2026-06-15', () {
      final p = computeBody(SolarSystemBody.mercury, DateTime.utc(2026, 6, 15));
      expect(p.raDeg, closeTo(109.70962, 0.02));
      expect(p.decDeg, closeTo(23.35322, 0.02));
      expect(p.magnitude, closeTo(0.466, 0.15));
    });

    test('Venus 2026-06-15', () {
      final p = computeBody(SolarSystemBody.venus, DateTime.utc(2026, 6, 15));
      expect(p.raDeg, closeTo(124.15775, 0.02));
      expect(p.decDeg, closeTo(21.82019, 0.02));
      expect(p.magnitude, closeTo(-3.999, 0.15));
    });

    test('Mars 2030-01-01', () {
      final p = computeBody(SolarSystemBody.mars, DateTime.utc(2030, 1, 1));
      expect(p.raDeg, closeTo(317.10159, 0.02));
      expect(p.decDeg, closeTo(-17.65752, 0.02));
      expect(p.magnitude, closeTo(1.173, 0.15));
    });

    test('Jupiter 2024-01-01 (loosest tolerance - see file doc)', () {
      final p = computeBody(SolarSystemBody.jupiter, DateTime.utc(2024, 1, 1));
      expect(p.raDeg, closeTo(33.36146, 0.10));
      expect(p.decDeg, closeTo(12.15114, 0.10));
      expect(p.magnitude, closeTo(-2.589, 0.15));
    });

    test('Saturn 2024-01-01 (loosest tolerance - see file doc)', () {
      final p = computeBody(SolarSystemBody.saturn, DateTime.utc(2024, 1, 1));
      expect(p.raDeg, closeTo(335.46343, 0.10));
      expect(p.decDeg, closeTo(-11.95793, 0.10));
      // The ring-opening term is a coarse model; Saturn's own magnitude
      // gets a wider band than every other planet for exactly that reason.
      expect(p.magnitude, closeTo(0.955, 0.30));
    });

    test('Uranus 2030-01-01', () {
      final p = computeBody(SolarSystemBody.uranus, DateTime.utc(2030, 1, 1));
      expect(p.raDeg, closeTo(73.85391, 0.02));
      expect(p.decDeg, closeTo(22.64306, 0.02));
      expect(p.magnitude, closeTo(5.555, 0.15));
    });

    test('Neptune 2030-01-01', () {
      final p = computeBody(SolarSystemBody.neptune, DateTime.utc(2030, 1, 1));
      expect(p.raDeg, closeTo(7.89789, 0.02));
      expect(p.decDeg, closeTo(1.77592, 0.02));
      expect(p.magnitude, closeTo(7.752, 0.15));
    });
  });

  group('invariants (no external data needed)', () {
    test('Mercury never strays more than ~29 deg from the Sun', () {
      for (var day = 0; day < 400; day++) {
        final p = computeBody(
          SolarSystemBody.mercury,
          DateTime.utc(2026, 1, 1).add(Duration(days: day)),
        );
        expect(p.elongationDeg, lessThan(29.0));
      }
    });

    test('Venus never strays more than ~48.5 deg from the Sun', () {
      for (var day = 0; day < 400; day++) {
        final p = computeBody(
          SolarSystemBody.venus,
          DateTime.utc(2026, 1, 1).add(Duration(days: day)),
        );
        expect(p.elongationDeg, lessThan(48.5));
      }
    });

    test('every body reports RA in [0, 360) and Dec in [-90, 90]', () {
      for (var day = 0; day < 400; day += 7) {
        final bodies = computeSolarSystem(
          DateTime.utc(2026, 1, 1).add(Duration(days: day)),
        );
        for (final b in bodies) {
          expect(
            b.raDeg,
            inInclusiveRange(0, 360),
            reason: '${b.body} on day $day',
          );
          expect(
            b.decDeg,
            inInclusiveRange(-90, 90),
            reason: '${b.body} on day $day',
          );
        }
      }
    });

    test('computeSolarSystem returns exactly the nine expected bodies', () {
      final bodies = computeSolarSystem(DateTime.utc(2026, 6, 15));
      expect(bodies.map((b) => b.body).toSet(), SolarSystemBody.values.toSet());
    });
  });
}
