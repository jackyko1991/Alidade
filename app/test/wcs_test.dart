// Proves the named-star projection actually draws where expected when a
// star *is* in frame — the two real reference photos (Dumbbell, Veil) don't
// exercise this at all, since neither happens to contain any of the 67
// bundled named stars (nearest is Deneb, 11-18° away, well outside either
// frame). Without this test, "the feature works" would rest only on the
// math being independently validated against tetra3's world_to_pixel (see
// the project plan) — real, but not the same as proving the Dart code path
// that actually runs in the app does the right thing end to end.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:alidade/wcs.dart';

// Independent great-circle separation, so the expected separationDeg in
// the tests below is derived, not a magic constant copied from the code
// under test.
double _haversineDeg(double ra1, double dec1, double ra2, double dec2) {
  final r1 = dec1 * math.pi / 180, r2 = dec2 * math.pi / 180;
  final dRa = (ra1 - ra2) * math.pi / 180;
  final cosSep =
      math.sin(r1) * math.sin(r2) + math.cos(r1) * math.cos(r2) * math.cos(dRa);
  return math.acos(cosSep.clamp(-1.0, 1.0)) * 180 / math.pi;
}

void main() {
  test('a star at the frame center projects to the image center', () {
    final wcs = SolvedWcs(
      centerRaDeg: 310.48886,
      centerDecDeg: 34.17502,
      rollDeg: 90.257,
      fovDeg: 15.208,
      imageWidthPx: 1616,
      imageHeightPx: 1080,
    );

    final pos = wcs.project(310.48886, 34.17502);
    expect(pos, isNotNull);
    expect(pos!.dx, closeTo(1616 / 2, 0.5));
    expect(pos.dy, closeTo(1080 / 2, 0.5));
  });

  test('Deneb, hypothetically centered in frame, projects inside bounds', () {
    // Same solve geometry as the real Veil photo, but re-centered on Deneb
    // (310.35799, 45.28035) instead of the Veil's actual center — this is
    // exactly what would happen if the user photographed Deneb with the
    // same lens/roll instead of the Veil complex.
    const denebRa = 310.35799;
    const denebDec = 45.28035;
    final wcs = SolvedWcs(
      centerRaDeg: denebRa,
      centerDecDeg: denebDec,
      rollDeg: 90.257,
      fovDeg: 15.208,
      imageWidthPx: 1616,
      imageHeightPx: 1080,
    );

    final pos = wcs.project(denebRa, denebDec);
    expect(pos, isNotNull, reason: 'Deneb should project to the frame center');
    expect(pos!.dx, greaterThanOrEqualTo(0));
    expect(pos.dx, lessThanOrEqualTo(1616));
    expect(pos.dy, greaterThanOrEqualTo(0));
    expect(pos.dy, lessThanOrEqualTo(1080));
  });

  test('the real Veil solve does NOT place Deneb inside the frame', () {
    // Confirms, in code (not just by hand-calculation), the exact claim
    // made to the user: Deneb is ~11 deg from the Veil frame's center,
    // outside its ~7.6 deg half-FOV radius, so it correctly projects
    // outside the image bounds (or returns null) for this real solve.
    final wcs = SolvedWcs(
      centerRaDeg: 310.48886,
      centerDecDeg: 34.17502,
      rollDeg: 90.257,
      fovDeg: 15.208,
      imageWidthPx: 1616,
      imageHeightPx: 1080,
    );

    const denebRa = 310.35799;
    const denebDec = 45.28035;
    final pos = wcs.project(denebRa, denebDec);
    final outsideBounds =
        pos == null ||
        pos.dx < 0 ||
        pos.dx > 1616 ||
        pos.dy < 0 ||
        pos.dy > 1080;
    expect(outsideBounds, isTrue);
  });

  group('projectUnclipped', () {
    test('agrees with project() for a target inside the frame', () {
      const denebRa = 310.35799;
      const denebDec = 45.28035;
      final wcs = SolvedWcs(
        centerRaDeg: denebRa,
        centerDecDeg: denebDec,
        rollDeg: 90.257,
        fovDeg: 15.208,
        imageWidthPx: 1616,
        imageHeightPx: 1080,
      );

      final projection = wcs.projectUnclipped(denebRa, denebDec);
      expect(projection.status, SkyProjectionStatus.inFrame);
      expect(projection.position!.dx, closeTo(1616 / 2, 0.5));
      expect(projection.position!.dy, closeTo(1080 / 2, 0.5));
      expect(projection.separationDeg, closeTo(0, 1e-6));
    });

    test(
      'reports offFrame with a finite position where project() returns null',
      () {
        final wcs = SolvedWcs(
          centerRaDeg: 310.48886,
          centerDecDeg: 34.17502,
          rollDeg: 90.257,
          fovDeg: 15.208,
          imageWidthPx: 1616,
          imageHeightPx: 1080,
        );
        const denebRa = 310.35799;
        const denebDec = 45.28035;

        expect(wcs.project(denebRa, denebDec), isNull);
        final projection = wcs.projectUnclipped(denebRa, denebDec);
        expect(projection.status, SkyProjectionStatus.offFrame);
        expect(projection.position, isNotNull);
        expect(projection.position!.dx.isFinite, isTrue);
        expect(projection.position!.dy.isFinite, isTrue);
        expect(projection.direction.distance, closeTo(1, 1e-9));
        final expectedSep = _haversineDeg(
          310.48886,
          34.17502,
          denebRa,
          denebDec,
        );
        expect(projection.separationDeg, closeTo(expectedSep, 1e-6));
        expect(projection.separationDeg, greaterThan(15.208 / 2));
      },
    );

    test('a target 100 deg away is behindCamera but still yields a usable direction', () {
      // This is the test that fails if the direction were computed from
      // the divided xi/eta instead of their pre-division numerators: that
      // would come out (-1, 0) here, 180 deg backwards.
      final wcs = SolvedWcs(
        centerRaDeg: 0,
        centerDecDeg: 0,
        rollDeg: 0,
        fovDeg: 15.208,
        imageWidthPx: 1616,
        imageHeightPx: 1080,
      );
      final projection = wcs.projectUnclipped(100, 0);
      expect(projection.status, SkyProjectionStatus.behindCamera);
      expect(projection.position, isNull);
      expect(projection.separationDeg, closeTo(100, 1e-9));
      expect(projection.direction.dx, closeTo(1, 1e-9));
      expect(projection.direction.dy, closeTo(0, 1e-9));
    });

    test(
      'direction is continuous crossing the 90 deg behind-camera boundary',
      () {
        final wcs = SolvedWcs(
          centerRaDeg: 0,
          centerDecDeg: 0,
          rollDeg: 0,
          fovDeg: 15.208,
          imageWidthPx: 1616,
          imageHeightPx: 1080,
        );
        final inFront = wcs.projectUnclipped(80, 0).direction;
        final behind = wcs.projectUnclipped(100, 0).direction;
        final dot = inFront.dx * behind.dx + inFront.dy * behind.dy;
        expect(dot, greaterThan(0.99));
      },
    );

    test('an exactly antipodal target has no meaningful direction', () {
      final wcs = SolvedWcs(
        centerRaDeg: 0,
        centerDecDeg: 0,
        rollDeg: 0,
        fovDeg: 15.208,
        imageWidthPx: 1616,
        imageHeightPx: 1080,
      );
      final projection = wcs.projectUnclipped(180, 0);
      expect(projection.status, SkyProjectionStatus.behindCamera);
      expect(projection.separationDeg, closeTo(180, 1e-6));
      expect(projection.direction, Offset.zero);
    });

    test('roll rotates the off-frame direction', () {
      const denebRa = 310.35799;
      const denebDec = 45.28035;
      final rolled = SolvedWcs(
        centerRaDeg: 310.48886,
        centerDecDeg: 34.17502,
        rollDeg: 90.257,
        fovDeg: 15.208,
        imageWidthPx: 1616,
        imageHeightPx: 1080,
      ).projectUnclipped(denebRa, denebDec).direction;
      final unrolled = SolvedWcs(
        centerRaDeg: 310.48886,
        centerDecDeg: 34.17502,
        rollDeg: 0.257,
        fovDeg: 15.208,
        imageWidthPx: 1616,
        imageHeightPx: 1080,
      ).projectUnclipped(denebRa, denebDec).direction;
      final dot = rolled.dx * unrolled.dx + rolled.dy * unrolled.dy;
      expect(dot, closeTo(0, 1e-6));
    });
  });

  group('edgePointForDirection', () {
    const size = Size(1616, 1080);

    test('exits the right border for a due-east direction', () {
      final edge = edgePointForDirection(const Offset(1, 0), size);
      expect(edge!.dx, closeTo(1616, 1e-9));
      expect(edge.dy, closeTo(540, 1e-9));
    });

    test('exits the top border for a steep upward direction', () {
      const direction = Offset(0.1, -1);
      final normalized = direction / direction.distance;
      final edge = edgePointForDirection(normalized, size);
      expect(edge!.dy, closeTo(0, 1e-9));
      // t = 540 / 0.99504..., x = 808 + t * 0.09950...
      final t = 540 / normalized.dy.abs();
      expect(edge.dx, closeTo(808 + t * normalized.dx, 1e-6));
    });

    test('an exact diagonal lands on the corner', () {
      const square = Size(1000, 1000);
      final direction = const Offset(1, 1) / math.sqrt(2);
      final edge = edgePointForDirection(direction, square);
      expect(edge!.dx, closeTo(1000, 1e-9));
      expect(edge.dy, closeTo(1000, 1e-9));
    });

    test('margin insets the exit point', () {
      final edge = edgePointForDirection(const Offset(1, 0), size, margin: 24);
      expect(edge!.dx, closeTo(1592, 1e-9));
      expect(edge.dy, closeTo(540, 1e-9));
    });

    test('returns null for a zero direction', () {
      expect(edgePointForDirection(Offset.zero, size), isNull);
    });

    test('returns null when the margin exceeds half the frame', () {
      expect(
        edgePointForDirection(
          const Offset(1, 0),
          const Size(100, 100),
          margin: 60,
        ),
        isNull,
      );
    });
  });

  group('directionAngle', () {
    test('is -pi/2 for a due-north direction', () {
      expect(directionAngle(const Offset(0, -1)), closeTo(-math.pi / 2, 1e-12));
    });

    test('is 0 for a due-east direction', () {
      expect(directionAngle(const Offset(1, 0)), closeTo(0, 1e-12));
    });
  });
}
