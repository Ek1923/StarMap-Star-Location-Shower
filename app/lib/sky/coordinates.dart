/// Turning one kind of sky coordinate into another.
///
/// Three conversions, in the order the app uses them:
///   ecliptic (where orbits live)  ->  equatorial (where catalogues live)
///   J2000 equinox                 ->  equinox of date
///   equatorial                    ->  horizontal (where YOU are, which is the whole point)
library;

import 'dart:math' as math;

import 'angles.dart';
import 'julian.dart';
import 'nutation.dart';

/// A position on the sky, with the equinox it is referred to stated rather than assumed.
///
/// Mixing J2000 and of-date coordinates silently is a 0.36 degree error in 2026 - twenty-one
/// arcminutes, two thirds of the Moon's width - so the equinox is part of the type.
class Equatorial {
  const Equatorial({
    required this.rightAscensionDegrees,
    required this.declinationDegrees,
    required this.equinox,
  });

  final double rightAscensionDegrees;
  final double declinationDegrees;
  final Equinox equinox;
}

enum Equinox { j2000, ofDate }

/// Where something is relative to your horizon. Altitude is what decides "can I see it".
class Horizontal {
  const Horizontal({required this.altitudeDegrees, required this.azimuthDegrees});

  /// Degrees above the horizon. Negative means below it - not visible, and the app says so
  /// rather than drawing it anyway.
  final double altitudeDegrees;

  /// Degrees clockwise from north. 0 = N, 90 = E, 180 = S, 270 = W.
  final double azimuthDegrees;

  bool get isAboveHorizon => altitudeDegrees > 0;

  String get compass => compassPoint(azimuthDegrees);
}

/// A rectangular position in the J2000 ecliptic frame, in astronomical units.
class EclipticVector {
  const EclipticVector(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  double get length => math.sqrt(x * x + y * y + z * z);

  EclipticVector operator -(EclipticVector other) =>
      EclipticVector(x - other.x, y - other.y, z - other.z);

  EclipticVector operator +(EclipticVector other) =>
      EclipticVector(x + other.x, y + other.y, z + other.z);

  EclipticVector scaled(double factor) =>
      EclipticVector(x * factor, y * factor, z * factor);
}

/// Rotate a J2000 ecliptic vector into the equatorial frame of `when`.
///
/// Two steps that must happen in this order: precess within the ecliptic from J2000 to the
/// equinox of date, then tilt by the obliquity OF DATE. Using the J2000 obliquity with a
/// precessed longitude, or precessing after the tilt, both leave an error of several arcseconds
/// that grows with time.
Equatorial eclipticVectorToEquatorialOfDate(EclipticVector vector, DateTime when) {
  final precessed = _precessEclipticFromJ2000(vector, when);
  final obliquity = trueObliquityDegrees(when) * degToRad;
  final cosE = math.cos(obliquity);
  final sinE = math.sin(obliquity);

  final xEq = precessed.x;
  final yEq = precessed.y * cosE - precessed.z * sinE;
  final zEq = precessed.y * sinE + precessed.z * cosE;

  final radius = math.sqrt(xEq * xEq + yEq * yEq + zEq * zEq);
  return Equatorial(
    rightAscensionDegrees: normalizeDegrees(math.atan2(yEq, xEq) * radToDeg),
    declinationDegrees: math.asin(zEq / radius) * radToDeg,
    equinox: Equinox.ofDate,
  );
}

/// Rotate a J2000 ecliptic vector into the J2000 EQUATORIAL frame - no precession, no nutation.
///
/// Needed by the constellation lookup, which takes J2000 coordinates and precesses them back to
/// B1875 itself. Feeding it an of-date position instead would double-count 125 years of
/// precession in one direction and 26 in the other.
Equatorial eclipticJ2000VectorToEquatorialJ2000(EclipticVector vector) {
  // Obliquity at J2000 exactly, not the obliquity of date.
  const obliquity = 23.439291111 * degToRad;
  final cosE = math.cos(obliquity);
  final sinE = math.sin(obliquity);
  final xEq = vector.x;
  final yEq = vector.y * cosE - vector.z * sinE;
  final zEq = vector.y * sinE + vector.z * cosE;
  final radius = math.sqrt(xEq * xEq + yEq * yEq + zEq * zEq);
  return Equatorial(
    rightAscensionDegrees: normalizeDegrees(math.atan2(yEq, xEq) * radToDeg),
    declinationDegrees: math.asin(zEq / radius) * radToDeg,
    equinox: Equinox.j2000,
  );
}

/// Rotate an ecliptic vector that is ALREADY referred to the mean equinox of date into the
/// equatorial frame of date.
///
/// The difference from `eclipticVectorToEquatorialOfDate` is that this one does not precess. It
/// exists because the two sources this app uses do not agree on a frame: JPL's orbital elements
/// are referred to J2000, while the ELP lunar series gives longitude referred to the mean equinox
/// of date. Feeding the Moon through the J2000 path precesses it a second time.
///
/// That was a real bug, and it is recorded here because it is invisible by inspection: the Moon
/// came out 22.5 arcminutes wrong at every one of sixteen test points, while its distance was
/// right to 70 km in 385,000. A constant angular offset with a correct distance is always a frame
/// error, never a series error - and 22.5 arcminutes is exactly the precession from J2000 to 2026.
Equatorial eclipticOfDateVectorToEquatorial(EclipticVector vector, DateTime when) {
  // Only nutation in longitude remains: mean equinox of date -> true equinox of date.
  final nutationAngle = (nutation(when).longitudeArcsec / 3600.0) * degToRad;
  final cosN = math.cos(nutationAngle);
  final sinN = math.sin(nutationAngle);
  final nutated = EclipticVector(
    vector.x * cosN - vector.y * sinN,
    vector.x * sinN + vector.y * cosN,
    vector.z,
  );

  final obliquity = trueObliquityDegrees(when) * degToRad;
  final xEq = nutated.x;
  final yEq = nutated.y * math.cos(obliquity) - nutated.z * math.sin(obliquity);
  final zEq = nutated.y * math.sin(obliquity) + nutated.z * math.cos(obliquity);
  final radius = math.sqrt(xEq * xEq + yEq * yEq + zEq * zEq);

  return Equatorial(
    rightAscensionDegrees: normalizeDegrees(math.atan2(yEq, xEq) * radToDeg),
    declinationDegrees: math.asin(zEq / radius) * radToDeg,
    equinox: Equinox.ofDate,
  );
}

/// General precession in ecliptic longitude, J2000 -> equinox of date.
///
/// The ecliptic plane itself also moves, but by under 0.5 arcseconds a century in this period,
/// which is far below the error of everything else here, so only the longitude is precessed.
/// Stated rather than hidden, because it is the kind of shortcut that needs to be visible to
/// whoever next raises the accuracy target.
EclipticVector _precessEclipticFromJ2000(EclipticVector vector, DateTime when) {
  // IAU 1976 general precession in longitude: 5029.0966"/century at J2000, with its own rate.
  final precessionDegrees = _generalPrecessionDegrees(when);
  // Nutation in longitude is a rotation about the same pole, so it rides along here rather than
  // needing a second rotation. This takes the result from the mean equinox of date to the TRUE
  // equinox of date, which is what an apparent place is referred to.
  final nutationDegrees = nutation(when).longitudeArcsec / 3600.0;
  final angle = (precessionDegrees + nutationDegrees) * degToRad;
  final cosP = math.cos(angle);
  final sinP = math.sin(angle);
  return EclipticVector(
    vector.x * cosP - vector.y * sinP,
    vector.x * sinP + vector.y * cosP,
    vector.z,
  );
}

/// Rotate an ecliptic vector from the mean equinox of date back to J2000.
///
/// The inverse of the rotation inside `eclipticVectorToEquatorialOfDate`. Needed in exactly one
/// place: the Moon's series is of-date and the planetary elements are J2000, and the Earth/Moon
/// barycentre correction subtracts one from the other.
EclipticVector eclipticOfDateToJ2000(EclipticVector vector, DateTime when) {
  final angle = -_generalPrecessionDegrees(when) * degToRad;
  final cosP = math.cos(angle);
  final sinP = math.sin(angle);
  return EclipticVector(
    vector.x * cosP - vector.y * sinP,
    vector.x * sinP + vector.y * cosP,
    vector.z,
  );
}

double _generalPrecessionDegrees(DateTime when) {
  final t = centuriesSinceJ2000(when);
  return (5029.0966 * t + 1.11113 * t * t - 0.000006 * t * t * t) / 3600.0;
}

/// Precess an equatorial position between equinoxes, using the IAU 1976 angles.
///
/// Used for the star catalogue, which is stored in J2000 and must be drawn in the frame the
/// sidereal time is measured in.
Equatorial precessEquatorialFromJ2000(
  double raJ2000Degrees,
  double decJ2000Degrees,
  DateTime when,
) {
  final t = centuriesSinceJ2000(when);
  const arcsecToRad = math.pi / (180.0 * 3600.0);
  final zeta =
      (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * arcsecToRad;
  final z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) * arcsecToRad;
  final theta =
      (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * arcsecToRad;

  final ra = raJ2000Degrees * degToRad;
  final dec = decJ2000Degrees * degToRad;
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

  final p11 = cosZeta * cosTheta * cosZ - sinZeta * sinZ;
  final p12 = -sinZeta * cosTheta * cosZ - cosZeta * sinZ;
  final p13 = -sinTheta * cosZ;
  final p21 = cosZeta * cosTheta * sinZ + sinZeta * cosZ;
  final p22 = -sinZeta * cosTheta * sinZ + cosZeta * cosZ;
  final p23 = -sinTheta * sinZ;
  final p31 = cosZeta * sinTheta;
  final p32 = -sinZeta * sinTheta;
  final p33 = cosTheta;

  // Forward, not transposed. The angles already carry the direction through the sign of `t`;
  // transposing as well reverses it a second time. That bug cost an afternoon in the Python
  // pipeline - it put Pollux in Cancer - and it is just as easy to make here.
  final x = p11 * x0 + p12 * y0 + p13 * z0;
  final y = p21 * x0 + p22 * y0 + p23 * z0;
  final zz = p31 * x0 + p32 * y0 + p33 * z0;

  return Equatorial(
    rightAscensionDegrees: normalizeDegrees(math.atan2(y, x) * radToDeg),
    declinationDegrees: math.asin(zz.clamp(-1.0, 1.0)) * radToDeg,
    equinox: Equinox.ofDate,
  );
}

/// Where a position sits relative to an observer's horizon.
///
/// `position` must be referred to the equinox of date; passing J2000 coordinates here is wrong by
/// about twenty arcminutes in 2026, so it is asserted rather than trusted.
Horizontal toHorizontal({
  required Equatorial position,
  required DateTime when,
  required double latitudeDegrees,
  required double longitudeEastDegrees,
}) {
  assert(
    position.equinox == Equinox.ofDate,
    'horizontal coordinates need the equinox of date; precess first',
  );

  final lst = localApparentSiderealTimeDegrees(when, longitudeEastDegrees);
  final hourAngle = (lst - position.rightAscensionDegrees) * degToRad;
  final dec = position.declinationDegrees * degToRad;
  final lat = latitudeDegrees * degToRad;

  final sinAltitude = math.sin(dec) * math.sin(lat) +
      math.cos(dec) * math.cos(lat) * math.cos(hourAngle);
  final altitude = math.asin(sinAltitude.clamp(-1.0, 1.0));

  // Measured from north, increasing eastward. The two-argument form avoids the quadrant
  // ambiguity the arccos form has, which is the other classic sky-app bug: a planet in the east
  // drawn in the west.
  //
  // Both arguments are the textbook ones multiplied through by cos(altitude)·cos(latitude),
  // which is positive everywhere the app can be used, so the quadrant is unchanged:
  //   y = -cos δ · sin H · cos φ        x = sin δ - sin(alt) · sin φ
  final azimuth = math.atan2(
    -math.cos(dec) * math.cos(lat) * math.sin(hourAngle),
    math.sin(dec) - math.sin(lat) * sinAltitude,
  );

  return Horizontal(
    altitudeDegrees: altitude * radToDeg,
    azimuthDegrees: normalizeDegrees(azimuth * radToDeg),
  );
}
