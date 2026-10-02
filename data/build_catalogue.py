"""Build `app/assets/starmap.db` from the catalogues in `raw/`.

What ships with the app is this file and nothing else: 9,110 stars, the 88 constellations, the
IAU boundary table, and a provenance record the app can show. Everything else - where the planets
are, what is above your horizon, the Moon's phase - is computed on the device from a date and a
position, so the app needs no network to show the sky.

Run:  py -3.12 data/sources.py          # fetch the raw catalogues first
      py -3.12 data/build_catalogue.py  # then build

It prints what it measured. Nothing in this file estimates a count it did not count.
"""

from __future__ import annotations

import csv
import json
import sqlite3
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from constellation import constellation_of, load_boundaries
from sources import SOURCES

HERE = Path(__file__).parent
RAW = HERE / "raw"
OUT = HERE.parent / "app" / "assets" / "starmap.db"
ASSET_DIR = HERE.parent / "app" / "assets"

# IAU-CSN is fixed width. Measured off its own header row, which sits at line 13 of the file.
_CSN_NAME = slice(0, 18)
_CSN_DESIGNATION = slice(36, 49)
_CSN_CON = slice(61, 65)
_CSN_TAIL = 82  # from here on the row is whitespace-separated: mag bnd HIP HD RA Dec date notes


@dataclass(frozen=True)
class Star:
    hr: int
    hd: int | None
    designation: str | None
    proper_name: str | None
    ra_deg: float
    dec_deg: float
    vmag: float
    bv: float | None
    spectral_type: str | None
    pm_ra: float | None
    pm_dec: float | None
    parallax: float | None
    constellation: str


def _sexagesimal_to_deg(text: str, *, is_hours: bool) -> float | None:
    """Parse '02 58 16.4' or '-40 18 17' into degrees. None when the field is blank."""
    parts = text.strip().split()
    if len(parts) != 3:
        return None
    sign = -1.0 if parts[0].lstrip().startswith("-") else 1.0
    try:
        a, b, c = abs(float(parts[0])), float(parts[1]), float(parts[2])
    except ValueError:
        return None
    value = sign * (a + b / 60.0 + c / 3600.0)
    return value * 15.0 if is_hours else value


def _float_or_none(text: str) -> float | None:
    text = text.strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def read_iau_names() -> tuple[dict[int, str], dict[int, str]]:
    """IAU-approved proper names, keyed by HR and by HD.

    Two keys because the catalogue's `Designation` column prefers HR but falls back to GJ, HD or a
    survey name. Both maps are returned rather than one merged map so the caller can prefer the HR
    match, which is exact, over the HD match, which is a fallback.
    """
    path = RAW / "iau_csn.txt"
    by_hr: dict[int, str] = {}
    by_hd: dict[int, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip() or line.startswith("#") or line.startswith("$"):
            continue
        if len(line) < _CSN_TAIL:
            continue
        name = line[_CSN_NAME].strip()
        designation = line[_CSN_DESIGNATION].strip()
        if not name:
            continue

        if designation.startswith("HR "):
            hr_text = designation[3:].strip()
            if hr_text.isdigit():
                by_hr.setdefault(int(hr_text), name)

        tail = line[_CSN_TAIL:].split()
        # mag bnd HIP HD ... - HD is the fourth field, '_' when absent.
        if len(tail) >= 4 and tail[3].isdigit():
            by_hd.setdefault(int(tail[3]), name)
    if not by_hr:
        raise RuntimeError(f"no HR-keyed names parsed from {path}; the column layout changed")
    return by_hr, by_hd


def read_stars() -> tuple[list[Star], dict[str, int]]:
    """Parse the Yale catalogue, assign a constellation to every star, and count what was dropped.

    Drops are counted and returned, never silently skipped: a star without coordinates or without
    a magnitude cannot be drawn, and the number of them is a fact about the catalogue worth
    printing.
    """
    bands = load_boundaries(RAW / "constellation_boundaries.tsv")
    by_hr, by_hd = read_iau_names()

    stars: list[Star] = []
    counts = {
        "rows_seen": 0,
        "no_coordinates": 0,
        "no_magnitude": 0,
        "named": 0,
        "bands": len(bands),
    }

    seen_table = False
    for line in (RAW / "bsc5.tsv").read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("#Table"):
            if seen_table:
                break  # the 'notes' table starts here; its rows are not stars
            seen_table = True
            continue
        if line.startswith("#") or not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) < 11 or not fields[0].strip().isdigit():
            continue

        counts["rows_seen"] += 1
        hr = int(fields[0])
        ra_deg = _sexagesimal_to_deg(fields[3], is_hours=True)
        dec_deg = _sexagesimal_to_deg(fields[4], is_hours=False)
        if ra_deg is None or dec_deg is None:
            counts["no_coordinates"] += 1
            continue
        vmag = _float_or_none(fields[5])
        if vmag is None:
            counts["no_magnitude"] += 1
            continue

        hd = int(fields[2].strip()) if fields[2].strip().isdigit() else None
        name = by_hr.get(hr) or (by_hd.get(hd) if hd is not None else None)
        if name:
            counts["named"] += 1

        stars.append(
            Star(
                hr=hr,
                hd=hd,
                designation=fields[1].strip() or None,
                proper_name=name,
                ra_deg=ra_deg,
                dec_deg=dec_deg,
                vmag=vmag,
                bv=_float_or_none(fields[6]),
                spectral_type=fields[7].strip() or None,
                pm_ra=_float_or_none(fields[8]),
                pm_dec=_float_or_none(fields[9]),
                parallax=_float_or_none(fields[10]),
                constellation=constellation_of(ra_deg, dec_deg, bands),
            )
        )
    return stars, counts


def read_constellation_names(abbrs_in_boundaries: set[str]) -> list[tuple[str, str, str, str]]:
    """The curated name table, checked against the authoritative abbreviation set.

    This is the assertion that makes a hand-written data file safe: if the curated keys are not
    exactly the boundary table's 88, the build stops. A typo cannot become a nameless
    constellation in the app.
    """
    rows: list[tuple[str, str, str, str]] = []
    with (HERE / "constellations.csv").open(encoding="utf-8") as handle:
        lines = [line for line in handle if not line.startswith("#")]
    for row in csv.DictReader(lines):
        rows.append((row["abbr"], row["latin"], row["genitive"], row["english"]))

    curated = {r[0] for r in rows}
    missing = sorted(abbrs_in_boundaries - curated)
    extra = sorted(curated - abbrs_in_boundaries)
    if missing or extra:
        raise RuntimeError(
            "constellations.csv does not match the Davenhall boundary table.\n"
            f"  in boundaries but not curated: {missing}\n"
            f"  curated but not in boundaries: {extra}"
        )
    if len(rows) != len(curated):
        raise RuntimeError(f"constellations.csv has duplicate abbreviations ({len(rows)} rows)")
    return rows


_SCHEMA = """
CREATE TABLE stars (
    hr              INTEGER PRIMARY KEY,
    hd              INTEGER,
    designation     TEXT,
    proper_name     TEXT,
    ra_deg          REAL NOT NULL,
    dec_deg         REAL NOT NULL,
    vmag            REAL NOT NULL,
    bv              REAL,
    spectral_type   TEXT,
    pm_ra_arcsec_yr REAL,
    pm_dec_arcsec_yr REAL,
    parallax_arcsec REAL,
    constellation   TEXT NOT NULL REFERENCES constellations(abbr)
);
CREATE INDEX stars_by_magnitude ON stars(vmag);
CREATE INDEX stars_by_constellation ON stars(constellation);

CREATE TABLE constellations (
    abbr     TEXT PRIMARY KEY,
    latin    TEXT NOT NULL,
    genitive TEXT NOT NULL,
    english  TEXT NOT NULL
);

-- The IAU boundaries, kept in the app so the device can answer "which constellation is the Sun
-- actually in today" without shipping a second copy of this logic.
CREATE TABLE constellation_boundaries (
    seq           INTEGER PRIMARY KEY,
    ra_low_hours  REAL NOT NULL,
    ra_up_hours   REAL NOT NULL,
    dec_low_deg   REAL NOT NULL,
    constellation TEXT NOT NULL REFERENCES constellations(abbr)
);

-- Provenance, so the app can show where its numbers came from instead of asserting them.
CREATE TABLE sources (
    filename TEXT PRIMARY KEY,
    title    TEXT NOT NULL,
    url      TEXT NOT NULL,
    licence  TEXT NOT NULL,
    note     TEXT NOT NULL
);

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


def write_database(
    stars: list[Star],
    names: list[tuple[str, str, str, str]],
    counts: dict[str, int],
) -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        OUT.unlink()
    connection = sqlite3.connect(OUT)
    try:
        connection.executescript(_SCHEMA)
        connection.executemany(
            "INSERT INTO constellations (abbr, latin, genitive, english) VALUES (?,?,?,?)", names
        )
        bands = load_boundaries(RAW / "constellation_boundaries.tsv")
        connection.executemany(
            "INSERT INTO constellation_boundaries "
            "(seq, ra_low_hours, ra_up_hours, dec_low_deg, constellation) VALUES (?,?,?,?,?)",
            [(b.seq, b.ra_low_h, b.ra_up_h, b.dec_low_deg, b.constellation) for b in bands],
        )
        connection.executemany(
            "INSERT INTO stars (hr, hd, designation, proper_name, ra_deg, dec_deg, vmag, bv,"
            " spectral_type, pm_ra_arcsec_yr, pm_dec_arcsec_yr, parallax_arcsec, constellation)"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [
                (
                    s.hr, s.hd, s.designation, s.proper_name, s.ra_deg, s.dec_deg, s.vmag, s.bv,
                    s.spectral_type, s.pm_ra, s.pm_dec, s.parallax, s.constellation,
                )
                for s in stars
            ],
        )
        connection.executemany(
            "INSERT INTO sources (filename, title, url, licence, note) VALUES (?,?,?,?,?)",
            [(s.filename, s.title, s.url, s.licence, s.note) for s in SOURCES],
        )
        connection.executemany(
            "INSERT INTO meta (key, value) VALUES (?,?)",
            [
                ("built_utc", datetime.now(UTC).isoformat(timespec="seconds")),
                ("star_count", str(len(stars))),
                ("named_star_count", str(counts["named"])),
                ("constellation_count", str(len(names))),
                ("boundary_band_count", str(counts["bands"])),
                ("star_equinox", "J2000.0"),
                ("boundary_equinox", "B1875.0"),
                ("magnitude_band", "V (Johnson)"),
            ],
        )
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()


def write_app_asset(stars: list[Star], names: list[tuple[str, str, str, str]]) -> Path:
    """Emit the same catalogue as a compact JSON asset for the app to load.

    Why both this and the SQLite file. The .db is the canonical build artefact - it carries the
    boundary table, the provenance and the foreign keys, and it is what `tests/test_catalogue.py`
    asserts against. But reading SQLite from Flutter needs a native plugin, and native plugins do
    not work on the web, which is the one platform this machine can actually run the app on. So
    the app reads this instead: arrays rather than objects to keep it small, one row per star, no
    duplication of meaning - everything here is copied straight out of the stars written above.

    Row layout, documented here because array indices are unreadable otherwise:
        [hr, ra_deg, dec_deg, vmag, bv, constellation, proper_name]
    """
    asset = ASSET_DIR / "stars.json"
    asset.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "format": "starmap-stars-1",
        "built_utc": datetime.now(UTC).isoformat(timespec="seconds"),
        "equinox": "J2000.0",
        "magnitude_band": "V (Johnson)",
        "source": SOURCES[0].title,
        "columns": ["hr", "ra_deg", "dec_deg", "vmag", "bv", "constellation", "proper_name"],
        "constellations": {
            abbr: {"latin": latin, "genitive": genitive, "english": english}
            for abbr, latin, genitive, english in names
        },
        "stars": [
            [s.hr, round(s.ra_deg, 6), round(s.dec_deg, 6), s.vmag, s.bv,
             s.constellation, s.proper_name]
            for s in sorted(stars, key=lambda s: s.vmag)
        ],
        # The IAU boundaries, in the B1875 equinox they are defined in. Carried into the app so
        # the device can answer "which constellation is the Sun really in today" - the question
        # that makes the difference between an astrological sign and the actual sky visible.
        # Order is load-bearing: the first matching band wins, so the sequence is preserved.
        "boundary_equinox": "B1875.0",
        "boundary_columns": ["ra_low_hours", "ra_up_hours", "dec_low_deg", "constellation"],
        "boundaries": [
            [b.ra_low_h, b.ra_up_h, b.dec_low_deg, b.constellation]
            for b in load_boundaries(RAW / "constellation_boundaries.tsv")
        ],
    }
    asset.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    return asset


def main() -> int:
    for source in SOURCES:
        if not (RAW / source.filename).exists():
            print(
                f"missing {RAW / source.filename}\nRun: py -3.12 data/sources.py", file=sys.stderr
            )
            return 1

    stars, counts = read_stars()
    bands = load_boundaries(RAW / "constellation_boundaries.tsv")
    names = read_constellation_names({b.constellation for b in bands})
    write_database(stars, names, counts)

    asset = write_app_asset(stars, names)
    size = OUT.stat().st_size
    brightest = min(stars, key=lambda s: s.vmag)
    print(f"built {OUT}  ({size:,} bytes)")
    print(f"  rows read            {counts['rows_seen']:,}")
    print(f"  stars written        {len(stars):,}")
    print(f"  dropped, no coords   {counts['no_coordinates']:,}")
    print(f"  dropped, no mag      {counts['no_magnitude']:,}")
    print(f"  IAU proper names     {counts['named']:,}")
    print(f"  constellations       {len(names)}")
    print(f"  boundary bands       {counts['bands']}")
    print(
        f"  brightest            {brightest.proper_name or brightest.designation or brightest.hr}"
        f"  V={brightest.vmag}  {brightest.constellation}"
    )
    print(f"  app asset            {asset.name}  ({asset.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
