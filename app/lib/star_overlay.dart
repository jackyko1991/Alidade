import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'wcs.dart';

/// Displays [imageBytes] with three overlay layers, scaled to however large
/// the image ends up being rendered:
///
/// - [matchedX]/[matchedY]: every star `tetra3` matched during solving
///   (small green circles, unlabeled — there are usually dozens of these
///   and almost none are bright enough to have a common name).
/// - [namedStars]: bright named stars (Deneb, Vega, ...) projected through
///   the solved WCS and labeled, independent of whether the solver's small
///   matched-verification set happened to include them — it often doesn't,
///   since bright named stars are commonly saturated/filtered out of that
///   set even when clearly in frame.
/// - [target]: the one object the user chose before solving, if any —
///   a red star marker when it's in frame, a red edge arrow pointing
///   toward it when it isn't. See [TargetMarker].
class StarOverlayImage extends StatefulWidget {
  const StarOverlayImage({
    super.key,
    required this.imageBytes,
    required this.matchedX,
    required this.matchedY,
    this.namedStars = const [],
    this.constellationLines = const [],
    this.target,
    this.overrideColor,
    this.height = 260,
  });

  final Uint8List imageBytes;
  final List<double> matchedX;
  final List<double> matchedY;
  final List<NamedStarPosition> namedStars;
  // Each inner list is one polyline (a projected constellation line pattern,
  // or one of its disconnected pieces): consecutive points are connected by
  // a straight segment, a null entry means that point fell outside the
  // frame (or behind the camera) and breaks the line rather than being
  // drawn to/from.
  final List<List<Offset?>> constellationLines;
  final TargetMarker? target;
  // When set (night mode), every marker draws in this one color instead of
  // its own green/gold/blue — keeps the whole screen to a single red so
  // night vision adaptation isn't undone by an unrelated bright color.
  final Color? overrideColor;
  final double height;

  @override
  State<StarOverlayImage> createState() => _StarOverlayImageState();
}

class _StarOverlayImageState extends State<StarOverlayImage> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant StarOverlayImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A decoded `ui.Image` owns native/GPU memory that Flutter's own image
    // cache doesn't track (that cache only covers images loaded through an
    // `ImageProvider`, not a manual `instantiateImageCodec` decode like
    // this one) — re-decoding on every rebuild without disposing the
    // previous image leaked a GPU texture per setState and crashed the app
    // natively after enough solves/history loads (Impeller
    // "ErrorOutOfPoolMemory" followed by a SIGSEGV, confirmed on-device).
    // Only re-decode when the bytes actually changed, and dispose the old
    // image once the new one is ready.
    if (!identical(oldWidget.imageBytes, widget.imageBytes)) {
      _decode();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final bytes = widget.imageBytes;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted || !identical(widget.imageBytes, bytes)) {
      frame.image.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = frame.image);
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: widget.height,
        width: double.infinity,
        // Letterbox background: portrait photos no longer get cropped
        // to the box's width (BoxFit.contain shows the whole image,
        // padding the empty sides/top-bottom instead of cutting content).
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: image.width.toDouble(),
            height: image.height.toDouble(),
            child: CustomPaint(
              foregroundPainter: _StarPainter(
                widget.matchedX,
                widget.matchedY,
                widget.namedStars,
                widget.constellationLines,
                widget.target,
                widget.overrideColor,
              ),
              child: RawImage(image: image, fit: BoxFit.fill),
            ),
          ),
        ),
      ),
    );
  }
}

class NamedStarPosition {
  const NamedStarPosition(this.x, this.y, this.name);

  final double x;
  final double y;
  final String name;
}

/// Where the user's chosen pre-solve target landed in a solved image —
/// built by projecting it through the solve's [SolvedWcs] (see
/// `SolvedWcs.projectUnclipped`). [position] and [direction] are already in
/// native image-pixel space, exactly like [NamedStarPosition]; this class
/// just also carries what [SolvedWcs.projectUnclipped] knows about targets
/// outside the frame, which a plain x/y pair can't represent.
class TargetMarker {
  const TargetMarker({
    required this.name,
    required this.status,
    required this.position,
    required this.direction,
    required this.separationDeg,
  });

  final String name;
  final SkyProjectionStatus status;

  /// Null iff [status] is [SkyProjectionStatus.behindCamera].
  final Offset? position;

  /// Unit vector, image-pixel space, toward the target from the image
  /// center. [Offset.zero] only when there's no meaningful direction at
  /// all (the target is exactly at the center or exactly antipodal).
  final Offset direction;
  final double separationDeg;

  bool get isInFrame => status == SkyProjectionStatus.inFrame;

  @override
  bool operator ==(Object other) =>
      other is TargetMarker &&
      other.name == name &&
      other.status == status &&
      other.position == position &&
      other.direction == direction &&
      other.separationDeg == separationDeg;

  @override
  int get hashCode =>
      Object.hash(name, status, position, direction, separationDeg);
}

/// Deliberately outside the app's existing palette — matched stars are
/// green (0xFF33E07A), named stars gold (0xFFDBA84E), constellation lines
/// blue (0xFF5C8AC9), and the app's own seed color is that same gold.
/// Nothing else in normal mode is red, so the target marker reads
/// unambiguously as "the one thing you asked for". In night mode every
/// marker becomes this same dim red via [StarOverlayImage.overrideColor];
/// the target then stays distinguishable from the rest by shape and
/// weight alone (see `_StarPainter._paintTarget`), not by color.
const targetMarkerColor = Color(0xFFFF3B30);

/// Vertices of a 5-point star centered on [center], first vertex straight
/// up. A plain point list (not a `Path`) so the geometry is unit-testable
/// without a canvas.
List<Offset> starVertices(
  Offset center,
  double outerRadius,
  double innerRadius,
) {
  final points = <Offset>[];
  for (var i = 0; i < 10; i++) {
    final radius = i.isEven ? outerRadius : innerRadius;
    final angle = -math.pi / 2 + i * math.pi / 5;
    points.add(
      center + Offset(radius * math.cos(angle), radius * math.sin(angle)),
    );
  }
  return points;
}

/// A closed 5-point star path, inner/outer radius ratio 1/phi^2
/// (`0.381966...`, the pentagram's own ratio) so it reads as a classic
/// star rather than a spiky asterisk.
Path targetStarPath(Offset center, double outerRadius) {
  final path = Path();
  final vertices = starVertices(center, outerRadius, outerRadius * 0.381966);
  path.addPolygon(vertices, true);
  return path;
}

class _StarPainter extends CustomPainter {
  _StarPainter(
    this.matchedX,
    this.matchedY,
    this.namedStars,
    this.constellationLines,
    this.target,
    this.overrideColor,
  );

  final List<double> matchedX;
  final List<double> matchedY;
  final List<NamedStarPosition> namedStars;
  final List<List<Offset?>> constellationLines;
  final TargetMarker? target;
  final Color? overrideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final lineColor = overrideColor ?? const Color(0xFF5C8AC9);
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: overrideColor != null ? 0.7 : 0.6)
      ..style = PaintingStyle.stroke
      // Was width/400 — reported as too thin to read at a glance; a
      // constellation line is a broad pattern cue, not a precise position
      // marker like the star circles, so it can afford to be much bolder.
      ..strokeWidth = size.width / 150;
    for (final polyline in constellationLines) {
      for (var i = 0; i + 1 < polyline.length; i++) {
        final a = polyline[i];
        final b = polyline[i + 1];
        if (a == null || b == null) continue;
        canvas.drawLine(a, b, linePaint);
      }
    }

    final matchedPaint = Paint()
      ..color = overrideColor ?? const Color(0xFF33E07A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width / 220;
    final matchedRadius = size.width / 110;

    for (var i = 0; i < matchedX.length && i < matchedY.length; i++) {
      canvas.drawCircle(
        Offset(matchedX[i], matchedY[i]),
        matchedRadius,
        matchedPaint,
      );
    }

    final namedColor = overrideColor ?? const Color(0xFFDBA84E);
    final namedPaint = Paint()
      ..color = namedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width / 100;
    final namedRadius = size.width / 45;
    // Bigger than a naive "size.width/N" would suggest: this canvas is in
    // the image's *native* pixel space (e.g. 1080px for a portrait phone
    // photo), which `FittedBox` then downscales to fit a fixed ~320dp
    // preview box — for a portrait image that scale-down is much more
    // aggressive than for landscape, since the box height is fixed but the
    // displayed width shrinks a lot. A portrait photo was reported as
    // showing unreadably small labels; sized for that case.
    final fontSize = size.width / 22;

    for (final star in namedStars) {
      final center = Offset(star.x, star.y);
      canvas.drawCircle(center, namedRadius, namedPaint);

      final painter = TextPainter(
        text: TextSpan(
          text: star.name,
          style: TextStyle(
            color: namedColor,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center + Offset(namedRadius + 4, -painter.height / 2),
      );
    }

    // Painted last so the one target the user actually asked for is never
    // occluded by a named-star circle or constellation line.
    final target = this.target;
    if (target != null) _paintTarget(canvas, size, target);
  }

  void _paintTarget(Canvas canvas, Size size, TargetMarker target) {
    final color = overrideColor ?? targetMarkerColor;
    final outerRadius = size.width / 38;
    final stroke = size.width / 90;
    final fontSize = size.width / 20;
    final textStyle = TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
    );

    if (target.isInFrame) {
      final center = target.position!;
      final path = targetStarPath(center, outerRadius);
      // Black outline first (same reasoning as the named-star label's
      // shadow above): a marker sitting on bright nebulosity or a
      // saturated star needs real contrast, not just a thin colored line.
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 2.0,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );

      // Dashed halo: the night-mode disambiguator. When every marker on
      // this canvas is the same red, this broken ring is the one thing
      // that still says "this one is the target" at a glance.
      final haloRadius = outerRadius * 1.9;
      final haloPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width / 200;
      const dashes = 12;
      const dutyCycle = 0.55;
      for (var i = 0; i < dashes; i++) {
        final start = i * 2 * math.pi / dashes;
        final sweep = (2 * math.pi / dashes) * dutyCycle;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: haloRadius),
          start,
          sweep,
          false,
          haloPaint,
        );
      }

      final painter = TextPainter(
        text: TextSpan(text: target.name, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center + Offset(outerRadius + 6, -painter.height / 2),
      );
      return;
    }

    // Off-frame or behind-camera: an edge arrow, unless there's truly no
    // direction to point in (the exact-antipode case) — draw nothing
    // rather than an arrow pointing nowhere in particular.
    if (target.direction == Offset.zero) return;
    final margin = size.width / 26;
    final edge = edgePointForDirection(target.direction, size, margin: margin);
    if (edge == null) return;

    final behindCamera = target.status == SkyProjectionStatus.behindCamera;
    final arrowLength = margin;
    final arrowHalfWidth = size.width / 55;
    final arrowTail = size.width / 18;

    canvas.save();
    canvas.translate(edge.dx, edge.dy);
    canvas.rotate(directionAngle(target.direction));
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawLine(
      Offset(-arrowTail, 0),
      Offset(-arrowLength * 0.35, 0),
      arrowPaint,
    );
    final head = Path()
      ..moveTo(0, 0)
      ..lineTo(-arrowLength, -arrowHalfWidth)
      ..lineTo(-arrowLength, arrowHalfWidth)
      ..close();
    if (behindCamera) {
      // Hollow head: pointing this way means turning the camera around,
      // not panning — a different action from an off-frame filled arrow.
      canvas.drawPath(head, arrowPaint);
    } else {
      canvas.drawPath(head, Paint()..color = color);
    }
    canvas.restore();

    final distanceLabel = target.separationDeg < 1
        ? '${(target.separationDeg * 60).toStringAsFixed(0)}\''
        : '${target.separationDeg.toStringAsFixed(1)}°';
    final label = behindCamera
        ? '${target.name}  $distanceLabel behind'
        : '${target.name}  $distanceLabel';
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    var labelTopLeft =
        edge -
        target.direction * (arrowLength + 6) -
        Offset(painter.width / 2, painter.height / 2);
    labelTopLeft = Offset(
      labelTopLeft.dx.clamp(4, size.width - painter.width - 4),
      labelTopLeft.dy.clamp(4, size.height - painter.height - 4),
    );
    painter.paint(canvas, labelTopLeft);
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.matchedX != matchedX ||
      oldDelegate.matchedY != matchedY ||
      oldDelegate.namedStars != namedStars ||
      oldDelegate.constellationLines != constellationLines ||
      oldDelegate.target != target ||
      oldDelegate.overrideColor != overrideColor;
}
