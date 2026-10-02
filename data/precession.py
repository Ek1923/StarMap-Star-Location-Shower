"""Precess equatorial coordinates from J2000 to B1875.

One job, because one thing needs it: the IAU constellation boundaries are defined in the B1875
equinox, and the star catalogue is in J2000. Looking a J2000 position up in a B1875 table without
precessing first puts stars in the wrong constellation near every boundary - roughly a degree and
a half of error after 125 years, which is five times the width of the full Moon.

Method: the IAU 1976 precession angles (Lieske et al. 1977), applied as a rotation. These are the
angles Roman (1987) assumes, which is the algorithm `constellation.py` implements, so they belong
together.

Pure functions, no I/O, no state - which is what makes `tests/test_precession.py` able to check
them against published positions.
"""

from __future__ import annotations

import math

# Julian Date of the standard epoch J2000.0 (2000 January 1.5 TT).
JD_J2000 = 2451545.0
# Julian Date of the Besselian epoch B1875.0. Besselian years are tropical, not Julian, so this
# is not J2000 minus 125 Julian years: B1875.0 = JD 2405889.258550.
JD_B1875 = 2405889.258550

_ARCSEC_TO_RAD = math.pi / (180.0 * 3600.0)


def precession_angles(jd_from: float, jd_to: float) -> tuple[float, float, float]:
    """The IAU 1976 equatorial precession angles zeta, z and theta, in radians.

    Only the J2000-as-origin form is implemented, because that is the only case this app has.
    Passing anything but J2000 as `jd_from` would silently give a wrong answer, so it raises.
    """
    if jd_from != JD_J2000:
        raise ValueError(
            f"precession_angles is only derived for J2000 as the starting equinox, got {jd_from}. "
            "Extending it needs the full three-angle series with a non-zero origin epoch."
        )
    # Centuries of 36525 days from J2000 to the target equinox. Negative when going back in time.
    t = (jd_to - JD_J2000) / 36525.0
    zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * _ARCSEC_TO_RAD
    z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) * _ARCSEC_TO_RAD
    theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * _ARCSEC_TO_RAD
    return zeta, z, theta


def precess(ra_deg: float, dec_deg: float, jd_to: float = JD_B1875) -> tuple[float, float]:
    """Precess a J2000 position to another equinox. Returns (ra_deg, dec_deg), RA in [0, 360).

    The rotation is written out rather than pulled from a matrix library: it is nine lines, it has
    no dependency, and every term is checkable against the textbook form.
    """
    zeta, z, theta = precession_angles(JD_J2000, jd_to)

    ra = math.radians(ra_deg)
    dec = math.radians(dec_deg)

    cos_dec = math.cos(dec)
    x0 = cos_dec * math.cos(ra)
    y0 = cos_dec * math.sin(ra)
    z0 = math.sin(dec)

    cos_zeta, sin_zeta = math.cos(zeta), math.sin(zeta)
    cos_z, sin_z = math.cos(z), math.sin(z)
    cos_theta, sin_theta = math.cos(theta), math.sin(theta)

    # P = R3(-z) . R2(theta) . R3(-zeta), expanded. This maps J2000 -> the equinox at `jd_to`.
    p11 = cos_zeta * cos_theta * cos_z - sin_zeta * sin_z
    p12 = -sin_zeta * cos_theta * cos_z - cos_zeta * sin_z
    p13 = -sin_theta * cos_z
    p21 = cos_zeta * cos_theta * sin_z + sin_zeta * cos_z
    p22 = -sin_zeta * cos_theta * sin_z + cos_zeta * cos_z
    p23 = -sin_theta * sin_z
    p31 = cos_zeta * sin_theta
    p32 = -sin_zeta * sin_theta
    p33 = cos_theta

    # Applied FORWARD, not transposed. Going back in time is already carried by the angles: `t`
    # is negative for B1875, so zeta, z and theta are negative and P rotates J2000 -> B1875.
    # Transposing as well would reverse it a second time and precess 125 years into the FUTURE.
    # That bug was real and measurable: it put Pollux in Cancer and Fomalhaut in Sculptor, and
    # disagreed with the catalogue's own Bayer designations on 389 of 2,785 stars (13.97%).
    x = p11 * x0 + p12 * y0 + p13 * z0
    y = p21 * x0 + p22 * y0 + p23 * z0
    zz = p31 * x0 + p32 * y0 + p33 * z0

    ra_out = math.degrees(math.atan2(y, x)) % 360.0
    dec_out = math.degrees(math.asin(max(-1.0, min(1.0, zz))))
    return ra_out, dec_out


def angular_separation_deg(
    ra1_deg: float, dec1_deg: float, ra2_deg: float, dec2_deg: float
) -> float:
    """Great-circle angle between two positions, in degrees.

    The haversine form, not the plain spherical cosine rule: the cosine rule loses precision at
    small separations, and small separations are exactly what a test comparing a computed position
    against a published one measures.
    """
    ra1, dec1 = math.radians(ra1_deg), math.radians(dec1_deg)
    ra2, dec2 = math.radians(ra2_deg), math.radians(dec2_deg)
    d_ra = ra2 - ra1
    d_dec = dec2 - dec1
    a = (
        math.sin(d_dec / 2.0) ** 2
        + math.cos(dec1) * math.cos(dec2) * math.sin(d_ra / 2.0) ** 2
    )
    return math.degrees(2.0 * math.asin(min(1.0, math.sqrt(a))))
