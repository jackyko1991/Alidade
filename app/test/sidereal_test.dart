// Validates the GMST/LST/Hour Angle math against Meeus's own worked
// example (ch. 12, Example 12.a) rather than trusting the formula
// transcription from memory.

import 'package:flutter_test/flutter_test.dart';
import 'package:alidade/sidereal.dart';

void main() {
  test('GMST at J2000.0 matches the well-known epoch value', () {
    final gmst = greenwichMeanSiderealTimeDeg(DateTime.utc(2000, 1, 1, 12));
    expect(gmst, closeTo(280.46061837, 1e-4));
  });

  test('GMST matches Meeus Example 12.a (1987-04-10 0h UT)', () {
    final gmst = greenwichMeanSiderealTimeDeg(DateTime.utc(1987, 4, 10));
    expect(gmst, closeTo(197.693195, 1e-4));
  });

  test('local sidereal time adds east longitude, wraps at 360', () {
    final utc = DateTime.utc(1987, 4, 10);
    final gmst = greenwichMeanSiderealTimeDeg(utc);
    expect(localSiderealTimeDeg(utc, 0), closeTo(gmst, 1e-9));
    expect(localSiderealTimeDeg(utc, 10), closeTo(gmst + 10, 1e-9));
    expect(localSiderealTimeDeg(utc, -10), closeTo(gmst - 10, 1e-9));
    // West longitude past the point that would wrap negative.
    expect(localSiderealTimeDeg(utc, -200), closeTo(gmst - 200 + 360, 1e-9));
  });

  test('hour angle is 0 when RA equals the local sidereal time', () {
    final utc = DateTime.utc(2026, 6, 15, 3, 30);
    const longitude = -71.06; // Boston-ish, west negative
    final lst = localSiderealTimeDeg(utc, longitude);
    expect(hourAngleDeg(lst, utc, longitude), closeTo(0, 1e-9));
  });

  test('hour angle is negative before transit, positive after', () {
    final utc = DateTime.utc(2026, 6, 15, 3, 30);
    const longitude = -71.06;
    final lst = localSiderealTimeDeg(utc, longitude);
    // A target 10 deg of RA east of the current LST hasn't transited yet.
    expect(hourAngleDeg(lst + 10, utc, longitude), closeTo(-10, 1e-9));
    // A target 10 deg of RA west of the current LST already transited.
    expect(hourAngleDeg(lst - 10, utc, longitude), closeTo(10, 1e-9));
  });

  test('hour angle stays normalized to (-180, 180]', () {
    final utc = DateTime.utc(2026, 1, 1);
    for (var ra = 0.0; ra < 360; ra += 15) {
      final ha = hourAngleDeg(ra, utc, 0);
      expect(ha, inInclusiveRange(-180.0, 180.0));
    }
  });

  test('timeToMeridian is positive before transit, negative after', () {
    expect(timeToMeridian(-15).inMinutes, closeTo(60, 1)); // 15 deg = 1h of HA
    expect(timeToMeridian(15).inMinutes, closeTo(-60, 1));
    expect(timeToMeridian(0).inMinutes, 0);
  });

  test('timeToMeridian accounts for the sidereal-vs-solar rate difference', () {
    // 360 deg of HA is one full sidereal day, which is a few minutes
    // shorter than 24 solar hours - not exactly 24h00m00s.
    final duration = timeToMeridian(-360);
    expect(duration.inSeconds, isNot(24 * 3600));
    expect(duration.inSeconds, closeTo(23 * 3600 + 56 * 60 + 4, 2));
  });
}
