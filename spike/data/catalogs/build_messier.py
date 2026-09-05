"""Parse messier-registry's raw JSON (RA/Dec/NGC/magnitude/constellation,
MIT licensed) into a compact asset for Alidade's free-tier named-object
catalog, adding well-known popular nicknames (public astronomical naming
convention, not sourced from any single copyrighted list)."""
import json

NICKNAMES = {
    "M1": "Crab Nebula",
    "M8": "Lagoon Nebula",
    "M11": "Wild Duck Cluster",
    "M13": "Hercules Cluster",
    "M16": "Eagle Nebula",
    "M17": "Omega Nebula",
    "M20": "Trifid Nebula",
    "M27": "Dumbbell Nebula",
    "M31": "Andromeda Galaxy",
    "M32": "Le Gentil",
    "M33": "Triangulum Galaxy",
    "M35": "Shoe-Buckle Cluster",
    "M42": "Orion Nebula",
    "M43": "De Mairan's Nebula",
    "M44": "Beehive Cluster",
    "M45": "Pleiades",
    "M51": "Whirlpool Galaxy",
    "M57": "Ring Nebula",
    "M63": "Sunflower Galaxy",
    "M64": "Black Eye Galaxy",
    "M65": "Leo Triplet (M65)",
    "M66": "Leo Triplet (M66)",
    "M74": "Phantom Galaxy",
    "M76": "Little Dumbbell Nebula",
    "M77": "Cetus A",
    "M78": "Casper the Friendly Ghost Nebula",
    "M81": "Bode's Galaxy",
    "M82": "Cigar Galaxy",
    "M83": "Southern Pinwheel Galaxy",
    "M92": "Hercules' Cluster #2",
    "M97": "Owl Nebula",
    "M101": "Pinwheel Galaxy",
    "M104": "Sombrero Galaxy",
    "M105": "Leo Trio",
    "M106": "M106 Galaxy",
    "M108": "Surfboard Galaxy",
    "M109": "Vacuum Cleaner Galaxy",
    "M110": "Andromeda's Satellite",
}


# The source dataset omits RA/Dec for these three; well-known public
# J2000 coordinates filled in manually.
MANUAL_COORDS = {
    "M45": ("03:47:24.0", "+24:07:00"),  # Pleiades
    "M102": ("15:06:29.5", "+55:45:48"),  # NGC 5866, Spindle Galaxy
    "M40": ("12:22:12.5", "+58:04:59"),  # Winnecke 4
}


def parse_ra(ra_str):
    h, m, s = (float(x) for x in ra_str.split(":"))
    return (h + m / 60 + s / 3600) * 15.0


def parse_dec(dec_str):
    sign = -1.0 if dec_str.strip().startswith("-") else 1.0
    d, m, s = (abs(float(x)) for x in dec_str.replace("-", "").split(":"))
    return sign * (d + m / 60 + s / 3600)


def main():
    with open("messier_raw.json", encoding="utf-8") as f:
        raw = json.load(f)

    out = []
    for rec in raw:
        f = rec["fields"]
        messier_id = f["messier"]
        ra_str, dec_str = MANUAL_COORDS.get(messier_id, (f.get("ra"), f.get("dec")))
        entry = {
            "id": messier_id,
            "ngc": f.get("ngc"),
            "name": NICKNAMES.get(messier_id),
            "type": f.get("objet", "").split(" / ")[0],
            "constellation": f.get("const"),
            "mag": f.get("mag"),
            "ra_deg": round(parse_ra(ra_str), 5),
            "dec_deg": round(parse_dec(dec_str), 5),
        }
        out.append(entry)

    out.sort(key=lambda e: int(e["id"][1:]))
    with open("../../../app/assets/messier.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"Wrote {len(out)} Messier objects, {sum(1 for e in out if e['name'])} with popular nicknames")


if __name__ == "__main__":
    main()
