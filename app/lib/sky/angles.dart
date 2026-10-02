/// Angle plumbing. Small on purpose: every other file in `sky/` leans on it, so a mistake here
/// is a mistake everywhere, and it is worth having one place to test.
library;

import 'dart:math' as math;

const double degToRad = math.pi / 180.0;
const double radToDeg = 180.0 / math.pi;

/// Wrap to [0, 360).
double normalizeDegrees(double degrees) {
  final wrapped = degrees % 360.0;
  return wrapped < 0 ? wrapped + 360.0 : wrapped;
}

/// Wrap to [-180, 180]. Kepler's equation needs the mean anomaly in this range, and the sign of
/// a declination difference is easier to read this way.
double normalizeDegreesSigned(double degrees) {
  final wrapped = normalizeDegrees(degrees);
  return wrapped > 180.0 ? wrapped - 360.0 : wrapped;
}

/// Great-circle angle between two equatorial positions, in degrees.
///
/// Haversine rather than the spherical cosine rule: the cosine rule loses precision for small
/// separations, and small separations are exactly what the accuracy tests measure.
double angularSeparationDegrees(
  double ra1Deg,
  double dec1Deg,
  double ra2Deg,
  double dec2Deg,
) {
  final ra1 = ra1Deg * degToRad;
  final dec1 = dec1Deg * degToRad;
  final ra2 = ra2Deg * degToRad;
  final dec2 = dec2Deg * degToRad;
  final dRa = ra2 - ra1;
  final dDec = dec2 - dec1;
  final a = math.pow(math.sin(dDec / 2), 2) +
      math.cos(dec1) * math.cos(dec2) * math.pow(math.sin(dRa / 2), 2);
  return 2 * math.asin(math.min(1.0, math.sqrt(a))) * radToDeg;
}

/// One of the eight compass points, for "look south-east, about a third of the way up".
///
/// Sixteen points would be more precise and less useful: nobody turns to face south-south-east.
String compassPoint(double azimuthDegrees) {
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final index = ((normalizeDegrees(azimuthDegrees) + 22.5) / 45.0).floor() % 8;
  return names[index];
}

/// '13h 25m 11.6s' - how right ascension is conventionally written.
String formatRightAscension(double raDegrees) {
  final hoursTotal = normalizeDegrees(raDegrees) / 15.0;
  final hours = hoursTotal.floor();
  final minutesTotal = (hoursTotal - hours) * 60.0;
  final minutes = minutesTotal.floor();
  final seconds = (minutesTotal - minutes) * 60.0;
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m '
      '${seconds.toStringAsFixed(1).padLeft(4, '0')}s';
}

/// "+15° 21' 19"" - declination, with the sign always shown.
String formatDeclination(double decDegrees) {
  final sign = decDegrees < 0 ? '-' : '+';
  final absolute = decDegrees.abs();
  final degrees = absolute.floor();
  final arcminutesTotal = (absolute - degrees) * 60.0;
  final arcminutes = arcminutesTotal.floor();
  final arcseconds = (arcminutesTotal - arcminutes) * 60.0;
  return '$sign$degrees° ${arcminutes.toString().padLeft(2, '0')}′ '
      '${arcseconds.round().toString().padLeft(2, '0')}″';
}
