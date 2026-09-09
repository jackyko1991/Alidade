import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

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

  /// Projects (raDeg, decDeg), never returning null — see [SkyProjection]
  /// for how a point behind the camera or outside the image is reported.
  /// [project] is the clipped convenience form most callers want.
  SkyProjection projectUnclipped(double raDeg, double decDeg) {
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
    // This is exactly the dot product of the target's and the center's
    // unit sky vectors, so acos(denom) is the true angular separation —
    // valid at any separation, not just in front of the tangent plane.
    final denom = sinDec * sinDec0 + cosDec * cosDec0 * cosDa;
    final separationDeg = math.acos(denom.clamp(-1.0, 1.0)) * 180 / math.pi;

    // Numerators of xi/eta (the target's components on the tangent-plane
    // east/north basis) BEFORE dividing by denom. Computing direction from
    // these — never from the divided xi/eta below — matters: for
    // denom < 0 (more than 90 deg away) the divided xi/eta point 180 deg
    // the wrong way, while these numerators still give the true bearing,
    // since dividing by a positive `denom` doesn't change direction and no
    // in-frame point ever has denom <= 0.
    final xiNum = cosDec * math.sin(da);
    final etaNum = sinDec * cosDec0 - cosDec * sinDec0 * cosDa;

    final cosT = math.cos(theta), sinT = math.sin(theta);
    final dxRaw = cosT * xiNum + sinT * etaNum;
    final dyRaw = -sinT * xiNum + cosT * etaNum;
    final rawLength = math.sqrt(dxRaw * dxRaw + dyRaw * dyRaw);
    final direction = rawLength < 1e-12
        ? Offset.zero
        : Offset(dxRaw / rawLength, dyRaw / rawLength);

    if (denom <= 1e-12) {
      return SkyProjection(
        status: SkyProjectionStatus.behindCamera,
        position: null,
        direction: direction,
        separationDeg: separationDeg,
      );
    }

    final xi = xiNum / denom;
    final eta = etaNum / denom;
    final xiCam = cosT * xi + sinT * eta;
    final etaCam = -sinT * xi + cosT * eta;

    final pixelScale = _pixelScale;
    final xCentered = xiCam / pixelScale;
    final yCentered = etaCam / pixelScale;

    final x = xCentered + imageWidthPx / 2;
    final y = yCentered + imageHeightPx / 2;
    final position = Offset(x, y);
    final inBounds = !(x < 0 || x > imageWidthPx || y < 0 || y > imageHeightPx);
    return SkyProjection(
      status: inBounds
          ? SkyProjectionStatus.inFrame
          : SkyProjectionStatus.offFrame,
      position: position,
      direction: direction,
      separationDeg: separationDeg,
    );
  }

  /// Projects (raDeg, decDeg) to top-left pixel coordinates, or null if the
  /// point falls outside the image (or behind the camera).
  Offset? project(double raDeg, double decDeg) {
    final projection = projectUnclipped(raDeg, decDeg);
    return projection.status == SkyProjectionStatus.inFrame
        ? projection.position
        : null;
  }
}

/// Where a point projects relative to the solved frame.
enum SkyProjectionStatus {
  /// Inside the image rect — the same case [SolvedWcs.project] returns
  /// non-null for.
  inFrame,

  /// In front of the camera (the tangent-plane projection is valid) but
  /// outside the image rect.
  offFrame,

  /// More than ~90 degrees from the solved center, where the gnomonic
  /// projection diverges/flips — [position] is meaningless and null, but
  /// [direction] and [separationDeg] are still exact.
  behindCamera,
}

/// The full result of projecting one sky position through a [SolvedWcs],
/// including the cases [SolvedWcs.project] collapses to null: this is what
/// lets an off-frame or behind-camera target still get a "this way" arrow
/// instead of just disappearing.
class SkyProjection {
  const SkyProjection({
    required this.status,
    required this.position,
    required this.direction,
    required this.separationDeg,
  });

  final SkyProjectionStatus status;

  /// Unclipped pixel position. Null iff [status] is [SkyProjectionStatus.behindCamera].
  final Offset? position;

  /// Unit vector in image-pixel space pointing from the image center
  /// toward the target — valid for every [status]. Only [Offset.zero]
  /// in the degenerate case of a target exactly at the center or exactly
  /// antipodal to it (no meaningful direction either way).
  final Offset direction;

  /// True great-circle separation between the solved center and the
  /// target, in degrees, 0..180.
  final double separationDeg;

  bool get isInFrame => status == SkyProjectionStatus.inFrame;
}

/// Where the ray from the center of [imageSize] in unit [direction] exits
/// the image border, inset by [margin] so a glyph drawn there stays fully
/// on-canvas. Null for a zero direction (no meaningful "which way"), or if
/// [margin] is at least half the frame's width or height (nothing to draw
/// inside of).
Offset? edgePointForDirection(
  Offset direction,
  Size imageSize, {
  double margin = 0,
}) {
  if (direction.distanceSquared < 1e-18) return null;
  final center = Offset(imageSize.width / 2, imageSize.height / 2);
  final left = margin;
  final top = margin;
  final right = imageSize.width - margin;
  final bottom = imageSize.height - margin;
  const eps = 1e-12;

  var t = double.infinity;
  if (direction.dx > eps) t = math.min(t, (right - center.dx) / direction.dx);
  if (direction.dx < -eps) t = math.min(t, (left - center.dx) / direction.dx);
  if (direction.dy > eps) t = math.min(t, (bottom - center.dy) / direction.dy);
  if (direction.dy < -eps) t = math.min(t, (top - center.dy) / direction.dy);
  if (!t.isFinite || t <= 0) return null;
  return center + direction * t;
}

/// Rotation (radians) for a glyph authored pointing along +x, so it points
/// along [direction] instead.
double directionAngle(Offset direction) =>
    math.atan2(direction.dy, direction.dx);
