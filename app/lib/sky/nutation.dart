/// Nutation: the small wobble of the Earth's axis on top of precession.
///
/// It was initially left out on the grounds that 17 arcseconds is below the error of the orbital
/// elements. The accuracy test disagreed, and it was right: leaving it out put a systematic floor
/// of 22 to 24 arcseconds under EVERY body - the Sun, Venus, Mercury, Mars and Uranus all landed
/// within an arcsecond of each other despite element errors that differ by a factor of three.
/// A common-mode offset across unrelated orbits is never an orbit problem, it is a frame problem.
///
/// Two things have to move together or it gets worse rather than better:
///   * the position, by the nutation in longitude and the true obliquity
///   * sidereal time, by the equation of the equinoxes
/// Correcting one without the other leaves most of the error in place with the sign flipped.
///
/// Series: the abbreviated IAU 1980 nutation of Meeus, Astronomical Algorithms ch. 22 - the four
/// largest terms of each. Stated accuracy about 0.5 arcseconds in longitude and 0.1 in obliquity,
/// which is an order of magnitude below the best body here.
library;

import 'dart:math' as math;

import 'angles.dart';
import 'julian.dart';

/// Nutation in longitude and obliquity, both in arcseconds.
class Nutation {
  const Nutation({required this.longitudeArcsec, required this.obliquityArcsec});

  final double longitudeArcsec;
  final double obliquityArcsec;
}

Nutation nutation(DateTime when) {
  final t = centuriesSinceJ2000(when);

  // Longitude of the ascending node of the Moon's mean orbit. This single term carries 17 of the
  // 17.2 arcseconds, on an 18.6-year cycle - the one that mattered.
  final omega = (125.04452 - 1934.136261 * t) * degToRad;
  // Mean longitude of the Sun and of the Moon.
  final sunLongitude = (280.4665 + 36000.7698 * t) * degToRad;
  final moonLongitude = (218.3165 + 481267.8813 * t) * degToRad;

  final longitudeArcsec = -17.20 * math.sin(omega) -
      1.32 * math.sin(2 * sunLongitude) -
      0.23 * math.sin(2 * moonLongitude) +
      0.21 * math.sin(2 * omega);

  final obliquityArcsec = 9.20 * math.cos(omega) +
      0.57 * math.cos(2 * sunLongitude) +
      0.10 * math.cos(2 * moonLongitude) -
      0.09 * math.cos(2 * omega);

  return Nutation(
    longitudeArcsec: longitudeArcsec,
    obliquityArcsec: obliquityArcsec,
  );
}

/// True obliquity of the ecliptic in degrees: the mean value plus nutation.
double trueObliquityDegrees(DateTime when) =>
    meanObliquityDegrees(when) + nutation(when).obliquityArcsec / 3600.0;

/// Local APPARENT sidereal time in degrees - mean sidereal time plus the equation of the
/// equinoxes.
///
/// This is the one the horizon calculation must use, because the positions it is given are
/// apparent places referred to the true equinox of date. Pairing an apparent position with mean
/// sidereal time leaves 16 arcseconds of the nutation error in place.
double localApparentSiderealTimeDegrees(DateTime when, double longitudeEastDegrees) =>
    normalizeDegrees(
      localSiderealTimeDegrees(when, longitudeEastDegrees) +
          equationOfTheEquinoxesDegrees(when),
    );

/// The equation of the equinoxes, in degrees.
///
/// The difference between mean and apparent sidereal time. Up to about 1.1 seconds of time, which
/// is 16 arcseconds of sky - the other half of the correction.
double equationOfTheEquinoxesDegrees(DateTime when) {
  final n = nutation(when);
  final obliquity = trueObliquityDegrees(when) * degToRad;
  return (n.longitudeArcsec * math.cos(obliquity)) / 3600.0;
}
