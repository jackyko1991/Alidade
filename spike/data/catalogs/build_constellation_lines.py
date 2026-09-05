"""Convert d3-celestial's constellations.lines.json (BSD-3-Clause, Olaf Frohn,
github.com/ofrohn/d3-celestial) into a compact RA/Dec line-segment asset for
the app's constellation-line overlay.

Source coordinates are [lon, lat] pairs in degrees using GeoJSON's -180..180
longitude convention (RA), which we normalize to the usual 0..360 RA range
used everywhere else in this app (WCS projection, star catalogs). Each
constellation's MultiLineString becomes a list of polylines (point sequences
to connect with straight segments) rather than independent line pairs, since
most points are shared between consecutive segments within a constellation.
"""
import json

IN_PATH = "constellations.lines.raw.json"
OUT_PATH = "../../../app/assets/constellation_lines.json"


def normalize_ra(ra_deg):
    return ra_deg + 360.0 if ra_deg < 0 else ra_deg


def main():
    with open(IN_PATH, encoding="utf-8") as f:
        data = json.load(f)

    out = []
    for feature in data["features"]:
        polylines = []
        for line in feature["geometry"]["coordinates"]:
            polylines.append([[round(normalize_ra(ra), 4), round(dec, 4)] for ra, dec in line])
        out.append({"id": feature["id"], "lines": polylines})

    print(f"{len(out)} constellations")
    total_points = sum(len(pl) for c in out for pl in c["lines"])
    print(f"{total_points} total polyline points")
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"))
    print(f"Wrote {OUT_PATH}")


if __name__ == "__main__":
    main()
