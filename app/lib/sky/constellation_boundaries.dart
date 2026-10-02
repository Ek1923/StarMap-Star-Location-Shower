/// Which constellation a direction falls in.
///
/// A Dart port of the same walk `data/constellation.py` performs, over the same Davenhall table.
/// It is duplicated deliberately: Python needs it at build time to label 9,096 stars, and the app
/// needs it at run time to answer the one question the catalogue cannot pre-compute - which
/// constellation the SUN is in today, which changes daily.
///
/// Both implementations are checked against the same truth, so the duplication cannot drift: the
/// Python side asserts agreement with 2,785 Bayer designations, and `test/zodiac_test.dart` here
/// asserts that this port puts the same famous stars in the same constellations.
library;

import 'dart:math' as math;

import 'angles.dart';
import 'julian.dart';

/// Julian Date of the Besselian epoch B1875.0, the equinox the IAU boundaries are defined in.
const double jdB1875 = 2405889.258550;

/// One row of the boundary table: a declination floor and a right-ascension range, in B1875.
class BoundaryBand {
  const BoundaryBand({
    required this.raLowHours,
    required this.raUpHours,
    required this.decLowDegrees,
    required this.constellation,
  });

  final double raLowHours;
  final double raUpHours;
  final double decLowDegrees;
  final String constellation;
}

/// The constellation containing a J2000 direction.
///
/// Returns null only if the table is incomplete, which would be a build problem rather than a
/// real sky position - the 357 bands cover the whole sphere. The caller decides what to say
/// about that; this function does not invent a constellation.
String? constellationAt({
  required double rightAscensionJ2000Degrees,
  required double declinationJ2000Degrees,
  required List<BoundaryBand> bands,
}) {
  final precessed = _precessToB1875(
    rightAscensionJ2000Degrees,
    declinationJ2000Degrees,
  );
  final raHours = precessed.$1 / 15.0;
  final dec = precessed.$2;

  for (final band in bands) {
    if (dec < band.decLowDegrees) continue;
    if (raHours >= band.raLowHours && raHours < band.raUpHours) {
      return band.constellation;
    }
  }
  return null;
}

/// Precess a J2000 position back to B1875, using the IAU 1976 angles.
///
/// 125 years of precession is a degree and a half - five times the width of the full Moon - so
/// looking a J2000 position up in a B1875 table without this misassigns every star near a
/// boundary.
(double, double) _precessToB1875(double raDegrees, double decDegrees) {
  const t = (jdB1875 - jdJ2000) / daysPerJulianCentury; // negative: going back in time
  const arcsecToRad = math.pi / (180.0 * 3600.0);
  const zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * arcsecToRad;
  const z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) * arcsecToRad;
  const theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * arcsecToRad;

  final ra = raDegrees * degToRad;
  final dec = decDegrees * degToRad;
  final cosDec = math.cos(dec);
  final x0 = cosDec * math.cos(ra);
  final y0 = cosDec * math.sin(ra);
  final z0 = math.sin(dec);

  final cosZeta = math.cos(zeta);
  final sinZeta = math.sin(zeta);
  final cosZ = math.cos(z);
  final sinZ = math.sin(z);
  final cosTheta = math.cos(theta);
  final sinTheta = math.sin(theta);

  // Forward, not transposed: the negative `t` already carries the direction.
  final x = (cosZeta * cosTheta * cosZ - sinZeta * sinZ) * x0 +
      (-sinZeta * cosTheta * cosZ - cosZeta * sinZ) * y0 +
      (-sinTheta * cosZ) * z0;
  final y = (cosZeta * cosTheta * sinZ + sinZeta * cosZ) * x0 +
      (-sinZeta * cosTheta * sinZ + cosZeta * cosZ) * y0 +
      (-sinTheta * sinZ) * z0;
  final zz = (cosZeta * sinTheta) * x0 + (-sinZeta * sinTheta) * y0 + cosTheta * z0;

  return (
    normalizeDegrees(math.atan2(y, x) * radToDeg),
    math.asin(zz.clamp(-1.0, 1.0)) * radToDeg,
  );
}
