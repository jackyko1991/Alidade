//! TDD guardrail: the two real-camera reference images from the M1
//! feasibility spike (see the project plan) must keep solving to their
//! known-correct sky coordinates. This exercises the *actual* app API
//! (`alidade_core::api::solver`), not a reimplementation — if `solve_image`'s
//! tuning (`max_sharpness`, `pattern_checking_stars`, `solve_timeout_ms`) or
//! `normalize_orientation` regress, these fail immediately, on the host
//! machine, with no phone/emulator/Flutter build required.
//!
//! Known-correct values were established by the M1/M9 spikes solving these
//! same images at pattern_checking_stars=40; the app now uses 60 (a later
//! fix for orientation-normalized re-encodes), so a slightly generous
//! tolerance (0.05°) covers minor refinement differences between the two
//! settings rather than demanding bit-identical output.

use alidade_core::api::solver;

const DB_PATH: &str = "tests/fixtures/db_fov16.bin";

fn ensure_database_loaded() {
    let bytes = std::fs::read(DB_PATH)
        .unwrap_or_else(|e| panic!("failed to read {DB_PATH}: {e}"));
    // load_database's OnceLock only accepts the first call; later calls
    // (from other #[test] fns in this same test binary) correctly fail with
    // "database already loaded" — that's success, not a real error, so
    // ignore it rather than unwrap.
    let _ = solver::load_database(bytes);
}

#[test]
fn solves_dumbbell_reference_image() {
    ensure_database_loaded();
    let image_bytes = std::fs::read("tests/fixtures/dumbbell.jpg").unwrap();

    let result = solver::solve_image(image_bytes, 15.2, 8.0);

    assert!(result.success, "solve failed: {:?}", result.error);
    assert!(
        (result.ra_deg - 302.78454).abs() < 0.05,
        "RA {} not close to expected 302.78454",
        result.ra_deg
    );
    assert!(
        (result.dec_deg - 26.34199).abs() < 0.05,
        "Dec {} not close to expected 26.34199",
        result.dec_deg
    );
    assert!(
        result.matched_stars >= 30,
        "only {} matched stars, expected >= 30",
        result.matched_stars
    );
    assert_eq!(result.matched_star_x.len(), result.matched_stars as usize);
    assert_eq!(result.matched_star_y.len(), result.matched_stars as usize);
    assert_eq!(
        result.matched_star_catalog_id.len(),
        result.matched_stars as usize
    );
}

#[test]
fn solves_veil_reference_image() {
    ensure_database_loaded();
    let image_bytes = std::fs::read("tests/fixtures/veil.jpg").unwrap();

    let result = solver::solve_image(image_bytes, 15.2, 8.0);

    assert!(result.success, "solve failed: {:?}", result.error);
    assert!(
        (result.ra_deg - 310.48886).abs() < 0.05,
        "RA {} not close to expected 310.48886",
        result.ra_deg
    );
    assert!(
        (result.dec_deg - 34.17502).abs() < 0.05,
        "Dec {} not close to expected 34.17502",
        result.dec_deg
    );
    assert!(
        result.matched_stars >= 30,
        "only {} matched stars, expected >= 30",
        result.matched_stars
    );
}

#[test]
fn solves_dumbbell_through_the_full_app_pipeline_normalize_then_solve() {
    // This is the actual sequence `main.dart`'s `_pickImage`/`_solve` run —
    // the two previous tests solve the raw file directly, skipping
    // `normalize_orientation` entirely, which is exactly why they didn't
    // catch a real regression: normalizing this file (EXIF Orientation=6)
    // re-encoded it as JPEG, and that second generation of JPEG compression
    // (on top of the camera's own) was enough to break solving outright —
    // measured directly: NoMatch at pattern_checking_stars=60, and it got
    // *worse* (Timeout) at 70/80/100, not better. Fixed by re-encoding as
    // PNG (lossless) in `normalize_orientation` instead. This test is the
    // regression guard for that fix — it must exercise the real pipeline,
    // not just `solve_image` alone, or it would pass right through the bug
    // again.
    ensure_database_loaded();
    let raw_bytes = std::fs::read("tests/fixtures/dumbbell.jpg").unwrap();

    let normalized = solver::normalize_orientation(raw_bytes)
        .expect("normalize_orientation failed");

    // The source photo is EXIF-rotated to portrait, so after normalization
    // its pixel width is the sensor's *height* (24mm on full-frame), not
    // its width (36mm) — same FOV math `LensPreset.fovDegForImage` does in
    // Dart for a portrait image.
    let fov_deg = 2.0_f32 * (24.0_f32 / (2.0 * 135.0)).atan().to_degrees();
    let result = solver::solve_image(normalized, fov_deg, 8.0);

    assert!(
        result.success,
        "solve failed after normalize_orientation: {:?}",
        result.error
    );
    assert!(
        (result.ra_deg - 302.78454).abs() < 0.05,
        "RA {} not close to expected 302.78454",
        result.ra_deg
    );
    assert!(
        (result.dec_deg - 26.34199).abs() < 0.05,
        "Dec {} not close to expected 26.34199",
        result.dec_deg
    );
    assert!(
        result.matched_stars >= 30,
        "only {} matched stars, expected >= 30",
        result.matched_stars
    );
}

#[test]
fn rejects_solve_before_database_loaded_is_a_real_error_shape() {
    // Not a claim that the database is unloaded (other tests in this binary
    // load it first and it stays loaded) — just a sanity check that a
    // clearly-wrong FOV on a real image fails gracefully with an error
    // message rather than panicking, since callers (the Flutter UI) rely on
    // `SolveOutcome.error` rather than a Rust panic crossing the FFI boundary.
    ensure_database_loaded();
    let image_bytes = std::fs::read("tests/fixtures/dumbbell.jpg").unwrap();
    let result = solver::solve_image(image_bytes, 0.5, 0.05);
    assert!(!result.success);
    assert!(result.error.is_some());
}
