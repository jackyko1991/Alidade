import 'dart:typed_data';
import 'dart:ui' as ui;

/// Renders [bytes] downscaled to [maxWidth] wide, PNG-encoded, with small
/// circles baked in at each (already full-image-scaled) matched-star
/// position — shared by both `HistoryStore` platform implementations.
Future<Uint8List> downscaleToPngWithMarkers(
  Uint8List bytes,
  int maxWidth,
  List<double> matchedStarX,
  List<double> matchedStarY,
) async {
  // Every `ui.Image` decoded here owns native/GPU memory that isn't
  // managed by Flutter's own image cache (that cache only covers images
  // loaded through an `ImageProvider`) — each one must be disposed
  // explicitly, or repeated solves slowly exhaust the GPU's descriptor
  // pool until the app crashes natively (confirmed on-device: repeated
  // solving crashed with Impeller's "ErrorOutOfPoolMemory" right before a
  // native SIGSEGV, traced back to leaked images from this function and
  // from decodes elsewhere in the app).
  final fullCodec = await ui.instantiateImageCodec(bytes);
  final fullFrame = await fullCodec.getNextFrame();
  final originalWidth = fullFrame.image.width;
  fullFrame.image.dispose();

  final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
  final frame = await codec.getNextFrame();
  final thumbWidth = frame.image.width.toDouble();
  final thumbHeight = frame.image.height.toDouble();
  final scale = originalWidth == 0 ? 1.0 : thumbWidth / originalWidth;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(frame.image, ui.Offset.zero, ui.Paint());
  final markerPaint = ui.Paint()
    ..color = const ui.Color(0xFF33E07A)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = thumbWidth / 220;
  final markerRadius = thumbWidth / 110;
  for (var i = 0; i < matchedStarX.length && i < matchedStarY.length; i++) {
    canvas.drawCircle(
      ui.Offset(matchedStarX[i] * scale, matchedStarY[i] * scale),
      markerRadius,
      markerPaint,
    );
  }
  final picture = recorder.endRecording();
  final composited = await picture.toImage(thumbWidth.round(), thumbHeight.round());
  frame.image.dispose();
  final byteData = await composited.toByteData(format: ui.ImageByteFormat.png);
  composited.dispose();
  return byteData!.buffer.asUint8List();
}
