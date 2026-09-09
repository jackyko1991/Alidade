"""Parse OpenNGC (Mattia Verga, CC-BY-SA 4.0 -
github.com/mattiaverga/OpenNGC) into a compact deep-sky-object catalog for
Alidade's target picker's "Deep sky" category: NGC/IC, plus Messier and
Caldwell cross-referenced onto the same OpenNGC coordinates/magnitudes so
each object appears exactly once however it's searched for.

Run order matters: this script reads the already-generated
`../../../app/assets/messier.json` (run build_messier.py first) so the
Messier popular nicknames aren't duplicated in a second table here.

Input files, fetched locally next to this script before running it (like
every other *_raw.* / *.dat input in this directory, these are gitignored,
not committed - a from-scratch checkout regenerates deepsky.json only
after fetching them):
  ngc_raw.csv          - OpenNGC's database_files/NGC.csv
  ngc_addendum_raw.csv - OpenNGC's database_files/addendum.csv (non-NGC/IC
                         objects OpenNGC still tracks - dark nebulae, star
                         clusters, and a handful of Caldwell objects that
                         have no NGC/IC number of their own, e.g. the Cave
                         Nebula and the Hyades)
    curl -sL -o ngc_raw.csv \
      https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/NGC.csv
    curl -sL -o ngc_addendum_raw.csv \
      https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/addendum.csv
Both semicolon-delimited; see NGC_guide.txt in the OpenNGC repo for the
full column reference.

Output: `../../../app/assets/deepsky.json`, a positional array-of-arrays
(cheaper to parse than keyed objects at this row count - see
SkyTarget.fromRow's doc comment in sky_target.dart for the exact field
order):
  [id, name|null, type, constellation, mag|null, ra_deg, dec_deg, aliases]

NOTE ON LICENSING: OpenNGC is CC-BY-SA 4.0, share-alike - a stricter
license than this repo's own MIT. deepsky.json is kept as its own
standalone, separately-attributed asset for exactly that reason (see
about_screen.dart's credits card and this repo's LICENSE file); it must
never be merged into a mixed-license asset.
"""

import csv
import json
import re

IN_NGC = "ngc_raw.csv"
IN_ADDENDUM = "ngc_addendum_raw.csv"
IN_MESSIER = "../../../app/assets/messier.json"
OUT_PATH = "../../../app/assets/deepsky.json"

# Rows whose Type is one of these are dropped entirely:
#   Dup   - duplicate entry for an object already listed under another name
#   NonEx - historical entry now known not to exist
#   Nova  - a transient stellar outburst, not a fixed deep-sky object
#   *     - a foreground star, misidentified as a nebula by early observers
#   **    - a double star; Alidade's Double Stars category (build_wds.py)
#           is the sole source for those, so as not to show the same pair
#           twice under two different catalogs with two different formats
DROPPED_TYPES = {"Dup", "NonEx", "Nova", "*", "**"}

TYPE_LABELS = {
    "G": "Galaxy",
    "GPair": "Galaxy Pair",
    "GTrpl": "Galaxy Triplet",
    "GGroup": "Galaxy Group",
    "PN": "Planetary Nebula",
    "OCl": "Open Cluster",
    "GCl": "Globular Cluster",
    "Cl+N": "Cluster with Nebulosity",
    "Neb": "Nebula",
    "EmN": "Emission Nebula",
    "RfN": "Reflection Nebula",
    "SNR": "Supernova Remnant",
    "HII": "HII Region",
    "*Ass": "Star Association",
    "DrkN": "Dark Nebula",
    "Other": "Other",
}

# Caldwell number -> the OpenNGC row it resolves to. Derived from the
# standard Caldwell-to-NGC/IC cross-reference; four objects (marked "C0xx")
# have no NGC/IC number of their own and are instead their own addendum.csv
# rows using their Caldwell number as the OpenNGC "Name". Multi-object
# designations (e.g. the Veil Complex's "NGC 6992/5", the Rosette's
# "NGC 2237-9") resolve to their first/primary member; the rest are close
# enough in the sky and by name that a search still finds them via the
# picker's substring/word matching.
CALDWELL = {
    1: "NGC0188", 2: "NGC0040", 3: "NGC4236", 4: "NGC7023", 5: "IC0342",
    6: "NGC6543", 7: "NGC2403", 8: "NGC0559", 9: "C009", 10: "NGC0663",
    11: "NGC7635", 12: "NGC6946", 13: "NGC0457", 14: "C014", 15: "NGC6826",
    16: "NGC7243", 17: "NGC0147", 18: "NGC0185", 19: "IC5146", 20: "NGC7000",
    21: "NGC4449", 22: "NGC7662", 23: "NGC0891", 24: "NGC1275", 25: "NGC2419",
    26: "NGC4244", 27: "NGC6888", 28: "NGC0752", 29: "NGC5005", 30: "NGC7331",
    31: "IC0405", 32: "NGC4631", 33: "NGC6992", 34: "NGC6960", 35: "NGC4889",
    36: "NGC4559", 37: "NGC6885", 38: "NGC4565", 39: "NGC2392", 40: "NGC3626",
    41: "C041", 42: "NGC7006", 43: "NGC7814", 44: "NGC7479", 45: "NGC5248",
    46: "NGC2261", 47: "NGC6934", 48: "NGC2775", 49: "NGC2237", 50: "NGC2244",
    51: "IC1613", 52: "NGC4697", 53: "NGC3115", 54: "NGC2506", 55: "NGC7009",
    56: "NGC0246", 57: "NGC6822", 58: "NGC2360", 59: "NGC3242", 60: "NGC4038",
    61: "NGC4039", 62: "NGC0247", 63: "NGC7293", 64: "NGC2362", 65: "NGC0253",
    66: "NGC5694", 67: "NGC1097", 68: "NGC6729", 69: "NGC6302", 70: "NGC0300",
    71: "NGC2477", 72: "NGC0055", 73: "NGC1851", 74: "NGC3132", 75: "NGC6124",
    76: "NGC6231", 77: "NGC5128", 78: "NGC6541", 79: "NGC3201", 80: "NGC5139",
    81: "NGC6352", 82: "NGC6193", 83: "NGC4945", 84: "NGC5286", 85: "IC2391",
    86: "NGC6397", 87: "NGC1261", 88: "NGC5823", 89: "NGC6087", 90: "NGC2867",
    91: "NGC3532", 92: "NGC3372", 93: "NGC6752", 94: "NGC4755", 95: "NGC6025",
    96: "NGC2516", 97: "NGC3766", 98: "NGC4609", 99: "C099", 100: "IC2944",
    101: "NGC6744", 102: "IC2602", 103: "NGC2070", 104: "NGC0362",
    105: "NGC4833", 106: "NGC0104", 107: "NGC6101", 108: "NGC4372",
    109: "NGC3195",
}

MAX_EXTRA_ALIASES = 4

# B-Mag (blue) runs systematically brighter than V-Mag (visual) for a red
# object and fainter for a blue one; galaxies and most nebulae read red, so
# a rough color offset gets a fallback estimate onto roughly the same scale
# as a true V-Mag rather than leaving it uncorrected.
BMAG_TO_VMAG_OFFSET = {"G": -0.8, "GPair": -0.8, "GTrpl": -0.8, "GGroup": -0.8}
DEFAULT_BMAG_OFFSET = -0.5


def parse_ra(ra_str):
    h, m, s = (float(x) for x in ra_str.split(":"))
    return (h + m / 60 + s / 3600) * 15.0


def parse_dec(dec_str):
    sign = -1.0 if dec_str.strip().startswith("-") else 1.0
    d, m, s = (abs(float(x)) for x in dec_str.replace("-", "").split(":"))
    return sign * (d + m / 60 + s / 3600)


def load_rows(path):
    try:
        with open(path, encoding="utf-8") as f:
            return list(csv.DictReader(f, delimiter=";"))
    except FileNotFoundError:
        raise SystemExit(
            f"{path} not found - see this script's module docstring for the "
            "curl command to fetch it (not committed; regenerated locally)."
        )


def magnitude(row):
    v = row.get("V-Mag", "").strip()
    if v:
        return round(float(v), 2)
    b = row.get("B-Mag", "").strip()
    if b:
        offset = BMAG_TO_VMAG_OFFSET.get(row["Type"], DEFAULT_BMAG_OFFSET)
        return round(float(b) + offset, 2)
    return None


def aliases_for(row):
    out = []
    identifiers = row.get("Identifiers", "").strip()
    if identifiers:
        out.extend(x.strip() for x in identifiers.split(",") if x.strip())
    return out[:MAX_EXTRA_ALIASES]


def display_name(row):
    common = row.get("Common names", "").strip()
    if not common:
        return None
    # A handful of rows list several common names comma-separated (e.g.
    # "Double Cluster,h & chi Persei"); the first is the most recognizable.
    return common.split(",")[0].strip()


def row_entry(row, object_id, display, aliases):
    return [
        object_id,
        display,
        TYPE_LABELS.get(row["Type"], "Deep Sky Object"),
        row["Const"] or None,
        magnitude(row),
        round(parse_ra(row["RA"]), 5),
        round(parse_dec(row["Dec"]), 5),
        aliases,
    ]


# M102's OpenNGC row carries Type=Dup and an M-column pointing at 101 (its
# own note: "Identification is controversial, here we take NED assumption")
# -- OpenNGC effectively treats M102 as a duplicate observation of M101.
# The traditionally accepted identification (also what build_messier.py's
# MANUAL_COORDS already uses) is NGC 5866, which carries no M-column of its
# own; resolve M102 there explicitly rather than lose it to that dispute.
MESSIER_NGC_OVERRIDES = {102: "NGC5866"}


def main():
    ngc_rows = load_rows(IN_NGC)
    addendum_rows = load_rows(IN_ADDENDUM)
    all_rows = ngc_rows + addendum_rows
    by_name = {row["Name"]: row for row in all_rows}

    with open(IN_MESSIER, encoding="utf-8") as f:
        messier = json.load(f)
    # OpenNGC's own M column ("031" for M31) is the authoritative Messier
    # cross-reference; messier_name_by_number supplies the popular nickname
    # already curated in build_messier.py so it isn't retyped here.
    messier_name_by_number = {int(m["id"][1:]): m["name"] for m in messier}

    # Pass 1: resolve every Messier and Caldwell number directly by its own
    # OpenNGC row, looked up by name/M-column rather than found by
    # iterating - so a row OpenNGC itself flags "Dup" or "**" (a double
    # star) still gets included when a historical catalog explicitly
    # designates it (M40 is a genuine double star; a handful of Caldwell
    # open clusters are marked "Dup" of a neighboring NGC number). Pass 2
    # below applies the normal DROPPED_TYPES filter to everything else.
    out = []
    seen_ids = set()
    consumed_names = set()

    m_field_index = {}
    for row in all_rows:
        m_field = row.get("M", "").strip()
        if m_field:
            m_field_index.setdefault(int(m_field), row)

    for messier_num in range(1, 111):
        row = by_name.get(MESSIER_NGC_OVERRIDES.get(messier_num, "")) or m_field_index.get(messier_num)
        if row is None:
            continue  # M40's a genuine gap-check case; see the printed summary
        object_id = f"M{messier_num}"
        aliases = [row["Name"]] + aliases_for(row)
        display = messier_name_by_number.get(messier_num) or display_name(row)
        out.append(row_entry(row, object_id, display, aliases))
        seen_ids.add(object_id)
        consumed_names.add(row["Name"])

    for caldwell_num, designation in CALDWELL.items():
        row = by_name.get(designation)
        object_id = f"C{caldwell_num}"
        if row is None or object_id in seen_ids:
            continue  # already covered above (no object is both M and C)
        aliases = [designation] + aliases_for(row)
        out.append(row_entry(row, object_id, display_name(row), aliases))
        seen_ids.add(object_id)
        consumed_names.add(designation)

    # Pass 2: every remaining row, filtered and labeled the normal way.
    for row in all_rows:
        name = row["Name"]
        if name in consumed_names:
            continue
        if row["Type"] in DROPPED_TYPES or row["Type"] == "Type":
            continue
        if not row["RA"] or not row["Dec"]:
            continue  # a few historical entries have no known position

        if re.match(r"^(NGC|IC)\d+$", name):
            # "NGC0224" -> "NGC 224": drop the zero-padding, keep the
            # catalog's own space convention (matches messier.json's "ngc"
            # field, e.g. "NGC 224").
            prefix = "NGC" if name.startswith("NGC") else "IC"
            object_id = f"{prefix} {int(name[len(prefix):])}"
        else:
            object_id = name

        if object_id in seen_ids:
            continue
        seen_ids.add(object_id)
        out.append(row_entry(row, object_id, display_name(row), aliases_for(row)))

    out.sort(key=lambda e: e[0])
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    with_mag = sum(1 for e in out if e[4] is not None)
    with_name = sum(1 for e in out if e[1] is not None)
    messier_count = sum(1 for e in out if e[0].startswith("M") and e[0][1:].isdigit())
    caldwell_count = sum(1 for e in out if e[0].startswith("C") and e[0][1:].isdigit())
    print(
        f"Wrote {len(out)} deep-sky objects "
        f"({messier_count} Messier, {caldwell_count} Caldwell, "
        f"{with_mag} with a magnitude, {with_name} with a common name)"
    )


if __name__ == "__main__":
    main()
