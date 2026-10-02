"""Tests for the built catalogue. stdlib `unittest`, so there is nothing to install.

Run:  py -3.12 -m unittest discover -s data/tests -t data -v

The load-bearing test here is `test_bayer_designations_agree_exactly`. The Yale catalogue labels
2,785 of its stars with a Bayer or Flamsteed designation that names a constellation, and those
labels were assigned independently of this code. Comparing them against the computed constellation
is therefore 2,785 free, independent checks of the precession and the boundary walk together.

It earned its place. The first implementation of `precess` applied the rotation transposed, which
precessed 125 years into the future instead of the past. Every famous star still landed in *a*
constellation, the database still built, and nothing looked wrong - but this test said 389 of
2,785 disagreed (13.97%), with Pollux in Cancer and Fomalhaut in Sculptor. After the fix: 0.
"""

from __future__ import annotations

import sqlite3
import unittest
from pathlib import Path

from constellation import constellation_of, load_boundaries
from precession import JD_B1875, precess

DB = Path(__file__).resolve().parents[2] / "app" / "assets" / "starmap.db"
RAW = Path(__file__).resolve().parents[1] / "raw"


def _db() -> sqlite3.Connection:
    if not DB.exists():
        raise unittest.SkipTest(
            f"{DB} not built. Run: py -3.12 data/sources.py && py -3.12 data/build_catalogue.py"
        )
    return sqlite3.connect(DB)


class TestPrecession(unittest.TestCase):
    def test_right_ascension_decreases_going_back_in_time(self) -> None:
        """The sign check that the original bug would have failed.

        Precession carries the equinox westward at about 50 arcseconds a year, so a position
        precessed from J2000 back to B1875 must come out at a SMALLER right ascension. Measured
        here on the equinox point itself, where the effect is purely in RA.
        """
        ra, _ = precess(0.0, 0.0)
        # Expressed as a signed offset so the wrap at 360 cannot hide a sign error.
        offset = ra - 360.0
        self.assertLess(offset, 0.0, "RA must decrease going from J2000 back to B1875")
        self.assertAlmostEqual(offset, -1.601, delta=0.05)

    def test_total_shift_matches_a_century_and_a_quarter_of_precession(self) -> None:
        """About 1.75 degrees of equinox motion over the interval, as the rate demands.

        50.29 arcsec/yr x 124.998 tropical years = 1.746 degrees. This asserts the magnitude
        rather than the direction, so the two failures are distinguishable.
        """
        zeta, z, theta = _angles()
        self.assertAlmostEqual(abs(theta), 0.6960, delta=0.01)  # degrees
        self.assertAlmostEqual(abs(zeta), 0.8009, delta=0.01)
        self.assertAlmostEqual(abs(z), 0.8006, delta=0.01)

    def test_a_pole_barely_moves_in_declination(self) -> None:
        """Polaris was already near the pole in 1875 and still is - a crude but real bound."""
        _, dec = precess(37.9529, 89.2641)
        self.assertGreater(dec, 88.0)
        self.assertLess(dec, 90.0)


def _angles() -> tuple[float, float, float]:
    import math

    from precession import JD_J2000, precession_angles

    zeta, z, theta = precession_angles(JD_J2000, JD_B1875)
    return math.degrees(zeta), math.degrees(z), math.degrees(theta)


class TestConstellationAssignment(unittest.TestCase):
    """Ten stars nobody argues about, then every star the catalogue labels itself."""

    KNOWN = (
        ("Sirius", "CMa"),
        ("Canopus", "Car"),
        ("Rigil Kentaurus", "Cen"),
        ("Arcturus", "Boo"),
        ("Vega", "Lyr"),
        ("Betelgeuse", "Ori"),
        ("Polaris", "UMi"),
        ("Antares", "Sco"),
        ("Spica", "Vir"),
        ("Deneb", "Cyg"),
        ("Fomalhaut", "PsA"),
        ("Pollux", "Gem"),
        ("Acrux", "Cru"),
    )

    def test_famous_stars_are_in_the_constellation_everyone_knows(self) -> None:
        with _db() as connection:
            for name, expected in self.KNOWN:
                row = connection.execute(
                    "SELECT constellation FROM stars WHERE proper_name = ?", (name,)
                ).fetchone()
                self.assertIsNotNone(row, f"{name} is not in the catalogue under that IAU name")
                self.assertEqual(row[0], expected, f"{name} landed in {row[0]}, expected {expected}")

    def test_bayer_designations_agree_exactly(self) -> None:
        """2,785 independent checks. Zero tolerance, because zero is what it measures.

        `min_checked` guards the guard: without it, a parsing regression that found only three
        designations would pass this test with 0 mismatches and prove nothing.
        """
        with _db() as connection:
            valid = {row[0] for row in connection.execute("SELECT abbr FROM constellations")}
            rows = connection.execute(
                "SELECT hr, designation, constellation FROM stars WHERE designation IS NOT NULL"
            ).fetchall()

        checked = 0
        disagreed: list[str] = []
        for hr, designation, computed in rows:
            parts = designation.split()
            if not parts or parts[-1] not in valid:
                continue
            checked += 1
            if parts[-1] != computed:
                disagreed.append(f"HR {hr} {designation!r}: catalogue {parts[-1]}, computed {computed}")

        self.assertGreaterEqual(
            checked, 2700, f"only {checked} designations parsed; the Name column format changed"
        )
        self.assertEqual(
            disagreed,
            [],
            f"{len(disagreed)} of {checked} stars disagree with their own designation:\n"
            + "\n".join(disagreed[:20]),
        )

    def test_a_position_outside_every_band_is_an_error_not_a_guess(self) -> None:
        """The boundary table covers the whole sphere, so a miss means a parsing bug.

        Asserted by removing the bands that could match and checking it raises rather than
        returning an empty string, because an "unknown" constellation on one star in 9,096 is
        exactly the kind of thing that never gets noticed.
        """
        bands = load_boundaries(RAW / "constellation_boundaries.tsv")
        with self.assertRaises(RuntimeError):
            constellation_of(0.0, 0.0, bands[:0])


class TestDatabase(unittest.TestCase):
    def test_the_counts_are_what_the_build_measured(self) -> None:
        with _db() as connection:
            stars = connection.execute("SELECT COUNT(*) FROM stars").fetchone()[0]
            constellations = connection.execute("SELECT COUNT(*) FROM constellations").fetchone()[0]
            bands = connection.execute(
                "SELECT COUNT(*) FROM constellation_boundaries"
            ).fetchone()[0]
        self.assertEqual(stars, 9096, "9,110 catalogue rows minus 14 with no coordinates")
        self.assertEqual(constellations, 88)
        self.assertEqual(bands, 357, "the Davenhall table has 357 bands, not the 360 lines of TSV")

    def test_every_star_points_at_a_constellation_that_exists(self) -> None:
        with _db() as connection:
            orphans = connection.execute(
                "SELECT COUNT(*) FROM stars s"
                " LEFT JOIN constellations c ON c.abbr = s.constellation"
                " WHERE c.abbr IS NULL"
            ).fetchone()[0]
        self.assertEqual(orphans, 0)

    def test_coordinates_and_magnitudes_are_in_range(self) -> None:
        with _db() as connection:
            bad = connection.execute(
                "SELECT COUNT(*) FROM stars WHERE ra_deg < 0 OR ra_deg >= 360"
                " OR dec_deg < -90 OR dec_deg > 90"
            ).fetchone()[0]
            self.assertEqual(bad, 0)
            faintest, brightest = connection.execute(
                "SELECT MAX(vmag), MIN(vmag) FROM stars"
            ).fetchone()
        self.assertAlmostEqual(brightest, -1.46, delta=0.01, msg="Sirius is the brightest star")
        self.assertLess(faintest, 8.0, "the Yale catalogue stops around magnitude 6.5")

    def test_unnamed_stars_stay_unnamed(self) -> None:
        """Only the IAU's approved names, not popular ones.

        341 of 9,096 have an approved name. Filling the rest in from somewhere would be the single
        easiest way to put a wrong fact in front of the user.
        """
        with _db() as connection:
            named = connection.execute(
                "SELECT COUNT(*) FROM stars WHERE proper_name IS NOT NULL"
            ).fetchone()[0]
        self.assertEqual(named, 341)

    def test_provenance_is_recorded(self) -> None:
        """The app shows where its data came from; that is only possible if it is stored."""
        with _db() as connection:
            sources = connection.execute(
                "SELECT filename, url, licence FROM sources"
            ).fetchall()
            meta = dict(connection.execute("SELECT key, value FROM meta"))
        self.assertEqual(len(sources), 3)
        for filename, url, licence in sources:
            self.assertTrue(url.startswith("https://"), filename)
            self.assertTrue(licence.strip(), filename)
        self.assertEqual(meta["star_equinox"], "J2000.0")
        self.assertEqual(meta["boundary_equinox"], "B1875.0")


if __name__ == "__main__":
    unittest.main()
