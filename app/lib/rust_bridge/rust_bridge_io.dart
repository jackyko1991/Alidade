import 'dart:typed_data';

import '../solve_outcome.dart' as app;
import '../src/rust/api/solver.dart' as api;
import '../src/rust/frb_generated.dart';

Future<void> initRust() => RustLib.init();

Future<void> loadDatabaseBytes(Uint8List bytes) async {
  api.loadDatabase(bytes: bytes);
}

Future<Uint8List> normalizeOrientationBytes(Uint8List imageBytes) async =>
    api.normalizeOrientation(imageBytes: imageBytes);

Future<app.SolveOutcome> solveImageBytes({
  required Uint8List imageBytes,
  required double fovDeg,
  required double fovErrorDeg,
}) async {
  final r = await api.solveImage(
    imageBytes: imageBytes,
    fovDeg: fovDeg,
    fovErrorDeg: fovErrorDeg,
  );
  return app.SolveOutcome(
    success: r.success,
    error: r.error,
    raDeg: r.raDeg,
    decDeg: r.decDeg,
    fovDeg: r.fovDeg,
    rollDeg: r.rollDeg,
    matchedStars: r.matchedStars,
    rmseArcsec: r.rmseArcsec,
    solveTimeMs: r.solveTimeMs,
    matchedStarX: r.matchedStarX,
    matchedStarY: r.matchedStarY,
  );
}
