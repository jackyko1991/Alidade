import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Displays [imageBytes] with two overlay layers, scaled to however large
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
class StarOverlayImage extends StatefulWidget {
  const StarOverlayImage({
    super.key,
    required this.imageBytes,
    required this.matchedX,
    required this.matchedY,
    this.namedStars = const [],
    this.constellationLines = const [],
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

class _StarPainter extends CustomPainter {
  _StarPainter(
    this.matchedX,
    this.matchedY,
    this.namedStars,
    this.constellationLines,
    this.overrideColor,
  );

  final List<double> matchedX;
  final List<double> matchedY;
  final List<NamedStarPosition> namedStars;
  final List<List<Offset?>> constellationLines;
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
      canvas.drawCircle(Offset(matchedX[i], matchedY[i]), matchedRadius, matchedPaint);
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
      painter.paint(canvas, center + Offset(namedRadius + 4, -painter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.matchedX != matchedX ||
      oldDelegate.matchedY != matchedY ||
      oldDelegate.namedStars != namedStars ||
      oldDelegate.constellationLines != constellationLines ||
      oldDelegate.overrideColor != overrideColor;
}
