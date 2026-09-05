"""Build assets/star_names.json: {hip: {"name": ..., "ra_deg": ..., "dec_deg": ...}}

Names come from the IAU Catalog of Star Names (github.com/cyschneck/iau-star-names,
MIT). Coordinates come from our own bundled gaia_merged.bin (source_id == -HIP for
Hipparcos gap-fill stars, per download_gaia_catalog.py's merge convention — already
confirmed against real solves in the M9 spike). Needed so the app can project named
stars through a solved WCS and label them regardless of whether tetra3's solver
happened to include that particular star in its small matched-verification set —
bright named stars are often saturated/filtered out of that set even when clearly
in frame.
"""
import csv
import json
import struct

GAIA_PATH = "../gaia_merged.bin"
IAU_CSV_PATH = "../iau_proper_stars.csv"
OUT_PATH = "../../../app/assets/star_names.json"


def load_hip_names():
    names = {}
    with open(IAU_CSV_PATH, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            hip = row.get("HIP", "").strip()
            name = row.get("Proper Names", "").strip()
            if hip.isdigit() and name:
                names[int(hip)] = name
    return names


def load_hip_coords(hip_set):
    coords = {}
    with open(GAIA_PATH, "rb") as f:
        data = f.read()
    count = struct.unpack("<Q", data[8:16])[0]
    body = data[16:]
    for i in range(count):
        rec = body[i * 36 : (i + 1) * 36]
        source_id, ra, dec, mag, pmra, pmdec = struct.unpack("<qddfff", rec)
        if source_id < 0:
            hip = -source_id
            if hip in hip_set:
                coords[hip] = (ra, dec)
    return coords


def main():
    names = load_hip_names()
    coords = load_hip_coords(set(names.keys()))
    print(f"{len(names)} named stars, {len(coords)} with coordinates in our catalog")

    missing = set(names.keys()) - set(coords.keys())
    if missing:
        print(f"  {len(missing)} named stars have no match in gaia_merged.bin "
              f"(likely fainter than our G<10 cutoff): {sorted(missing)[:10]}...")

    out = {}
    for hip, name in names.items():
        if hip in coords:
            ra, dec = coords[hip]
            out[str(hip)] = {"name": name, "ra_deg": round(ra, 5), "dec_deg": round(dec, 5)}

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"Wrote {len(out)} entries to {OUT_PATH}")


if __name__ == "__main__":
    main()
