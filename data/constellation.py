"""Which of the 88 constellations a position falls in.

Roman's (1987) algorithm, over the Davenhall & Leggett boundary table: precess the position to
B1875, then walk the table in order and take the first band whose declination floor is at or
below the position and whose right-ascension range contains it. The table is ordered so that the
first match is the right one; order is load-bearing, which is why `load_boundaries` keeps the
catalogue's own sequence number and sorts by it rather than trusting file order.

Pure except for reading the table once. No network, no clock.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from precession import precess


@dataclass(frozen=True)
class Band:
    """One row of the boundary table: a declination floor and an RA range, in B1875."""

    seq: int
    ra_low_h: float
    ra_up_h: float
    dec_low_deg: float
    constellation: str


def load_boundaries(path: Path) -> tuple[Band, ...]:
    """Parse the VizieR VI/42 TSV. Stops at a second `#Table`, keeps catalogue order."""
    bands: list[Band] = []
    seen_table = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("#Table"):
            # VizieR concatenates tables; the first `#Table` marker is the one we want, a second
            # means a different table has started and its rows are not boundaries.
            if seen_table:
                break
            seen_table = True
            continue
        if line.startswith("#") or not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) < 5 or not fields[0].strip().isdigit():
            continue
        try:
            bands.append(
                Band(
                    seq=int(fields[0]),
                    ra_low_h=float(fields[1]),
                    ra_up_h=float(fields[2]),
                    dec_low_deg=float(fields[3]),
                    constellation=fields[4].strip(),
                )
            )
        except ValueError:
            # A row that does not parse is a parser bug or a changed format, not something to
            # skip quietly - but one unparseable row should not lose the other 359, so it is
            # counted by the caller via the returned length.
            continue

    if not bands:
        raise RuntimeError(f"no boundary rows parsed from {path}")
    return tuple(sorted(bands, key=lambda b: b.seq))


def constellation_of(ra_j2000_deg: float, dec_j2000_deg: float, bands: tuple[Band, ...]) -> str:
    """The IAU constellation containing a J2000 position.

    Raises rather than guessing if nothing matches: the table covers the whole sphere, so a miss
    means the position is malformed or the table was parsed wrong, and a silent "unknown" in
    9,110 stars is the kind of thing nobody notices until the app looks wrong.
    """
    ra_h, dec = _to_b1875_hours(ra_j2000_deg, dec_j2000_deg)
    for band in bands:
        if dec < band.dec_low_deg:
            continue
        if band.ra_low_h <= ra_h < band.ra_up_h:
            return band.constellation
    raise RuntimeError(
        f"no constellation band matched RA {ra_h:.4f}h Dec {dec:.4f} (B1875), from J2000 "
        f"RA {ra_j2000_deg:.4f} Dec {dec_j2000_deg:.4f}"
    )


def _to_b1875_hours(ra_j2000_deg: float, dec_j2000_deg: float) -> tuple[float, float]:
    ra_deg, dec_deg = precess(ra_j2000_deg, dec_j2000_deg)
    return ra_deg / 15.0, dec_deg
