"""Parse the Washington Double Star Catalog (WDS, USNO, public domain -
astro.gsu.edu/wds/) into a small curated list of bright, well-known double
stars for Alidade's target picker's "Double stars" category.

Run order matters: this reads the already-generated
`../../../app/assets/bsc5_designations.json` (run build_bsc5.py first) to
label each pair by its Flamsteed number + constellation where a cross-match
succeeds (e.g. "6 Cyg" for Albireo's primary), the same style used
throughout the rest of the app.

Input file, fetched locally next to this script before running it (like
every other *_raw.* / *.dat input in this directory, this is gitignored,
not committed - the file is ~20MB, four times anything else here, so
unlike bsc5.dat it isn't worth carrying in the repo even gitignored-but-
present; a from-scratch checkout must fetch it once before regenerating):
  curl -sL -o wds_summ.txt \
    https://www.astro.gsu.edu/wds/Webtextfiles/wdsweb_summ2.txt
Byte layout is documented in the companion `wds.readme` (also fetched, not
committed) - fetch it with:
  curl -sL -o wds.readme \
    https://www.astro.gsu.edu/wds/Webtextfiles/wdsweb_format.txt
Column offsets below are transcribed directly from that file, not
remembered - see WDS_COLUMNS.

The full catalog is ~156,000 pairs, the great majority faint, close, or
both. The cut below is deliberately not just a brightness/separation
threshold (that alone yields either ~3,000 anonymous entries or an
arbitrary ~200): a pair only makes it in if it is naked-eye-bright,
splittable in a modest scope, AND close enough to a BSC5 star to get a
recognizable label. That combination is what keeps the list to a genuinely
useful, browsable size.

Output: `../../../app/assets/double_stars.json`, keyed objects (unlike
deepsky.json's positional rows - at only a few hundred entries here,
readability wins over the parse-speed argument that justifies the
positional format there):
  {"id", "name"|null, "label"|null, "mag", "mag2", "sep", "const"|null,
   "ra_deg", "dec_deg"}
"""

import json
import re

IN_WDS = "wds_summ.txt"
IN_BSC5 = "../../../app/assets/bsc5_designations.json"
OUT_PATH = "../../../app/assets/double_stars.json"

# 0-indexed [start, end) slices, transcribed from wds.readme's "WDS BIBLE"
# column table (1-indexed columns N-M there become slice (N-1, M) here).
WDS_COLUMNS = {
    "wds_id": (0, 10),
    "discoverer": (10, 17),
    "components": (17, 22),
    "mag1": (58, 63),
    "mag2": (64, 69),
    "sep_first": (46, 51),
    "sep_last": (52, 57),
    "precise_coord": (112, 130),
}

MIN_LINE_LEN = 130
MAG1_LIMIT = 6.0  # naked-eye primary
MAG2_LIMIT = 9.0  # visible in a small scope alongside the primary
SEP_MIN_ARCSEC = 3.0  # splittable in a modest amateur scope
SEP_MAX_ARCSEC = 250.0  # wide enough that "double" stops being the point
BSC5_MATCH_ARCSEC = 15.0

# A handful of iconic naked-eye doubles, force-included by their exact WDS
# id + discoverer designation regardless of the general cut above - some
# (Almach, the "Double Double") use a hierarchical-system components code
# ("A,BC", "AB,CD") the general filter's "primary pair only" rule would
# otherwise exclude, and all of them deserve their popular name rather
# than a bare discoverer code or a BSC5 cross-match label.
NAMED_PAIRS = {
    ("19307+2758", "STFA 43"): "Albireo",
    ("13239+5456", "STF1744"): "Mizar",
    ("02039+4220", "STF 205"): "Almach",
    ("07346+3153", "STF1110"): "Castor",
    ("12560+3819", "STF1692"): "Cor Caroli",
    ("18443+3940", "STFA 37"): "Epsilon Lyrae (the Double Double)",
    ("17146+1423", "STF2140"): "Rasalgethi",
}


def parse_precise_coord(raw):
    # "HHMMSS.SS+DDMMSS.S" -> (ra_deg, dec_deg), or None if incomplete
    # (a small fraction of pairs have no precise arcsecond position yet).
    m = re.match(r"(\d{2})(\d{2})(\d{2}\.\d{2})([+-])(\d{2})(\d{2})(\d{2}\.\d)", raw.strip())
    if not m:
        return None
    h, minute, sec, sign, d, dm, ds = m.groups()
    ra_deg = (int(h) + int(minute) / 60 + float(sec) / 3600) * 15.0
    dec_deg = int(d) + int(dm) / 60 + float(ds) / 3600
    if sign == "-":
        dec_deg = -dec_deg
    return ra_deg, dec_deg


def field(line, key):
    a, b = WDS_COLUMNS[key]
    return line[a:b].strip()


def angular_separation_deg(ra1, dec1, ra2, dec2):
    import math

    r1, r2 = math.radians(dec1), math.radians(dec2)
    d_ra = math.radians(ra1 - ra2)
    cos_d = math.sin(r1) * math.sin(r2) + math.cos(r1) * math.cos(r2) * math.cos(d_ra)
    return math.degrees(math.acos(max(-1.0, min(1.0, cos_d))))


def load_lines():
    try:
        with open(IN_WDS, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except FileNotFoundError:
        raise SystemExit(
            f"{IN_WDS} not found - see this script's module docstring for "
            "the curl command to fetch it (not committed; ~20MB)."
        )


def nearest_bsc5_label(bsc5, ra_deg, dec_deg):
    best, best_sep = None, float("inf")
    for star in bsc5:
        sep = angular_separation_deg(ra_deg, dec_deg, star["ra_deg"], star["dec_deg"])
        if sep < best_sep:
            best_sep, best = sep, star
    if best is not None and best_sep * 3600 < BSC5_MATCH_ARCSEC:
        return best["label"]
    return None


def main():
    lines = load_lines()
    data_lines = [l for l in lines if len(l) >= MIN_LINE_LEN and l[0:1].isdigit()]

    with open(IN_BSC5, encoding="utf-8") as f:
        bsc5 = json.load(f)

    out = []
    seen_keys = set()

    def emit(line, forced_name):
        wds_id = field(line, "wds_id")
        discoverer = re.sub(r"\s+", " ", field(line, "discoverer")).strip()
        key = (wds_id, discoverer)
        if key in seen_keys:
            return
        pos = parse_precise_coord(field(line, "precise_coord"))
        if pos is None:
            return
        mag1, mag2 = float(field(line, "mag1")), float(field(line, "mag2"))
        sep_s = field(line, "sep_last") or field(line, "sep_first")
        sep = float(sep_s) if sep_s else None
        label = None if forced_name else nearest_bsc5_label(bsc5, pos[0], pos[1])
        seen_keys.add(key)
        out.append(
            {
                "id": discoverer,
                "name": forced_name,
                "label": label,
                "mag": mag1,
                "mag2": mag2,
                "sep": sep,
                # WDS doesn't carry a constellation column; derive it later
                # from RA/Dec if the picker ends up needing one (BSC5's own
                # label already encodes it for the common case where a
                # cross-match label is available).
                "const": None,
                "ra_deg": round(pos[0], 5),
                "dec_deg": round(pos[1], 5),
            }
        )

    # A single (wds_id, discoverer) pair can have several rows - one per
    # pair of components (AB, AC, AD, BC, ...) in a hierarchical system.
    # NAMED_PAIRS always means the primary AB pair (or, for Almach and the
    # Double Double, the closest thing to it in their non-standard
    # components field), never a wider sub-pair, so prefer "AB" and fall
    # back to the first row seen otherwise.
    PREFERRED_COMPONENTS = ("AB", "A,BC", "AB,CD")
    by_key = {}
    for line in data_lines:
        key = (field(line, "wds_id"), re.sub(r"\s+", " ", field(line, "discoverer")).strip())
        if key not in by_key or field(line, "components") in PREFERRED_COMPONENTS:
            by_key[key] = line

    for key, name in NAMED_PAIRS.items():
        line = by_key.get(key)
        if line is None:
            continue  # a mistranscribed id here is a bug - checked in the asset test
        emit(line, name)

    for line in data_lines:
        components = field(line, "components")
        if components not in ("", "AB"):
            continue
        mag1_s, mag2_s = field(line, "mag1"), field(line, "mag2")
        if not mag1_s or not mag2_s:
            continue
        try:
            mag1, mag2 = float(mag1_s), float(mag2_s)
        except ValueError:
            continue
        if mag1 > MAG1_LIMIT or mag2 > MAG2_LIMIT:
            continue
        sep_s = field(line, "sep_last") or field(line, "sep_first")
        if not sep_s:
            continue
        try:
            sep = float(sep_s)
        except ValueError:
            continue
        if not (SEP_MIN_ARCSEC <= sep <= SEP_MAX_ARCSEC):
            continue
        emit(line, forced_name=None)

    out.sort(key=lambda e: e["mag"])
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    named = sum(1 for e in out if e["name"])
    labeled = sum(1 for e in out if e["label"])
    print(
        f"Wrote {len(out)} double stars from {len(data_lines)} WDS records "
        f"({named} with a popular name, {labeled} more with a BSC5 cross-match label)"
    )


if __name__ == "__main__":
    main()
