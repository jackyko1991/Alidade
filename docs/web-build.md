# Web build: platform-specific gaps, not one

The web (PWA) build compiles the same Rust solver crate
(`app/rust`, `alidade_core`) to WebAssembly instead of a native
Android/iOS library, and reuses the rest of the app's Dart code as-is.
Getting an actually-working deployment surfaced several separate platform
gaps, each confirmed by driving the real, deployed page (headless Chrome
or Playwright + the DevTools protocol, not just reading source) rather
than assumed from reading library docs:

1. flutter_rust_bridge's default web build doesn't run on GitHub Pages at
   all (below).
2. The per-lens database download is blocked by CORS when fetched from a
   GitHub Pages origin (see "Same-origin database hosting").
3. Both the download's local cache and solve history are native-only —
   `path_provider` has no web implementation (see "No persistent cache on
   web").

This doc covers all of them, since they were each easy to miss (the app
*compiles* cleanly for web in every case — every one of these only shows
up at runtime, in a browser, doing the actual thing a user would do).

## The problem: GitHub Pages can't set cross-origin isolation headers

flutter_rust_bridge's default web build is **threaded**: Rust calls run
on a Web Worker, keeping the main JS thread (and Flutter's rendering)
free. That requires transferring a `SharedArrayBuffer` between the main
thread and the worker, which browsers only allow on a
["cross-origin isolated"](https://web.dev/articles/cross-origin-isolation-guide)
page — one served with:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

GitHub Pages serves static files with no way to add custom response
headers. Confirmed locally (headless Chrome, plain `python -m
http.server`, no COOP/COEP): the default build fails at runtime the
moment it tries to spin up its worker pool —

```
panicked at .../flutter_rust_bridge-2.13.0/src/third_party/wasm_bindgen/worker_pool.rs:253:
fail to create WorkerPool: JsValue(DataCloneError: Failed to execute 'postMessage' on 'Worker':
SharedArrayBuffer transfer requires self.crossOriginIsolated.
```

## The fix: `default_dart_async: false`

flutter_rust_bridge documents a single-threaded fallback for exactly
this situation
([docs](https://cjycode.com/flutter_rust_bridge/manual/miscellaneous/web-cross-origin)):
setting `default_dart_async: false` makes every Rust function
`#[frb(sync)]` by default, so calls run on the main thread and never
need a `SharedArrayBuffer`. Fine for this app — solves are 40–300ms,
comfortably within a single frame budget even blocking the main thread.

## Why that setting can't just go in `flutter_rust_bridge.yaml`

`default_dart_async` is a **global** codegen setting, not per-platform.
Applying it to the app's one `flutter_rust_bridge.yaml` would make
`solve_image` synchronous on Android/iOS too — turning every solve into
a main-thread block instead of running on flutter_rust_bridge's own
worker thread (the previous, correct native behavior; there's a doc
comment on `solveImage` in the generated bindings that says as much).
That's a real UX regression on native, not just a web-specific tweak.

So there are two separate generated-bindings trees:

| | Config | Generated Dart | `default_dart_async` |
|---|---|---|---|
| Native (Android/iOS/desktop) | `app/flutter_rust_bridge.yaml` | `app/lib/src/rust/` | unset (→ `true`, async/threaded) |
| Web | `app/flutter_rust_bridge_web.yaml` | `app/lib/src/rust_web/` | `false` (sync/main-thread) |

Both configs share the same `rust_root: rust/` — same Rust source, same
crate — but each `generate` run also overwrites
**`app/rust/src/frb_generated.rs`** with glue code shaped for that
config (sync wrappers vs. async/threaded wrappers). The two configs
cannot be "generated" at the same time; whichever ran most recently is
what a subsequent `cargo build` / `wasm-pack build` actually compiles
against.

**Practical consequence:** the committed `app/rust/src/frb_generated.rs`
is always the **native** variant (that's what local `flutter run` / `cargo
build` needs day to day). Building web regenerates it into the web
variant as a build step, immediately before `wasm-pack`; CI does this in
an ephemeral runner and never commits the result. If you do this in your
own working tree instead of CI, regenerate the native variant again
afterward before doing any native work:

```sh
# Web build (as CI does it)
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge_web.yaml
flutter_rust_bridge_codegen build-web --release --wasm-pack-rustflags="-C target-feature=+bulk-memory"
flutter build web --release --base-href /Alidade/

# Restore native glue before touching Android/iOS again
flutter_rust_bridge_codegen generate
```

## Why the RUSTFLAGS override too

`flutter_rust_bridge_codegen build-web` always passes `wasm-pack` a
threaded-WASM `RUSTFLAGS` by default (`+atomics,+bulk-memory,
+mutable-globals`, `--shared-memory`, …), independent of
`default_dart_async`. Even with every *call* on the main thread, a wasm
binary built with those flags still requires shared memory to
instantiate, hitting the same `crossOriginIsolated` requirement. The
`--wasm-pack-rustflags="-C target-feature=+bulk-memory"` override drops
the threading-specific flags so the compiled module never asks for
`SharedArrayBuffer` in the first place. `wasm-pack` warns about this
override ("does not contain the default threaded-WASM flags") — that
warning is expected and is exactly the trade-off being made here.

## The other half: reconciling incompatible generated types

Because `app/lib/src/rust/api/solver.dart` and
`app/lib/src/rust_web/api/solver.dart` are generated independently, they
each define their *own* `SolveOutcome` class (and `RustLib`, etc.) —
same names, incompatible types, and different method signatures
(`Future<SolveOutcome> solveImage(...)` on native vs. plain
`SolveOutcome solveImage(...)` on web). App code can't import both
directly and use one uniform call site.

- **`app/lib/solve_outcome.dart`** — a plain, hand-written `SolveOutcome`
  class with just the fields the app actually uses. Neither generated
  type; app code (`main.dart`, `history.dart`, etc.) only ever sees this
  one.
- **`app/lib/rust_bridge/`** — the platform switch:
  - `rust_bridge_io.dart` wraps the native tree, `await`s the real async
    call, and converts its `SolveOutcome` to the plain one.
  - `rust_bridge_web.dart` wraps the web tree, calls the sync function
    directly (no `await` needed under the hood), and converts the
    result the same way — but is still declared `async` itself, so it
    returns a `Future` too. This is what lets `main.dart` `await
    solver.solveImageBytes(...)` identically on every platform, even
    though only the native path is genuinely asynchronous underneath.
  - `rust_bridge.dart` picks between the two via a conditional export
    (`if (dart.library.js_interop)`), the same mechanism
    flutter_rust_bridge's own generated `frb_generated.dart` uses to
    pick between its `.io.dart`/`.web.dart` runtime.

If you add a new Rust API function the app needs to call, it needs a
matching wrapper added to *both* `rust_bridge_io.dart` and
`rust_bridge_web.dart` — there's no way around maintaining that pair by
hand, since the two generated signatures genuinely differ.

## Same-origin database hosting

The per-lens solver databases are hosted as GitHub Release assets for the
native app (`db_manifest.dart`'s `downloadUrl`). Confirmed live (headless
Chrome + the DevTools protocol, driving the actual deployed page) that a
browser can't fetch them from there: GitHub's release-asset host
(`release-assets.githubusercontent.com`) sends no
`Access-Control-Allow-Origin` header, so the cross-origin request is
blocked —

```
Access to fetch at 'https://github.com/.../db_fov130.bin' from origin
'https://jackyko1991.github.io' has been blocked by CORS policy: No
'Access-Control-Allow-Origin' header is present on the requested resource.
```

Fixed by serving the same files same-origin instead: `downloadUrl` returns
a relative `dbs/<file>` path on web (resolved by the browser against the
page's own `<base href>`), and `.github/workflows/deploy-pwa.yml` has a
"Download solver databases for same-origin serving" step that copies the
release assets into the Pages build output before it's deployed, so
they're served from `jackyko1991.github.io/Alidade/dbs/...` — no
cross-origin request, no CORS to hit.

## No persistent cache on web

Two features — the per-lens database cache (`DbManager`) and solve history
(`HistoryStore`) — used `dart:io`'s `File`/`Directory` plus `path_provider`
for local storage. Neither works on Flutter web: `path_provider` (as of
2.1.6) has no web platform implementation at all — its own `pubspec.yaml`
declares `android`/`ios`/`linux`/`macos`/`windows` default packages and
nothing else. Calling `getApplicationSupportDirectory()` /
`getApplicationDocumentsDirectory()` on web doesn't silently no-op; it
throws `MissingPluginException` at the first real use, confirmed live
(driving the deployed page: adding a lens and tapping download surfaced a
`MissingPluginException(No implementation found for method
getApplicationSupportDirectory on channel plugins.flutter.io/path_provider)`
SnackBar; opening Solve History with entries would hit the same failure
mode for `getApplicationDocumentsDirectory()`).

Both got the same fix, split the same way as the solver bindings above:

| | Native | Web |
|---|---|---|
| Database cache | `db_manager_io.dart` (files under the app support dir) | `db_manager_web.dart` (in-memory `Map`, cleared on reload) |
| Solve history | `history_store_io.dart` (JSON manifest + image files) | `history_store_web.dart` (in-memory, cleared on reload) |

Both pairs are picked via the same `export 'x_io.dart' if
(dart.library.js_interop) 'x_web.dart';` conditional export as
`rust_bridge.dart`. The web variants are a deliberate, documented
trade-off, not a partial fix: a real persistent web store (IndexedDB, or
the Origin Private File System) is possible later, but re-fetching /
re-solving once per page load is the honest, *working* starting point —
better than a persistent store that's actually broken.

`e2e/pwa.spec.mjs` exercises both of these directly (a real download, and
opening Solve History) specifically because they're exactly the kind of
bug that compiles cleanly and only shows up doing the actual thing a user
would do in a real browser.
