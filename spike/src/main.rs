//! M1 feasibility spike (see the project plan): can tetra3rs solve (a) a real
//! full-resolution camera frame, and (b) a phone photo of that same frame on
//! the camera's LCD screen (the actual field use case)?
//!
//! Usage:
//!   spike solve --image path.jpg --fov-deg 15.0 [--db data/my_db.bin]
//!   spike build-db --catalog data/gaia_merged.bin --max-fov-deg 25 --out data/db_5_25.bin

use std::time::Instant;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use image::GenericImageView;
use numeris::Matrix3;
use tetra3::{
    extract_centroids_from_image, CentroidExtractionConfig, GenerateDatabaseConfig, Quaternion,
    SolveConfig, SolverDatabase,
};

/// Build the ICRS→camera rotation quaternion for a hinted boresight (ra_deg,
/// dec_deg) and an assumed camera roll `theta_rad` (same convention as
/// `Solution::theta_rad`: angle from tangent-plane East axis to camera +X,
/// counter-clockwise). See the plan's M9 notes for the derivation: East/North
/// unit vectors at the boresight, rotated by theta to get the camera's local
/// +X/+Y axes in ICRS coordinates, then those three orthonormal directions
/// become the rows of the ICRS->camera rotation matrix.
fn hint_quaternion(ra_deg: f64, dec_deg: f64, theta_rad: f64) -> Quaternion {
    let ra = ra_deg.to_radians();
    let dec = dec_deg.to_radians();

    let z0 = [dec.cos() * ra.cos(), dec.cos() * ra.sin(), dec.sin()];
    let east0 = [-ra.sin(), ra.cos(), 0.0];
    let north0 = [-ra.cos() * dec.sin(), -ra.sin() * dec.sin(), dec.cos()];

    let (c, s) = (theta_rad.cos(), theta_rad.sin());
    let x_cam = [
        c * east0[0] + s * north0[0],
        c * east0[1] + s * north0[1],
        c * east0[2] + s * north0[2],
    ];
    let y_cam = [
        -s * east0[0] + c * north0[0],
        -s * east0[1] + c * north0[1],
        -s * east0[2] + c * north0[2],
    ];

    let m: Matrix3<f32> = Matrix3::new([
        [x_cam[0] as f32, x_cam[1] as f32, x_cam[2] as f32],
        [y_cam[0] as f32, y_cam[1] as f32, y_cam[2] as f32],
        [z0[0] as f32, z0[1] as f32, z0[2] as f32],
    ]);
    Quaternion::from_rotation_matrix(&m)
}

#[derive(Parser)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Build a solver database from a Gaia .bin catalog.
    BuildDb {
        #[arg(long)]
        catalog: String,
        #[arg(long, default_value_t = 25.0)]
        max_fov_deg: f32,
        #[arg(long)]
        min_fov_deg: Option<f32>,
        #[arg(long)]
        out: String,
    },
    /// Extract centroids from an image and attempt a plate solve.
    Solve {
        #[arg(long)]
        image: String,
        #[arg(long)]
        db: String,
        /// Estimated horizontal FOV in degrees.
        #[arg(long)]
        fov_deg: f32,
        /// Allowed FOV error, degrees either side of the estimate.
        #[arg(long, default_value_t = 5.0)]
        fov_error_deg: f32,
        /// Detection threshold, sigma above background noise.
        #[arg(long, default_value_t = 5.0)]
        sigma_threshold: f32,
        /// Cap on centroids fed to the solver (brightest first).
        #[arg(long, default_value_t = 60)]
        max_centroids: usize,
        /// Minimum blob size in pixels to count as a star candidate.
        #[arg(long, default_value_t = 3)]
        min_pixels: usize,
        /// Maximum blob size in pixels to count as a star candidate.
        #[arg(long, default_value_t = 10000)]
        max_pixels: usize,
        /// Max elongation (major/minor axis ratio). Pass a large value to disable.
        #[arg(long, default_value_t = 3.0)]
        max_elongation: f32,
        /// Max DAOFIND-style sharpness gate; set 0 to disable (None) for
        /// severely undersampled / downsized images where real stars are
        /// only 1-2 px wide and look hot-pixel-like.
        #[arg(long, default_value_t = 0.9)]
        max_sharpness: f32,
        /// FOV search timeout, ms.
        #[arg(long, default_value_t = 60_000)]
        solve_timeout_ms: u64,
        /// Brightest N centroids considered for 4-star pattern combinations
        /// (default in the crate is 24). Raise this if junk/hot-pixels are
        /// outranking real stars by brightness.
        #[arg(long, default_value_t = 24)]
        pattern_checking_stars: u32,
        /// Dump the extracted centroids and exit without solving.
        #[arg(long, default_value_t = false)]
        dump_centroids: bool,
        /// Debug: after solving, print tetra3's own world_to_pixel(ra,dec)
        /// for this RA (degrees) — ground truth to validate Dart's WCS port.
        #[arg(long)]
        check_ra_deg: Option<f64>,
        /// Paired with --check-ra-deg.
        #[arg(long)]
        check_dec_deg: Option<f64>,
    },
    /// Solve using a roll-sweep attitude hint (approximate target RA/Dec, no
    /// known camera roll) instead of blind lost-in-space search.
    SolveHint {
        #[arg(long)]
        image: String,
        #[arg(long)]
        db: String,
        #[arg(long)]
        fov_deg: f32,
        #[arg(long, default_value_t = 5.0)]
        sigma_threshold: f32,
        #[arg(long, default_value_t = 300)]
        max_centroids: usize,
        /// Approximate target RA, degrees.
        #[arg(long)]
        ra_deg: f64,
        /// Approximate target Dec, degrees.
        #[arg(long)]
        dec_deg: f64,
        /// Angular hint uncertainty (boresight), degrees.
        #[arg(long, default_value_t = 3.0)]
        hint_uncertainty_deg: f32,
        /// Roll-guess step, degrees (0..360 swept at this spacing).
        #[arg(long, default_value_t = 30.0)]
        roll_step_deg: f64,
        /// If set, use this exact theta (degrees) instead of sweeping — for
        /// validating the quaternion construction against a known-good solve.
        #[arg(long)]
        exact_theta_deg: Option<f64>,
    },
    /// Debug: check EXIF orientation handling before/after normalization.
    FixOrientation {
        #[arg(long)]
        image: String,
        #[arg(long)]
        out: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::BuildDb {
            catalog,
            max_fov_deg,
            min_fov_deg,
            out,
        } => build_db(&catalog, max_fov_deg, min_fov_deg, &out),
        Cmd::Solve {
            image,
            db,
            fov_deg,
            fov_error_deg,
            sigma_threshold,
            max_centroids,
            min_pixels,
            max_pixels,
            max_elongation,
            max_sharpness,
            solve_timeout_ms,
            pattern_checking_stars,
            dump_centroids,
            check_ra_deg,
            check_dec_deg,
        } => solve(
            &image,
            &db,
            fov_deg,
            fov_error_deg,
            sigma_threshold,
            max_centroids,
            min_pixels,
            max_pixels,
            max_elongation,
            max_sharpness,
            solve_timeout_ms,
            pattern_checking_stars,
            dump_centroids,
            check_ra_deg,
            check_dec_deg,
        ),
        Cmd::SolveHint {
            image,
            db,
            fov_deg,
            sigma_threshold,
            max_centroids,
            ra_deg,
            dec_deg,
            hint_uncertainty_deg,
            roll_step_deg,
            exact_theta_deg,
        } => solve_hint(
            &image,
            &db,
            fov_deg,
            sigma_threshold,
            max_centroids,
            ra_deg,
            dec_deg,
            hint_uncertainty_deg,
            roll_step_deg,
            exact_theta_deg,
        ),
        Cmd::FixOrientation { image, out } => fix_orientation(&image, &out),
    }
}

fn fix_orientation(image_path: &str, out_path: &str) -> Result<()> {
    use image::{ImageDecoder, ImageReader};
    use std::io::Cursor;

    let bytes = std::fs::read(image_path)?;
    let raw = image::load_from_memory(&bytes)?;
    println!(
        "Raw decode (no EXIF applied): {}x{}",
        raw.width(),
        raw.height()
    );

    let reader = ImageReader::new(Cursor::new(&bytes)).with_guessed_format()?;
    let mut decoder = reader.into_decoder()?;
    let orientation = decoder.orientation()?;
    println!("EXIF orientation: {:?}", orientation);

    let mut normalized = image::DynamicImage::from_decoder(decoder)?;
    normalized.apply_orientation(orientation);
    println!(
        "After apply_orientation: {}x{}",
        normalized.width(),
        normalized.height()
    );
    normalized.save(out_path)?;
    println!("Saved normalized image to {out_path}");
    Ok(())
}

fn build_db(catalog: &str, max_fov_deg: f32, min_fov_deg: Option<f32>, out: &str) -> Result<()> {
    let config = GenerateDatabaseConfig {
        max_fov_deg,
        min_fov_deg,
        epoch_proper_motion_year: Some(2026.0),
        ..Default::default()
    };
    println!(
        "Generating database: max_fov={max_fov_deg} deg, min_fov={:?} deg, from {catalog}",
        min_fov_deg
    );
    let t0 = Instant::now();
    let db = SolverDatabase::generate_from_gaia(catalog, &config)
        .with_context(|| format!("generating database from {catalog}"))?;
    println!("Generated in {:.1}s", t0.elapsed().as_secs_f32());
    db.save_to_file(out)
        .with_context(|| format!("saving database to {out}"))?;
    let bytes = std::fs::metadata(out)?.len();
    println!("Saved {out} ({:.1} MB)", bytes as f64 / 1e6);
    Ok(())
}

fn solve(
    image_path: &str,
    db_path: &str,
    fov_deg: f32,
    fov_error_deg: f32,
    sigma_threshold: f32,
    max_centroids: usize,
    min_pixels: usize,
    max_pixels: usize,
    max_elongation: f32,
    max_sharpness: f32,
    solve_timeout_ms: u64,
    pattern_checking_stars: u32,
    dump_centroids: bool,
    check_ra_deg: Option<f64>,
    check_dec_deg: Option<f64>,
) -> Result<()> {
    let img = image::open(image_path).with_context(|| format!("opening {image_path}"))?;
    let (w, h) = img.dimensions();
    println!("Image: {image_path} ({w}x{h})");

    let extract_config = CentroidExtractionConfig {
        sigma_threshold,
        max_centroids: Some(max_centroids),
        min_pixels,
        max_pixels,
        max_elongation: if max_elongation >= 100.0 { None } else { Some(max_elongation) },
        max_sharpness: if max_sharpness <= 0.0 { None } else { Some(max_sharpness) },
        ..Default::default()
    };
    let t0 = Instant::now();
    let extraction = extract_centroids_from_image(&img, &extract_config)
        .with_context(|| "centroid extraction failed")?;
    let extract_ms = t0.elapsed().as_secs_f32() * 1000.0;
    println!(
        "Extracted {} centroids in {:.1} ms",
        extraction.centroids.len(),
        extract_ms
    );

    if dump_centroids {
        for c in &extraction.centroids {
            println!(
                "  x={:8.2} y={:8.2} mass={:?}",
                c.x, c.y, c.mass
            );
        }
        return Ok(());
    }

    if extraction.centroids.len() < 5 {
        println!(
            "GATE FAILED: only {} centroids found; lost-in-space solving needs >= 5. \
             Try --sigma-threshold lower (more sensitive) or check the image.",
            extraction.centroids.len()
        );
        return Ok(());
    }

    let db = SolverDatabase::load_from_file(db_path)
        .with_context(|| format!("loading database {db_path}"))?;

    let solve_config = SolveConfig {
        fov_max_error_rad: Some(fov_error_deg.to_radians()),
        solve_timeout_ms: Some(solve_timeout_ms),
        pattern_checking_stars,
        ..SolveConfig::new(fov_deg.to_radians(), w, h)
    };

    let result = db.solve_from_centroids(&extraction.centroids, &solve_config);
    match result {
        Ok(solution) => {
            let cx = w as f64 / 2.0;
            let cy = h as f64 / 2.0;
            // Solution::pixel_to_world expects centered pixel coords (origin
            // at image center), matching the centroid convention.
            let (ra_deg, dec_deg) = solution.pixel_to_world(0.0, 0.0);
            println!("SOLVED");
            println!("  RA  = {:.5} deg", ra_deg);
            println!("  Dec = {:.5} deg", dec_deg);
            println!("  FOV = {:.3} deg", solution.fov_rad.to_degrees());
            println!(
                "  Roll (theta) = {:.3} deg",
                solution.theta_rad.to_degrees()
            );
            println!("  Matched stars = {}", solution.num_matches);
            println!(
                "  Matched catalog IDs (negative = -HIP): {:?}",
                solution.matched_catalog_ids
            );
            println!("  RMSE = {:.2} arcsec", solution.rmse_rad.to_degrees() * 3600.0);
            println!("  Solve time = {:.1} ms", solution.solve_time_ms);
            println!(
                "  Total (extract+solve) = {:.1} ms",
                extract_ms + solution.solve_time_ms
            );
            if let (Some(ra), Some(dec)) = (check_ra_deg, check_dec_deg) {
                match solution.world_to_pixel(ra, dec) {
                    Some((x, y)) => {
                        println!(
                            "  CHECK world_to_pixel({ra}, {dec}) = centered({x:.3}, {y:.3}), top-left({:.3}, {:.3})",
                            x + cx,
                            y + cy
                        );
                    }
                    None => println!("  CHECK world_to_pixel({ra}, {dec}) = None (behind camera)"),
                }
            }
        }
        Err(failure) => {
            println!("SOLVE FAILED: {:?}", failure.status);
            println!("  Solve time = {:.1} ms", failure.solve_time_ms);
        }
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn solve_hint(
    image_path: &str,
    db_path: &str,
    fov_deg: f32,
    sigma_threshold: f32,
    max_centroids: usize,
    ra_deg: f64,
    dec_deg: f64,
    hint_uncertainty_deg: f32,
    roll_step_deg: f64,
    exact_theta_deg: Option<f64>,
) -> Result<()> {
    let img = image::open(image_path).with_context(|| format!("opening {image_path}"))?;
    let (w, h) = img.dimensions();
    println!("Image: {image_path} ({w}x{h})");

    let extract_config = CentroidExtractionConfig {
        sigma_threshold,
        max_centroids: Some(max_centroids),
        max_sharpness: None,
        ..Default::default()
    };
    let t0 = Instant::now();
    let extraction = extract_centroids_from_image(&img, &extract_config)
        .with_context(|| "centroid extraction failed")?;
    let extract_ms = t0.elapsed().as_secs_f32() * 1000.0;
    println!(
        "Extracted {} centroids in {:.1} ms",
        extraction.centroids.len(),
        extract_ms
    );

    let db = SolverDatabase::load_from_file(db_path)
        .with_context(|| format!("loading database {db_path}"))?;

    let thetas: Vec<f64> = match exact_theta_deg {
        Some(t) => vec![t.to_radians()],
        None => {
            let n = (360.0 / roll_step_deg).round() as i64;
            (0..n).map(|i| (i as f64 * roll_step_deg).to_radians()).collect()
        }
    };
    println!("Trying {} roll guess(es)...", thetas.len());

    let t_hint0 = Instant::now();
    for theta in &thetas {
        let hint = hint_quaternion(ra_deg, dec_deg, *theta);
        let solve_config = SolveConfig {
            attitude_hint: Some(hint),
            hint_uncertainty_rad: hint_uncertainty_deg.to_radians(),
            strict_hint: true,
            ..SolveConfig::new(fov_deg.to_radians(), w, h)
        };
        let result = db.solve_from_centroids(&extraction.centroids, &solve_config);
        if let Ok(solution) = result {
            let (solved_ra, solved_dec) = solution.pixel_to_world(0.0, 0.0);
            println!(
                "HINT SOLVE SUCCEEDED at roll guess {:.0}° (tried {} of {})",
                theta.to_degrees(),
                thetas.iter().position(|t| t == theta).unwrap() + 1,
                thetas.len()
            );
            println!("  RA  = {:.5} deg", solved_ra);
            println!("  Dec = {:.5} deg", solved_dec);
            println!("  FOV = {:.3} deg", solution.fov_rad.to_degrees());
            println!("  Roll (theta) = {:.3} deg", solution.theta_rad.to_degrees());
            println!("  Matched stars = {}", solution.num_matches);
            println!(
                "  Total hint-sweep time = {:.1} ms (+ {:.1} ms extraction)",
                t_hint0.elapsed().as_secs_f32() * 1000.0,
                extract_ms
            );
            return Ok(());
        }
    }
    println!(
        "HINT SOLVE FAILED after {} roll guess(es) in {:.1} ms — would fall back to blind search",
        thetas.len(),
        t_hint0.elapsed().as_secs_f32() * 1000.0
    );
    Ok(())
}
