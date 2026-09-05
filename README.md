<p align="center">
  <img src="design/icon/alidade_icon.png" width="120" alt="Alidade icon">
</p>

<h1 align="center">Alidade</h1>

<p align="center">An offline plate solver for astrophotographers without a finder scope.</p>

Point your camera, take a shot, and Alidade tells you exactly where in the sky
you're pointed — no internet connection required. Solving runs entirely
on-device in well under a second.

## Features

- **Fully offline lost-in-space plate solving.** Import a photo from your
  gallery and get RA/Dec, field of view, and roll in well under a second,
  with no network round-trip and nothing ever leaving your phone.
- **Matched-star and named-star overlays.** See exactly which stars the
  solver detected, plus labels for bright named stars or denser Flamsteed/
  Bayer catalog designations (your choice), projected through the solved
  WCS onto the image.
- **Constellation lines**, projected the same way.
- **Reverse-lookup auto-naming** — after a successful solve, Alidade
  suggests a name for what you're looking at (Messier catalog).
- **Solve history**, with a thumbnail (matched stars baked in), full
  result, and multi-select delete.
- **Night mode** — a red-on-black theme that preserves night-adapted
  vision, the classic astronomer's red-flashlight trick.

## How it works

Alidade's solving core is [tetra3rs](https://github.com/ssmichael1/tetra3rs),
a Rust implementation of the Tetra3 lost-in-space star identification
algorithm. Given a set of star positions extracted from your photo, it
matches their geometric pattern against a bundled star catalog — no prior
pointing estimate required.

The Flutter UI talks to the Rust solver via
[flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge).

## Building

Requires Flutter (stable channel) and Rust (via rustup) installed and on
your `PATH`.

```sh
cd app
flutter pub get
flutter run --release
```

The Android build compiles the Rust solver automatically via
[cargokit](https://github.com/irondash/cargokit) — no separate `cargo-ndk`
step needed.

## License

Alidade's own source code is licensed under the [MIT License](LICENSE).

Bundled data carries its own license, credited in-app on the About screen
and summarized here:

| Data | Source | License |
|---|---|---|
| Solving engine | [tetra3rs](https://github.com/ssmichael1/tetra3rs) (Rust port of ESA's [tetra3](https://github.com/esa/tetra3)) | MIT / Apache-2.0 |
| Star catalog | Gaia DR3 + Hipparcos (ESA) | — |
| Named-star lookup | [IAU Catalog of Star Names](https://github.com/cyschneck/iau-star-names) | MIT |
| Star designations | Yale Bright Star Catalog (BSC5, Hoffleit & Warren 1991) | Public domain |
| Messier object lookup | [messier-registry](https://github.com/wdelenclos/messier-registry) | MIT |
| Constellation lines | [d3-celestial](https://github.com/ofrohn/d3-celestial) by Olaf Frohn | BSD-3-Clause |
