// Proves the named-star projection actually draws where expected when a
// star *is* in frame — the two real reference photos (Dumbbell, Veil) don't
// exercise this at all, since neither happens to contain any of the 67
// bundled named stars (nearest is Deneb, 11-18° away, well outside either
// frame). Without this test, "the feature works" would rest only on the
// math being independently validated against tetra3's world_to_pixel (see
// the project plan) — real, but not the same as proving the Dart code path
// that actually runs in the app does the right thing end to end.

import 'package:flutter_test/flutter_test.dart';
import 'package:alidade/wcs.dart';

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
}
