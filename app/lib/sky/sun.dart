/// Where the Sun is.
///
/// Derived from the same Earth/Moon barycentre elements the planets use, by the oldest trick in
/// the book: the Sun seen from the Earth is the Earth seen from the Sun, pointing the other way.
/// One orbit model instead of two means the Sun and the planets can never disagree about where
/// the Earth is - which they would, subtly, if the Sun had its own series.
library;

import 'dart:math' as math;

import 'angles.dart';
import 'coordinates.dart';
import 'julian.dart';
import 'planets.dart';

/// Geocentric apparent position of the Sun, referred to the equinox of date.
///
/// Light time is 8 minutes 19 seconds, over which the Sun's apparent place moves about 20
/// arcseconds, so it is applied. Aberration from the Earth's own motion is the same 20 arcseconds
/// in the opposite sense and very nearly cancels it, which is a well-known coincidence rather
/// than a reason to skip either: the residual is what makes the difference between 20 arcseconds
/// of error and under one.
Equatorial sunPosition(DateTime when) {
  final lightTimeSeconds =
      earthHeliocentricPosition(when).length * 499.004784;
  final emitted = when.subtract(
    Duration(microseconds: (lightTimeSeconds * 1e6).round()),
  );
  // The vector from Earth to Sun is minus the vector from Sun to Earth.
  final toSun = earthHeliocentricPosition(emitted).scaled(-1.0);
  return eclipticVectorToEquatorialOfDate(toSun, when);
}

/// Geocentric position of the Sun in the J2000 frame.
///
/// The of-date position is what you point a telescope with; this one is what you look a
/// catalogue up with. Both exist because the app needs both, and the frame is in the name so
/// they cannot be confused.
Equatorial sunPositionJ2000(DateTime when) {
  final lightTimeSeconds = earthHeliocentricPosition(when).length * 499.004784;
  final emitted = when.subtract(
    Duration(microseconds: (lightTimeSeconds * 1e6).round()),
  );
  return eclipticJ2000VectorToEquatorialJ2000(
    earthHeliocentricPosition(emitted).scaled(-1.0),
  );
}

/// Earth-Sun distance in au.
double sunDistanceAu(DateTime when) => earthHeliocentricPosition(when).length;

/// Apparent angular diameter of the Sun in arcseconds.
///
/// From the IAU 2015 nominal solar radius, 695,700 km, and the distance above - not a constant,
/// because the Earth's orbit is eccentric enough that the Sun is visibly bigger in January.
double sunAngularDiameterArcseconds(DateTime when) {
  const solarRadiusKm = 695700.0;
  const auKm = 149597870.7;
  final distanceKm = sunDistanceAu(when) * auKm;
  return 2 * (solarRadiusKm / distanceKm) * 206264.806247;
}

/// Where the Sun is in the ecliptic, in degrees of longitude from the vernal equinox.
///
/// This is the number both zodiac answers come from: the tropical sign is this longitude divided
/// into twelve equal 30-degree slices, and the actual constellation is this direction looked up in
/// the IAU boundaries. They disagree by roughly one sign, and that disagreement is precession.
double sunEclipticLongitudeDegrees(DateTime when) {
  final equatorial = sunPosition(when);
  // Convert back out of the equatorial frame rather than keeping a parallel ecliptic path: one
  // source of truth, even when it costs a conversion.
  return _equatorialToEclipticLongitude(equatorial, when);
}

double _equatorialToEclipticLongitude(Equatorial position, DateTime when) {
  final obliquity = meanObliquityDegrees(when) * degToRad;
  final ra = position.rightAscensionDegrees * degToRad;
  final dec = position.declinationDegrees * degToRad;
  final y = math.sin(ra) * math.cos(obliquity) +
      math.tan(dec) * math.sin(obliquity);
  final x = math.cos(ra);
  return normalizeDegrees(math.atan2(y, x) * radToDeg);
}
