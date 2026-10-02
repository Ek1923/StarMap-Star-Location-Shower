/// Time scales. The app only ever gets a `DateTime` from the phone, and every position calculation
/// needs that turned into a Julian date - plus the difference between the clock on the wall and
/// the clock the ephemeris uses.
library;

import 'angles.dart';

/// The standard epoch, 2000 January 1.5 TT.
const double jdJ2000 = 2451545.0;

/// Julian days in a Julian century.
const double daysPerJulianCentury = 36525.0;

/// The range JPL's Table 1 elements were fitted over. Outside it the elements are not merely less
/// accurate, they are undefined - JPL says so explicitly - so `Planets` refuses rather than
/// returning a number that looks like an answer.
final DateTime validFrom = DateTime.utc(1800, 1, 1);
final DateTime validTo = DateTime.utc(2050, 1, 1);

/// Julian Date (UT). Valid for any Gregorian date; the pre-1582 Julian calendar is not handled
/// because the app never asks about it.
double julianDateUtc(DateTime when) {
  final utc = when.toUtc();
  var year = utc.year;
  var month = utc.month;
  if (month <= 2) {
    year -= 1;
    month += 12;
  }
  final a = (year / 100).floor();
  final b = 2 - a + (a / 4).floor();
  final dayFraction = (utc.hour +
          utc.minute / 60.0 +
          utc.second / 3600.0 +
          utc.millisecond / 3600000.0) /
      24.0;
  return (365.25 * (year + 4716)).floor() +
      (30.6001 * (month + 1)).floor() +
      utc.day +
      dayFraction +
      b -
      1524.5;
}

/// TT - UTC in seconds.
///
/// A constant, and that is a deliberate simplification rather than an oversight. It is 69.2 s as
/// of 2026 (32.184 s of TAI-TT offset plus 37 leap seconds). Leap seconds are unpredictable by
/// definition, so a table would be wrong about the future anyway, and the error this constant can
/// accumulate is of order one second. One second of time moves the Moon by half an arcsecond and
/// a planet by far less - two orders of magnitude below the error of the orbital elements
/// themselves. Revisit only if the elements are ever replaced by something better.
const double ttMinusUtcSeconds = 69.2;

/// Julian Date in Terrestrial Time, which is the scale the ephemeris formulae want.
double julianDateTerrestrial(DateTime when) =>
    julianDateUtc(when) + ttMinusUtcSeconds / 86400.0;

/// Julian centuries of TT since J2000.
double centuriesSinceJ2000(DateTime when) =>
    (julianDateTerrestrial(when) - jdJ2000) / daysPerJulianCentury;

/// Greenwich Mean Sidereal Time in degrees - the right ascension currently on the Greenwich
/// meridian. This is what turns a position in the sky into a position over your head.
///
/// IAU 1982 expression, evaluated on UT rather than TT because sidereal time tracks the Earth's
/// actual rotation.
double greenwichMeanSiderealTimeDegrees(DateTime when) {
  final jd = julianDateUtc(when);
  final t = (jd - jdJ2000) / daysPerJulianCentury;
  final degrees = 280.46061837 +
      360.98564736629 * (jd - jdJ2000) +
      0.000387933 * t * t -
      t * t * t / 38710000.0;
  return normalizeDegrees(degrees);
}

/// Local sidereal time in degrees, for an observer at `longitudeEastDegrees`.
///
/// East longitude positive. Getting this sign wrong is the single most common bug in a sky app
/// and it is invisible from Greenwich, which is why the fixture tests use four sites spread
/// across both hemispheres and both sides of the prime meridian.
double localSiderealTimeDegrees(DateTime when, double longitudeEastDegrees) =>
    normalizeDegrees(
      greenwichMeanSiderealTimeDegrees(when) + longitudeEastDegrees,
    );

/// Mean obliquity of the ecliptic in degrees, for the equinox of date (IAU 1980).
double meanObliquityDegrees(DateTime when) {
  final t = centuriesSinceJ2000(when);
  const arcsecToDeg = 1.0 / 3600.0;
  return 23.439291111 -
      46.8150 * arcsecToDeg * t -
      0.00059 * arcsecToDeg * t * t +
      0.001813 * arcsecToDeg * t * t * t;
}
