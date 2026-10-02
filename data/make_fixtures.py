"""Ask JPL Horizons where the Sun, Moon and planets actually were, and save it as test fixtures.

This file is the reason the app can claim to be factual. The Dart engine computes positions on the
device from a date and a latitude/longitude; these fixtures are what that computation is checked
against, and they come from NASA/JPL's own ephemeris rather than from another approximation.

What is asked for, per body per observing site, at four epochs:
    apparent RA/Dec, azimuth/elevation, visual magnitude, illuminated fraction,
    angular diameter, distance and range-rate

Four sites on purpose: two northern, one southern, one on the equator. A horizon calculation can
be wrong in a way that only shows up in one hemisphere - a sign error in latitude looks perfect
from Amsterdam and puts the Moon underground in Sydney.

Run:  py -3.12 data/make_fixtures.py
      -> app/test/fixtures/horizons.json   (36 requests, about a minute)

Re-running overwrites the file. The fixtures are COMMITTED, so the Dart tests need no network and
so a change in them shows up as a reviewable diff instead of silently moving the goalposts.
"""

from __future__ import annotations

import json
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

OUT = Path(__file__).parent.parent / "app" / "test" / "fixtures" / "horizons.json"
API = "https://ssd.jpl.nasa.gov/api/horizons.api"
_USER_AGENT = "StarMap/0.1 (+https://github.com/Ek1923/StarMap-Star-Location-Shower)"

# Horizons body codes. 10 is the Sun, 301 the Moon, n99 a planet barycentre-free body centre.
BODIES: dict[str, str] = {
    "sun": "10",
    "moon": "301",
    "mercury": "199",
    "venus": "299",
    "mars": "499",
    "jupiter": "599",
    "saturn": "699",
    "uranus": "799",
    "neptune": "899",
}

# East longitude, latitude, altitude in km - the order Horizons wants in SITE_COORD.
SITES: dict[str, tuple[float, float, float]] = {
    "amsterdam": (4.9041, 52.3676, 0.0),
    "istanbul": (28.9784, 41.0082, 0.0),
    "sydney": (151.2093, -33.8688, 0.0),
    "quito": (-78.4678, -0.1807, 2.850),
}

# Spread across seasons and across both sides of now, so a test cannot pass by being right only
# near the date it was written.
EPOCHS: tuple[str, ...] = (
    "2025-12-25 18:00",
    "2026-10-03 21:00",
    "2027-01-15 03:00",
    "2027-06-21 12:00",
)

_MONTHS = {
    "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
    "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
}


def _parse_number(text: str) -> float | None:
    text = text.strip()
    if not text or text in {"n.a.", "*", "/*"}:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _parse_epoch(text: str) -> str:
    """'2026-Oct-03 21:00:00.000' -> '2026-10-03T21:00:00Z'."""
    date_part, time_part = text.strip().split(" ", 1)
    year, month_name, day = date_part.split("-")
    moment = datetime(
        int(year),
        _MONTHS[month_name],
        int(day),
        int(time_part[0:2]),
        int(time_part[3:5]),
        int(time_part[6:8]),
        tzinfo=UTC,
    )
    return moment.isoformat().replace("+00:00", "Z")


def fetch(body: str, command: str, site: str) -> list[dict[str, object]]:
    lon, lat, alt = SITES[site]
    params = [
        ("format", "text"),
        ("COMMAND", f"'{command}'"),
        ("EPHEM_TYPE", "OBSERVER"),
        ("CENTER", "'coord@399'"),
        ("COORD_TYPE", "GEODETIC"),
        ("SITE_COORD", f"'{lon},{lat},{alt}'"),
        ("TLIST", " ".join(f"'{e}'" for e in EPOCHS)),
        ("QUANTITIES", "'2,4,9,10,13,20'"),
        ("ANG_FORMAT", "DEG"),
        ("CSV_FORMAT", "YES"),
        ("EXTRA_PREC", "YES"),
    ]
    url = f"{API}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    with urllib.request.urlopen(request, timeout=180) as response:
        text = response.read().decode("utf-8", errors="replace")

    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.startswith("$$SOE"))
        end = next(i for i, line in enumerate(lines) if line.startswith("$$EOE"))
    except StopIteration:
        raise RuntimeError(
            f"Horizons returned no ephemeris block for {body} at {site}. First 400 characters of "
            f"the reply:\n{text[:400]}"
        ) from None

    rows: list[dict[str, object]] = []
    for line in lines[start + 1 : end]:
        fields = line.split(",")
        if len(fields) < 13:
            raise RuntimeError(f"{body}/{site}: expected >=13 CSV fields, got {len(fields)}: {line}")
        rows.append(
            {
                "body": body,
                "site": site,
                "utc": _parse_epoch(fields[0]),
                "ra_deg": _parse_number(fields[3]),
                "dec_deg": _parse_number(fields[4]),
                "azimuth_deg": _parse_number(fields[5]),
                "elevation_deg": _parse_number(fields[6]),
                "apparent_magnitude": _parse_number(fields[7]),
                "surface_brightness": _parse_number(fields[8]),
                "illuminated_percent": _parse_number(fields[9]),
                "angular_diameter_arcsec": _parse_number(fields[10]),
                "distance_au": _parse_number(fields[11]),
                "range_rate_km_s": _parse_number(fields[12]),
            }
        )

    if len(rows) != len(EPOCHS):
        raise RuntimeError(
            f"{body}/{site}: asked for {len(EPOCHS)} epochs, got {len(rows)} rows back"
        )
    return rows


def main() -> int:
    observations: list[dict[str, object]] = []
    for body, command in BODIES.items():
        for site in SITES:
            rows = fetch(body, command, site)
            observations.extend(rows)
            print(f"  {body:<8} {site:<10} {len(rows)} epochs")

    payload = {
        "generated_utc": datetime.now(UTC).isoformat(timespec="seconds"),
        "source": "NASA/JPL Horizons API, https://ssd.jpl.nasa.gov/api/horizons.api",
        "source_note": (
            "Apparent (a-app) coordinates for a geodetic surface observer, which is what an "
            "app showing 'what is above you' needs: refraction-free apparent place, corrected "
            "for light time, aberration and nutation. Quantities 2,4,9,10,13,20."
        ),
        "units": {
            "ra_deg": "degrees, apparent, equinox of date",
            "dec_deg": "degrees, apparent, equinox of date",
            "azimuth_deg": "degrees east of north",
            "elevation_deg": "degrees above the horizon, negative below",
            "angular_diameter_arcsec": "arcseconds",
            "distance_au": "astronomical units, observer to body centre",
        },
        "sites": {
            name: {"lon_east_deg": lon, "lat_deg": lat, "alt_km": alt}
            for name, (lon, lat, alt) in SITES.items()
        },
        "epochs_utc": list(EPOCHS),
        "observations": observations,
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")
    print(
        f"\nwrote {OUT}  ({OUT.stat().st_size:,} bytes)\n"
        f"  {len(BODIES)} bodies x {len(SITES)} sites x {len(EPOCHS)} epochs "
        f"= {len(observations)} observations"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
