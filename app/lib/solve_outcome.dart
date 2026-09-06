/// Plain, platform-independent mirror of the Rust solver's result.
///
/// Deliberately not the `flutter_rust_bridge`-generated `SolveOutcome` class
/// directly: native and web builds each generate their own, incompatible
/// version of that type (see `lib/rust_bridge/`'s doc comment for why), so
/// app code needs one shared shape neither generated tree defines.
class SolveOutcome {
  final bool success;
  final String? error;
  final double raDeg;
  final double decDeg;
  final double fovDeg;
  final double rollDeg;
  final int matchedStars;
  final double rmseArcsec;
  final double solveTimeMs;

  /// Pixel coordinates (top-left origin, matching the source image) of the
  /// matched stars, for drawing a highlight overlay.
  final List<double> matchedStarX;
  final List<double> matchedStarY;

  const SolveOutcome({
    required this.success,
    this.error,
    required this.raDeg,
    required this.decDeg,
    required this.fovDeg,
    required this.rollDeg,
    required this.matchedStars,
    required this.rmseArcsec,
    required this.solveTimeMs,
    required this.matchedStarX,
    required this.matchedStarY,
  });
}
