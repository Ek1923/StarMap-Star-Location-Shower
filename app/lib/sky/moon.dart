/// Where the Moon is, how lit it is, and when it is next full.
///
/// Series: ELP2000-82, in the truncated form given by Meeus, Astronomical Algorithms ch. 47. The
/// terms below are the largest of that table, ordered by magnitude as Meeus lists them, so
/// truncating is safe - the residual is bounded by the terms left out, not scattered.
///
/// The measured accuracy against NASA/JPL's own ephemeris is in `test/moon_test.dart`. That
/// number is the claim; this comment is not.
///
/// The Moon is the one body where the viewer's position on the Earth genuinely matters: its
/// diurnal parallax reaches a full degree, twice its own apparent width. `observer.dart` handles
/// that, and skipping it would be the most visible possible error in a sky app.
library;

import 'dart:math' as math;

import 'angles.dart';
import 'coordinates.dart';
import 'julian.dart';

/// Mean distance used as the zero point of the distance series, in km (Meeus ch. 47).
const double _meanDistanceKm = 385000.56;

/// Equatorial radius of the Moon in km, IAU 2015 nominal.
const double _moonRadiusKm = 1737.4;

const double _auKm = 149597870.7;

/// Moon/(Earth+Moon) mass ratio, DE430. Used to turn the Earth/Moon barycentre - which is what
/// the planetary elements actually describe - into the Earth's own centre.
const double moonMassFraction = 0.0121505856;

/// Periodic terms for ecliptic longitude and distance: [D, M, M', F, sinCoeff, cosCoeff].
///
/// `sinCoeff` is in units of 1e-6 degrees and feeds the longitude sum; `cosCoeff` is in units of
/// 1e-3 km and feeds the distance sum. Same argument set for both, which is why Meeus tabulates
/// them together.
const List<List<double>> _longitudeAndDistanceTerms = [
  [0, 0, 1, 0, 6288774, -20905355],
  [2, 0, -1, 0, 1274027, -3699111],
  [2, 0, 0, 0, 658314, -2955968],
  [0, 0, 2, 0, 213618, -569925],
  [0, 1, 0, 0, -185116, 48888],
  [0, 0, 0, 2, -114332, -3149],
  [2, 0, -2, 0, 58793, 246158],
  [2, -1, -1, 0, 57066, -152138],
  [2, 0, 1, 0, 53322, -170733],
  [2, -1, 0, 0, 45758, -204586],
  [0, 1, -1, 0, -40923, -129620],
  [1, 0, 0, 0, -34720, 108743],
  [0, 1, 1, 0, -30383, 104755],
  [2, 0, 0, -2, 15327, 10321],
  [0, 0, 1, 2, -12528, 0],
  [0, 0, 1, -2, 10980, 79661],
  [4, 0, -1, 0, 10675, -34782],
  [0, 0, 3, 0, 10034, -23210],
  [4, 0, -2, 0, 8548, -21636],
  [2, 1, -1, 0, -7888, 24208],
  [2, 1, 0, 0, -6766, 30824],
  [1, 0, -1, 0, -5163, -8379],
  [1, 1, 0, 0, 4987, -16675],
  [2, -1, 1, 0, 4036, -12831],
  [2, 0, 2, 0, 3994, -10445],
  [4, 0, 0, 0, 3861, -11650],
  [2, 0, -3, 0, 3665, 14403],
  [0, 1, -2, 0, -2689, -7003],
  [2, 0, -1, 2, -2602, 0],
  [2, -1, -2, 0, 2390, 10056],
  [1, 0, 1, 0, -2348, 6322],
  [2, -2, 0, 0, 2236, -9884],
  [0, 1, 2, 0, -2120, 5751],
  [0, 2, 0, 0, -2069, 0],
  [2, -2, -1, 0, 2048, -4950],
  [2, 0, 1, -2, -1773, 4130],
  [2, 0, 0, 2, -1595, 0],
  [4, -1, -1, 0, 1215, -3958],
  [0, 0, 2, 2, -1110, 0],
  [3, 0, -1, 0, -892, 3258],
  [2, 1, 1, 0, -810, 2616],
  [4, -1, -2, 0, 759, -1897],
  [0, 2, -1, 0, -713, -2117],
  [2, 2, -1, 0, -700, 2354],
  [2, 1, -2, 0, 691, 0],
  [2, -1, 0, -2, 596, 0],
  [4, 0, 1, 0, 549, -1423],
  [0, 0, 4, 0, 537, -1117],
  [4, -1, 0, 0, 520, -1571],
  [1, 0, -2, 0, -487, -1739],
  [2, 1, 0, -2, -399, 0],
  [0, 0, 2, -2, -381, -4421],
  [1, 1, 1, 0, 351, 0],
  [3, 0, -2, 0, -340, 0],
  [4, 0, -3, 0, 330, 0],
  [2, -1, 2, 0, 327, 0],
  [0, 2, 1, 0, -323, 1165],
  [1, 1, -1, 0, 299, 0],
  [2, 0, 3, 0, 294, 0],
  [2, 0, -1, -2, 0, 8752],
];

/// Periodic terms for ecliptic latitude: [D, M, M', F, sinCoeff] in units of 1e-6 degrees.
const List<List<double>> _latitudeTerms = [
  [0, 0, 0, 1, 5128122],
  [0, 0, 1, 1, 280602],
  [0, 0, 1, -1, 277693],
  [2, 0, 0, -1, 173237],
  [2, 0, -1, 1, 55413],
  [2, 0, -1, -1, 46271],
  [2, 0, 0, 1, 32573],
  [0, 0, 2, 1, 17198],
  [2, 0, 1, -1, 9266],
  [0, 0, 2, -1, 8822],
  [2, -1, 0, -1, 8216],
  [2, 0, -2, -1, 4324],
  [2, 0, 1, 1, 4200],
  [2, 1, 0, -1, -3359],
  [2, -1, -1, 1, 2463],
  [2, -1, 0, 1, 2211],
  [2, -1, -1, -1, 2065],
  [0, 1, -1, -1, -1870],
  [4, 0, -1, -1, 1828],
  [0, 1, 0, 1, -1794],
  [0, 0, 0, 3, -1749],
  [0, 1, -1, 1, -1565],
  [1, 0, 0, 1, -1491],
  [0, 1, 1, 1, -1475],
  [0, 1, 1, -1, -1410],
  [0, 1, 0, -1, -1344],
  [1, 0, 0, -1, -1335],
  [0, 0, 3, 1, 1107],
  [4, 0, 0, -1, 1021],
  [4, 0, -1, 1, 833],
  [0, 0, 1, -3, 777],
  [4, 0, -2, 1, 671],
  [2, 0, 0, -3, 607],
  [2, 0, 2, -1, 596],
  [2, -1, 1, -1, 491],
  [2, 0, -2, 1, -451],
  [0, 0, 3, -1, 439],
  [2, 0, 2, 1, 422],
  [2, 0, -3, -1, 421],
  [2, 1, -1, 1, -366],
  [2, 1, 0, 1, -351],
  [4, 0, 0, 1, 331],
  [2, -1, 1, 1, 315],
  [2, -2, 0, -1, 302],
  [0, 0, 1, 3, -283],
  [2, 1, 1, -1, -229],
  [1, 1, 0, -1, 223],
  [1, 1, 0, 1, 223],
  [0, 1, -2, -1, -220],
  [2, 1, -1, -1, -220],
  [1, 0, 1, 1, -185],
  [2, -1, -2, -1, 181],
  [0, 1, 2, 1, -177],
  [4, 0, -2, -1, 176],
  [4, -1, -1, -1, 166],
  [1, 0, 1, -1, -164],
  [4, 0, 1, -1, 132],
  [1, 0, -1, -1, -119],
  [4, -1, 0, -1, 115],
  [2, -2, 0, 1, 107],
];

/// The Moon's geocentric position as a vector in au, in the ecliptic frame OF DATE.
///
/// Of date, not J2000 - the ELP series gives longitude referred to the mean equinox of the
/// moment. The frame is in the name because getting it wrong is a 22 arcminute error that looks
/// like nothing at all in the code.
///
/// Returned as a vector rather than as angles so it can be subtracted from the Earth/Moon
/// barycentre without a round trip through spherical coordinates.
EclipticVector moonGeocentricVectorOfDateAu(DateTime when) {
  final geometry = _geometry(when);
  final latitude = geometry.latitudeDegrees * degToRad;
  final longitude = geometry.longitudeDegrees * degToRad;
  final distanceAu = geometry.distanceKm / _auKm;
  return EclipticVector(
    distanceAu * math.cos(latitude) * math.cos(longitude),
    distanceAu * math.cos(latitude) * math.sin(longitude),
    distanceAu * math.sin(latitude),
  );
}

/// Geocentric apparent position of the Moon, referred to the true equinox of date.
Equatorial moonPosition(DateTime when) =>
    eclipticOfDateVectorToEquatorial(moonGeocentricVectorOfDateAu(when), when);

/// Earth-Moon distance in km.
double moonDistanceKm(DateTime when) => _geometry(when).distanceKm;

/// Apparent angular diameter of the Moon in arcseconds, from its real distance.
///
/// Not a constant: the Moon's distance varies by about 13% over a month, which is the whole
/// reason "supermoon" is a word.
double moonAngularDiameterArcseconds(DateTime when) =>
    2 * (_moonRadiusKm / moonDistanceKm(when)) * 206264.806247;

/// The Moon's ecliptic longitude in degrees, referred to the mean equinox OF DATE.
double moonEclipticLongitudeDegrees(DateTime when) => _geometry(when).longitudeDegrees;

class _MoonGeometry {
  const _MoonGeometry({
    required this.longitudeDegrees,
    required this.latitudeDegrees,
    required this.distanceKm,
  });

  final double longitudeDegrees;
  final double latitudeDegrees;
  final double distanceKm;
}

_MoonGeometry _geometry(DateTime when) {
  final t = centuriesSinceJ2000(when);

  // Meeus ch. 47: the five fundamental arguments, in degrees.
  final meanLongitude = 218.3164477 +
      481267.88123421 * t -
      0.0015786 * t * t +
      t * t * t / 538841.0 -
      t * t * t * t / 65194000.0;
  final elongation = 297.8501921 +
      445267.1114034 * t -
      0.0018819 * t * t +
      t * t * t / 545868.0 -
      t * t * t * t / 113065000.0;
  final sunAnomaly =
      357.5291092 + 35999.0502909 * t - 0.0001536 * t * t + t * t * t / 24490000.0;
  final moonAnomaly = 134.9633964 +
      477198.8675055 * t +
      0.0087414 * t * t +
      t * t * t / 69699.0 -
      t * t * t * t / 14712000.0;
  final argumentOfLatitude = 93.2720950 +
      483202.0175233 * t -
      0.0036539 * t * t -
      t * t * t / 3526000.0 +
      t * t * t * t / 863310000.0;

  // Additive arguments for the three largest planetary perturbations.
  final a1 = 119.75 + 131.849 * t;
  final a2 = 53.09 + 479264.290 * t;
  final a3 = 313.45 + 481266.484 * t;

  // The Earth's orbital eccentricity is decreasing, which damps the terms that depend on the
  // Sun's anomaly. E to the power of |M| is applied per term, as Meeus specifies.
  final e = 1 - 0.002516 * t - 0.0000074 * t * t;

  var sumLongitude = 0.0;
  var sumDistance = 0.0;
  for (final term in _longitudeAndDistanceTerms) {
    final argument = (term[0] * elongation +
            term[1] * sunAnomaly +
            term[2] * moonAnomaly +
            term[3] * argumentOfLatitude) *
        degToRad;
    final damping = math.pow(e, term[1].abs()).toDouble();
    sumLongitude += term[4] * damping * math.sin(argument);
    sumDistance += term[5] * damping * math.cos(argument);
  }

  var sumLatitude = 0.0;
  for (final term in _latitudeTerms) {
    final argument = (term[0] * elongation +
            term[1] * sunAnomaly +
            term[2] * moonAnomaly +
            term[3] * argumentOfLatitude) *
        degToRad;
    final damping = math.pow(e, term[1].abs()).toDouble();
    sumLatitude += term[4] * damping * math.sin(argument);
  }

  sumLongitude += 3958 * math.sin(a1 * degToRad) +
      1962 * math.sin((meanLongitude - argumentOfLatitude) * degToRad) +
      318 * math.sin(a2 * degToRad);

  sumLatitude += -2235 * math.sin(meanLongitude * degToRad) +
      382 * math.sin(a3 * degToRad) +
      175 * math.sin((a1 - argumentOfLatitude) * degToRad) +
      175 * math.sin((a1 + argumentOfLatitude) * degToRad) +
      127 * math.sin((meanLongitude - moonAnomaly) * degToRad) -
      115 * math.sin((meanLongitude + moonAnomaly) * degToRad);

  return _MoonGeometry(
    longitudeDegrees: normalizeDegrees(meanLongitude + sumLongitude / 1000000.0),
    latitudeDegrees: sumLatitude / 1000000.0,
    distanceKm: _meanDistanceKm + sumDistance / 1000.0,
  );
}
