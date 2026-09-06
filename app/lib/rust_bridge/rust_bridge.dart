/// Platform-agnostic bridge to the Rust solver. Exactly one of the two
/// generated `flutter_rust_bridge` binding trees is used depending on
/// platform — see this file's sibling implementations for why.
///
/// ## Why two trees, not one
///
/// `lib/src/rust` (native: Android/iOS/desktop) keeps flutter_rust_bridge's
/// default threaded behavior: `solveImage` runs on a worker thread, so a
/// solve never blocks the Flutter UI thread. `lib/src/rust_web` is
/// generated with `default_dart_async: false` instead (see
/// `flutter_rust_bridge_web.yaml`), because GitHub Pages — the planned web
/// host — cannot set the COOP/COEP response headers the default threaded
/// web build needs for SharedArrayBuffer; without them,
/// flutter_rust_bridge's web worker pool fails at runtime the moment it's
/// used (confirmed locally: "SharedArrayBuffer transfer requires
/// self.crossOriginIsolated"). `default_dart_async` is a global codegen
/// setting, not per-platform, so getting the single-threaded web behavior
/// without also making every native call block the UI thread requires two
/// separately generated trees rather than one shared config.
///
/// Both trees define their own `RustLib`/`SolveOutcome`/etc. — incompatible
/// Dart types that happen to share names — so callers use this file's
/// uniform, always-`Future`-returning functions and `../solve_outcome.dart`'s
/// plain `SolveOutcome` instead of either generated type directly.
library;

export 'rust_bridge_io.dart'
    if (dart.library.js_interop) 'rust_bridge_web.dart';
