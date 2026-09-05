//! Offline plate-solving API exposed to Flutter.
//!
//! Tuning here is not arbitrary — both non-default values were forced by the
//! M1 feasibility spike against real camera JPEGs (see the project plan):
//! `max_sharpness: None` because downsized in-camera JPEGs land stars
//! sub-pixel (crate default `Some(0.9)` rejects them as hot-pixel-like), and
//! `pattern_checking_stars: 60` because JPEG/hot-pixel noise can outrank real
//! stars by brightness in sparser fields (crate default 24 was too small for
//! any 4-star combination to hash to a real pattern; 40 was enough for the
//! original M1 test images but not after re-encoding/rotating one for EXIF
//! orientation — see `normalize_orientation` below).

use std::io::Cursor;
use std::sync::OnceLock;

use flutter_rust_bridge::frb;
use image::{GenericImageView, ImageDecoder, ImageFormat, ImageReader};
use tetra3::{
    extract_centroids_from_image, CentroidExtractionConfig, SolveConfig, SolverDatabase,
};

static DB: OnceLock<SolverDatabase> = OnceLock::new();

/// Bakes the image's EXIF orientation into its pixel data and re-encodes as
/// JPEG, so every consumer (Rust solving, Flutter display, history
/// thumbnails) shares one unambiguous pixel layout.
///
/// This matters because `image::load_from_memory` does **not** auto-rotate
/// on decode (confirmed against `image` 0.25.10's source — `Orientation` must
/// be read from the decoder and applied explicitly), and Flutter's own image
/// widgets are inconsistent about honoring EXIF orientation across platforms.
/// Call this once, right after picking an image, and use only the returned
/// bytes from then on — that removes the ambiguity instead of trying to keep
/// two decoders' conventions in sync.
#[frb(sync)]
pub fn normalize_orientation(image_bytes: Vec<u8>) -> Result<Vec<u8>, String> {
    let reader = ImageReader::new(Cursor::new(&image_bytes))
        .with_guessed_format()
        .map_err(|e| e.to_string())?;
    let mut decoder = reader.into_decoder().map_err(|e| e.to_string())?;
    let orientation = decoder.orientation().map_err(|e| e.to_string())?;

    let mut img = image::DynamicImage::from_decoder(decoder).map_err(|e| e.to_string())?;
    img.apply_orientation(orientation);

    // PNG, not JPEG: re-encoding a rotated image as JPEG stacks a second
    // generation of compression noise on top of the camera's original
    // JPEG artifacts, which is enough to break solving outright — measured
    // directly (not theorized): the same photo, rotated then re-encoded as
    // JPEG, failed to solve even at pattern_checking_stars=60 and got
    // *worse* (timeouts) at 70/80/100, while the identical rotation
    // re-encoded as PNG solved cleanly at 60 in ~200ms. PNG is lossless, so
    // this cost is a one-time size increase (a JPEG-shot phone photo grows
    // to a several-MB in-memory PNG), not a repeated quality loss.
    let mut out = Vec::new();
    img.write_to(&mut Cursor::new(&mut out), ImageFormat::Png)
        .map_err(|e| e.to_string())?;
    Ok(out)
}

/// Load the star-catalog pattern database (bundled as a Flutter asset and
/// passed here as raw bytes) once at app startup.
#[frb(sync)]
pub fn load_database(bytes: Vec<u8>) -> Result<(), String> {
    let db = SolverDatabase::from_bytes(&bytes).map_err(|e| e.to_string())?;
    DB.set(db).map_err(|_| "database already loaded".to_string())
}

#[frb(sync)]
pub fn is_database_loaded() -> bool {
    DB.get().is_some()
}

pub struct SolveOutcome {
    pub success: bool,
    pub ra_deg: f64,
    pub dec_deg: f64,
    pub fov_deg: f32,
    pub roll_deg: f64,
    pub matched_stars: u32,
    pub rmse_arcsec: f32,
    pub solve_time_ms: f32,
    /// Pixel coordinates (top-left origin, matching the source image) of the
    /// matched stars, for drawing a highlight overlay. Same length as
    /// `matched_star_y` and `matched_star_catalog_id`; empty on failure.
    pub matched_star_x: Vec<f32>,
    pub matched_star_y: Vec<f32>,
    /// Catalog ID for each matched star, same order as `matched_star_x`/`y`.
    /// Negative = Hipparcos gap-fill star, with the HIP number being
    /// `-id` (see `download_gaia_catalog.py`'s merge convention); positive =
    /// a Gaia DR3 `source_id`, which has no common name to look up.
    pub matched_star_catalog_id: Vec<i64>,
    pub error: Option<String>,
}

fn failure(msg: impl Into<String>) -> SolveOutcome {
    SolveOutcome {
        success: false,
        ra_deg: 0.0,
        dec_deg: 0.0,
        fov_deg: 0.0,
        roll_deg: 0.0,
        matched_stars: 0,
        rmse_arcsec: 0.0,
        solve_time_ms: 0.0,
        matched_star_x: Vec::new(),
        matched_star_y: Vec::new(),
        matched_star_catalog_id: Vec::new(),
        error: Some(msg.into()),
    }
}

/// Solve an image (JPEG/PNG bytes, e.g. from an image picker) against the
/// loaded database, given an estimated horizontal FOV in degrees.
///
/// Not marked `#[frb(sync)]`: flutter_rust_bridge runs this on a worker
/// thread automatically, keeping the UI isolate free during the solve.
pub fn solve_image(image_bytes: Vec<u8>, fov_deg: f32, fov_error_deg: f32) -> SolveOutcome {
    let Some(db) = DB.get() else {
        return failure("database not loaded — call load_database first");
    };

    let img = match image::load_from_memory(&image_bytes) {
        Ok(img) => img,
        Err(e) => return failure(format!("failed to decode image: {e}")),
    };
    let (w, h) = img.dimensions();

    let extract_config = CentroidExtractionConfig {
        sigma_threshold: 5.0,
        max_centroids: Some(300),
        max_sharpness: None,
        ..Default::default()
    };
    let extraction = match extract_centroids_from_image(&img, &extract_config) {
        Ok(e) => e,
        Err(e) => return failure(format!("centroid extraction failed: {e}")),
    };
    if extraction.centroids.len() < 5 {
        return failure(format!(
            "only {} star candidates found; need at least 5",
            extraction.centroids.len()
        ));
    }

    let solve_config = SolveConfig {
        fov_max_error_rad: Some(fov_error_deg.to_radians()),
        // 60, not the M1 spike's 40: re-encoding/rotating an image (e.g. for
        // EXIF orientation normalization) shifts which JPEG-noise artifacts
        // land in the brightest-N set enough that 40 wasn't always enough —
        // confirmed empirically against a real portrait-orientation photo.
        pattern_checking_stars: 60,
        // Crate default is 5000ms — a real device hit that ceiling (reported
        // as "Timeout after 5001ms"). Our own benches are 40-300ms, so 5s
        // should never be a real search taking genuinely longer; give it
        // headroom anyway rather than fail fast, since a slightly slower
        // solve beats a spurious failure.
        solve_timeout_ms: Some(20_000),
        ..SolveConfig::new(fov_deg.to_radians(), w, h)
    };

    match db.solve_from_centroids(&extraction.centroids, &solve_config) {
        Ok(solution) => {
            let (ra_deg, dec_deg) = solution.pixel_to_world(0.0, 0.0);
            let (cx, cy) = (w as f32 / 2.0, h as f32 / 2.0);
            let mut matched_star_x = Vec::new();
            let mut matched_star_y = Vec::new();
            let mut matched_star_catalog_id = Vec::new();
            for (&centroid_idx, &catalog_id) in solution
                .matched_centroid_indices
                .iter()
                .zip(solution.matched_catalog_ids.iter())
            {
                if let Some(c) = extraction.centroids.get(centroid_idx) {
                    matched_star_x.push(c.x + cx);
                    matched_star_y.push(c.y + cy);
                    matched_star_catalog_id.push(catalog_id);
                }
            }
            SolveOutcome {
                success: true,
                ra_deg,
                dec_deg,
                fov_deg: solution.fov_rad.to_degrees(),
                roll_deg: solution.theta_rad.to_degrees(),
                matched_stars: solution.num_matches,
                rmse_arcsec: solution.rmse_rad.to_degrees() * 3600.0,
                solve_time_ms: solution.solve_time_ms,
                matched_star_x,
                matched_star_y,
                matched_star_catalog_id,
                error: None,
            }
        }
        Err(fail) => failure(format!("{:?} after {:.0} ms", fail.status, fail.solve_time_ms)),
    }
}
