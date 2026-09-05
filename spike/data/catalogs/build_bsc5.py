"""Parse the Yale Bright Star Catalog (BSC5, public domain / freely
redistributable — Hoffleit & Warren 1991, hosted at
tdc-www.harvard.edu/catalogs/bsc5.html) into a compact designation catalog:
Flamsteed-number + constellation abbreviation (e.g. "13 Vul", "39 Cyg"),
matching the style astrometry.net's own annotated_display uses — the
reference the user is comparing against. This is deliberately a different,
much denser catalog than star_names.json's ~67 popular names (Deneb, Vega,
...): BSC5 covers all 9,110 naked-eye stars (down to ~V=6.5), so most
matched-verification stars in a typical frame will actually have one.

Byte layout (1-indexed, from ybsc5.readme):
  1-4    HR number
  5-14   Name: Flamsteed (3) + Bayer greek-letter abbrev (3) + space + constellation (3)
  76-79  RA J2000 (h, min)
  80-83  RA J2000 (sec, F4.1)
  84     Dec sign
  85-90  Dec J2000 (deg, arcmin, arcsec)
  103-107 V magnitude
"""
import json

IN_PATH = "bsc5.dat"
OUT_PATH = "../../../app/assets/bsc5_designations.json"
MAG_LIMIT = 6.5  # naked-eye limit; keeps the file small and the overlay uncluttered


def parse_line(line):
    if len(line) < 107:
        return None
    hr = line[0:4].strip()
    name_field = line[4:14]
    flamsteed = name_field[0:3].strip()
    constellation = name_field[7:10].strip()

    ra_h = line[75:77].strip()
    ra_m = line[77:79].strip()
    ra_s = line[79:83].strip()
    dec_sign = line[83:84].strip()
    dec_d = line[84:86].strip()
    dec_m = line[86:88].strip()
    dec_s = line[88:90].strip()
    vmag_str = line[102:107].strip()

    if not (ra_h and dec_d and constellation and vmag_str):
        return None  # star removed from catalog / no current position
    try:
        vmag = float(vmag_str)
    except ValueError:
        return None
    if vmag > MAG_LIMIT:
        return None

    ra_deg = (int(ra_h) + int(ra_m) / 60 + float(ra_s) / 3600) * 15.0
    dec_abs = int(dec_d) + int(dec_m) / 60 + int(dec_s) / 3600
    dec_deg = -dec_abs if dec_sign == "-" else dec_abs

    if flamsteed.isdigit():
        label = f"{flamsteed} {constellation}"
    else:
        return None  # Bayer-only / unnamed stars: skip for this designation-style catalog

    return {
        "hr": hr,
        "label": label,
        "mag": vmag,
        "ra_deg": round(ra_deg, 5),
        "dec_deg": round(dec_deg, 5),
    }


def main():
    with open(IN_PATH, encoding="latin-1") as f:
        lines = f.readlines()

    out = []
    for line in lines:
        entry = parse_line(line)
        if entry:
            out.append(entry)

    print(f"{len(lines)} BSC5 records, {len(out)} with a Flamsteed designation and mag <= {MAG_LIMIT}")
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"Wrote {OUT_PATH}")


if __name__ == "__main__":
    main()
