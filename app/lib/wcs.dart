import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Maps sky coordinates to pixel positions for a solved image, using the
/// same TAN (gnomonic) projection + roll convention `tetra3`'s
/// `Solution::pixel_to_world` uses (confirmed against it — see
/// `hint_quaternion` in the spike CLI, which validated this same
/// forward/inverse relationship by reproducing an already-known-correct
/// solve exactly). This is the inverse direction: given a target RA/Dec,
/// where would it land in the image?
class SolvedWcs {
  SolvedWcs({
    required this.centerRaDeg,
    required this.centerDecDeg,
    required this.rollDeg,
    required this.fovDeg,
    required this.imageWidthPx,
    required this.imageHeightPx,
  });

  final double centerRaDeg;
  final double centerDecDeg;
  final double rollDeg;
  final double fovDeg;
  final int imageWidthPx;
  final int imageHeightPx;

  /// Pixel-space radians-per-pixel, from the solved horizontal FOV and
  /// image width — the same pinhole relation `SolveConfig::new` assumes:
  /// f = (width/2) / tan(fov/2), pixel_scale = 1/f.
  double get _pixelScale {
    final fovRad = fovDeg * math.pi / 180;
    final focalLengthPx = (imageWidthPx / 2) / math.tan(fovRad / 2);
    return 1 / focalLengthPx;
  }

  /// Projects (raDeg, decDeg) to top-left pixel coordinates, or null if the
  /// point falls outside the image (or behind the camera).
  Offset? project(double raDeg, double decDeg) {
    final ra0 = centerRaDeg * math.pi / 180;
    final dec0 = centerDecDeg * math.pi / 180;
    final ra = raDeg * math.pi / 180;
    final dec = decDeg * math.pi / 180;
    final theta = rollDeg * math.pi / 180;

    // Forward gnomonic (TAN) projection at the solved center.
    final da = ra - ra0;
    final sinDec = math.sin(dec), cosDec = math.cos(dec);
    final sinDec0 = math.sin(dec0), cosDec0 = math.cos(dec0);
    final cosDa = math.cos(da);
    final denom = sinDec * sinDec0 + cosDec * cosDec0 * cosDa;
    if (denom <= 1e-12) return null; // behind the tangent plane

    final xi = cosDec * math.sin(da) / denom;
    final eta = (sinDec * cosDec0 - cosDec * sinDec0 * cosDa) / denom;

    // Invert the roll rotation: forward was [xi;eta] = R(theta)*[xiCam;etaCam].
    final cosT = math.cos(theta), sinT = math.sin(theta);
    final xiCam = cosT * xi + sinT * eta;
    final etaCam = -sinT * xi + cosT * eta;

    final pixelScale = _pixelScale;
    final xCentered = xiCam / pixelScale;
    final yCentered = etaCam / pixelScale;

    final x = xCentered + imageWidthPx / 2;
    final y = yCentered + imageHeightPx / 2;
    if (x < 0 || x > imageWidthPx || y < 0 || y > imageHeightPx) return null;
    return Offset(x, y);
  }
}
