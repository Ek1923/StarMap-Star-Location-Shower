"""Fetch the catalogues this app is built from, and say exactly where each one came from.

Three sources, no more. Every one was reached from the build machine on 2026-10-03 and the
measured result is recorded beside it, so a future failure is distinguishable from a wrong URL.

No third-party packages. Measured: `urllib` reaches all three over TLS without `certifi` on this
machine, so adding a dependency would buy nothing. (Wikidata's SPARQL endpoint does NOT verify
from Python here - it is deliberately not a source; see `constellations.csv`.)

Run:  py -3.12 data/sources.py          # fetch what is missing
      py -3.12 data/sources.py --force  # refetch everything
"""

from __future__ import annotations

import argparse
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

RAW = Path(__file__).parent / "raw"
_USER_AGENT = "StarMap/0.1 (+https://github.com/Ek1923/StarMap-Star-Location-Shower)"
_TIMEOUT_S = 300


@dataclass(frozen=True)
class Source:
    """One downloaded catalogue, with the provenance the app shows to the user."""

    filename: str
    url: str
    title: str
    licence: str
    note: str
    min_bytes: int


SOURCES: tuple[Source, ...] = (
    Source(
        filename="bsc5.tsv",
        url=(
            "https://vizier.cds.unistra.fr/viz-bin/asu-tsv?-source=V/50&-out.max=unlimited"
            "&-out=HR,Name,HD,RAJ2000,DEJ2000,Vmag,B-V,SpType,pmRA,pmDE,Parallax"
        ),
        title="Yale Bright Star Catalogue, 5th Revised Edition (Hoffleit & Warren 1991)",
        licence="CDS/VizieR, free for research and educational use with attribution",
        note=(
            "9,110 stars to about magnitude 6.5 - the naked-eye sky and nothing more, which is "
            "exactly what this app draws. Served as two tables: the catalogue, then a 'notes' "
            "table that the parser must stop at. Measured 2026-10-03: 9,110 data rows."
        ),
        min_bytes=500_000,
    ),
    Source(
        filename="iau_csn.txt",
        url="https://www.pas.rochester.edu/~emamajek/WGSN/IAU-CSN.txt",
        title="IAU Catalog of Star Names (IAU-CSN), WGSN",
        licence="CC BY 4.0 (IAU)",
        note=(
            "The only officially approved proper names for stars. Fixed-width. Its 'Designation' "
            "column carries 'HR nnnn' and there is an HD column, which is how a name is joined "
            "onto a Yale row. Most stars have no approved name and must stay nameless rather "
            "than be given a popular one."
        ),
        min_bytes=20_000,
    ),
    Source(
        filename="constellation_boundaries.tsv",
        url=(
            "https://vizier.cds.unistra.fr/viz-bin/asu-tsv?-source=VI/42"
            "&-out.max=unlimited&-out.all"
        ),
        title="Catalogue of Constellation Boundary Data (Davenhall & Leggett 1989)",
        licence="CDS/VizieR, free for research and educational use with attribution",
        note=(
            "The IAU constellation boundaries as declination-ordered RA bands, in the B1875 "
            "equinox they were defined in. This is the data Roman's (1987) lookup walks. "
            "Measured 2026-10-03: 357 rows, sequence 1..357 contiguous, covering exactly 88 "
            "constellations. (A naive line count says 360 - VizieR prefixes three header rows.)"
        ),
        min_bytes=10_000,
    ),
)


def fetch(source: Source, *, force: bool = False) -> Path:
    """Download one source into `raw/`, unless it is already there and big enough."""
    target = RAW / source.filename
    if target.exists() and not force:
        size = target.stat().st_size
        if size >= source.min_bytes:
            print(f"  have   {source.filename}  ({size:,} bytes)")
            return target
        print(f"  redo   {source.filename}  (only {size:,} bytes, expected >= {source.min_bytes:,})")

    RAW.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(source.url, headers={"User-Agent": _USER_AGENT})
    print(f"  fetch  {source.filename}  <- {source.url[:72]}...")
    with urllib.request.urlopen(request, timeout=_TIMEOUT_S) as response:
        body = response.read()

    if len(body) < source.min_bytes:
        raise RuntimeError(
            f"{source.filename}: got {len(body):,} bytes, expected at least "
            f"{source.min_bytes:,}. The source changed or the query was rejected - look at the "
            f"body before trusting it:\n{body[:400]!r}"
        )
    # Written only after the size check, so a truncated response never lands in the cache and
    # gets mistaken for a good file on the next run.
    target.write_bytes(body)
    print(f"         wrote {len(body):,} bytes")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="refetch even if the file is present")
    args = parser.parse_args()

    print(f"StarMap sources -> {RAW}")
    failed: list[str] = []
    for source in SOURCES:
        try:
            fetch(source, force=args.force)
        except (urllib.error.URLError, RuntimeError, OSError) as exc:
            print(f"  FAIL   {source.filename}: {exc}", file=sys.stderr)
            failed.append(source.filename)

    if failed:
        print(f"\n{len(failed)} of {len(SOURCES)} sources failed: {', '.join(failed)}")
        return 1
    print(f"\nall {len(SOURCES)} sources present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
