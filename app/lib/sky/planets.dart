/// Where the planets are, from JPL's own published orbital elements.
///
/// Source: "Keplerian Elements for Approximate Positions of the Major Planets",
/// https://ssd.jpl.nasa.gov/planets/approx_pos.html - Table 1, referred to the mean ecliptic and
/// equinox of J2000, fitted over 1800-2050. The numbers below are copied from that table and
/// nothing else; none of them is derived, rounded or adjusted here.
///
/// Why this and not a full VSOP87 series: JPL states the error of these elements, so the app can
/// state it too. Their nominal heliocentric longitude errors over 1800-2050 are
///
///     Mercury 15"   Venus 20"   Earth 20"   Mars 40"
///     Jupiter 400"  Saturn 600" Uranus 50"  Neptune 10"
///
/// The worst of those, Saturn at 600 arcseconds, is 10 arcminutes - a third of the width of the
/// full Moon, and well under the 1 degree a hand span covers at arm's length. The app exists to
/// tell you where to look, and this is finer than you can point. A VSOP87 implementation would be
/// a thousand coefficients to buy accuracy nobody standing in a garden can use.
///
/// The measured geocentric error against NASA's own ephemeris is in `test/accuracy_test.dart`,
/// which checks all eight planets at four epochs from four places on Earth. That number, not this
/// comment, is the claim.
library;

import 'dart:math' as math;

import 'angles.dart';
import 'coordinates.dart';
import 'julian.dart';
import 'moon.dart';

/// The eight planets, plus the Earth/Moon barycentre, which is how the Earth enters the geometry.
enum Planet {
  mercury('Mercury'),
  venus('Venus'),
  mars('Mars'),
  jupiter('Jupiter'),
  saturn('Saturn'),
  uranus('Uranus'),
  neptune('Neptune');

  const Planet(this.displayName);

  final String displayName;
}

/// One planet's six elements and their rates, exactly as JPL Table 1 lists them.
class _Elements {
  const _Elements({
    required this.semiMajorAxisAu,
    required this.semiMajorAxisRateAuPerCentury,
    required this.eccentricity,
    required this.eccentricityRatePerCentury,
    required this.inclinationDegrees,
    required this.inclinationRateDegreesPerCentury,
    required this.meanLongitudeDegrees,
    required this.meanLongitudeRateDegreesPerCentury,
    required this.longitudeOfPerihelionDegrees,
    required this.longitudeOfPerihelionRateDegreesPerCentury,
    required this.longitudeOfAscendingNodeDegrees,
    required this.longitudeOfAscendingNodeRateDegreesPerCentury,
  });

  final double semiMajorAxisAu;
  final double semiMajorAxisRateAuPerCentury;
  final double eccentricity;
  final double eccentricityRatePerCentury;
  final double inclinationDegrees;
  final double inclinationRateDegreesPerCentury;
  final double meanLongitudeDegrees;
  final double meanLongitudeRateDegreesPerCentury;
  final double longitudeOfPerihelionDegrees;
  final double longitudeOfPerihelionRateDegreesPerCentury;
  final double longitudeOfAscendingNodeDegrees;
  final double longitudeOfAscendingNodeRateDegreesPerCentury;
}

/// JPL Table 1, verbatim. First row of each pair is the element at J2000, second row its rate
/// per Julian century.
const _Elements _earthMoonBarycentre = _Elements(
  semiMajorAxisAu: 1.00000261,
  semiMajorAxisRateAuPerCentury: 0.00000562,
  eccentricity: 0.01671123,
  eccentricityRatePerCentury: -0.00004392,
  inclinationDegrees: -0.00001531,
  inclinationRateDegreesPerCentury: -0.01294668,
  meanLongitudeDegrees: 100.46457166,
  meanLongitudeRateDegreesPerCentury: 35999.37244981,
  longitudeOfPerihelionDegrees: 102.93768193,
  longitudeOfPerihelionRateDegreesPerCentury: 0.32327364,
  longitudeOfAscendingNodeDegrees: 0.0,
  longitudeOfAscendingNodeRateDegreesPerCentury: 0.0,
);

const Map<Planet, _Elements> _elements = {
  Planet.mercury: _Elements(
    semiMajorAxisAu: 0.38709927,
    semiMajorAxisRateAuPerCentury: 0.00000037,
    eccentricity: 0.20563593,
    eccentricityRatePerCentury: 0.00001906,
    inclinationDegrees: 7.00497902,
    inclinationRateDegreesPerCentury: -0.00594749,
    meanLongitudeDegrees: 252.25032350,
    meanLongitudeRateDegreesPerCentury: 149472.67411175,
    longitudeOfPerihelionDegrees: 77.45779628,
    longitudeOfPerihelionRateDegreesPerCentury: 0.16047689,
    longitudeOfAscendingNodeDegrees: 48.33076593,
    longitudeOfAscendingNodeRateDegreesPerCentury: -0.12534081,
  ),
  Planet.venus: _Elements(
    semiMajorAxisAu: 0.72333566,
    semiMajorAxisRateAuPerCentury: 0.00000390,
    eccentricity: 0.00677672,
    eccentricityRatePerCentury: -0.00004107,
    inclinationDegrees: 3.39467605,
    inclinationRateDegreesPerCentury: -0.00078890,
    meanLongitudeDegrees: 181.97909950,
    meanLongitudeRateDegreesPerCentury: 58517.81538729,
    longitudeOfPerihelionDegrees: 131.60246718,
    longitudeOfPerihelionRateDegreesPerCentury: 0.00268329,
    longitudeOfAscendingNodeDegrees: 76.67984255,
    longitudeOfAscendingNodeRateDegreesPerCentury: -0.27769418,
  ),
  Planet.mars: _Elements(
    semiMajorAxisAu: 1.52371034,
    semiMajorAxisRateAuPerCentury: 0.00001847,
    eccentricity: 0.09339410,
    eccentricityRatePerCentury: 0.00007882,
    inclinationDegrees: 1.84969142,
    inclinationRateDegreesPerCentury: -0.00813131,
    meanLongitudeDegrees: -4.55343205,
    meanLongitudeRateDegreesPerCentury: 19140.30268499,
    longitudeOfPerihelionDegrees: -23.94362959,
    longitudeOfPerihelionRateDegreesPerCentury: 0.44441088,
    longitudeOfAscendingNodeDegrees: 49.55953891,
    longitudeOfAscendingNodeRateDegreesPerCentury: -0.29257343,
  ),
  Planet.jupiter: _Elements(
    semiMajorAxisAu: 5.20288700,
    semiMajorAxisRateAuPerCentury: -0.00011607,
    eccentricity: 0.04838624,
    eccentricityRatePerCentury: -0.00013253,
    inclinationDegrees: 1.30439695,
    inclinationRateDegreesPerCentury: -0.00183714,
    meanLongitudeDegrees: 34.39644051,
    meanLongitudeRateDegreesPerCentury: 3034.74612775,
    longitudeOfPerihelionDegrees: 14.72847983,
    longitudeOfPerihelionRateDegreesPerCentury: 0.21252668,
    longitudeOfAscendingNodeDegrees: 100.47390909,
    longitudeOfAscendingNodeRateDegreesPerCentury: 0.20469106,
  ),
  Planet.saturn: _Elements(
    semiMajorAxisAu: 9.53667594,
    semiMajorAxisRateAuPerCentury: -0.00125060,
    eccentricity: 0.05386179,
    eccentricityRatePerCentury: -0.00050991,
    inclinationDegrees: 2.48599187,
    inclinationRateDegreesPerCentury: 0.00193609,
    meanLongitudeDegrees: 49.95424423,
    meanLongitudeRateDegreesPerCentury: 1222.49362201,
    longitudeOfPerihelionDegrees: 92.59887831,
    longitudeOfPerihelionRateDegreesPerCentury: -0.41897216,
    longitudeOfAscendingNodeDegrees: 113.66242448,
    longitudeOfAscendingNodeRateDegreesPerCentury: -0.28867794,
  ),
  Planet.uranus: _Elements(
    semiMajorAxisAu: 19.18916464,
    semiMajorAxisRateAuPerCentury: -0.00196176,
    eccentricity: 0.04725744,
    eccentricityRatePerCentury: -0.00004397,
    inclinationDegrees: 0.77263783,
    inclinationRateDegreesPerCentury: -0.00242939,
    meanLongitudeDegrees: 313.23810451,
    meanLongitudeRateDegreesPerCentury: 428.48202785,
    longitudeOfPerihelionDegrees: 170.95427630,
    longitudeOfPerihelionRateDegreesPerCentury: 0.40805281,
    longitudeOfAscendingNodeDegrees: 74.01692503,
    longitudeOfAscendingNodeRateDegreesPerCentury: 0.04240589,
  ),
  Planet.neptune: _Elements(
    semiMajorAxisAu: 30.06992276,
    semiMajorAxisRateAuPerCentury: 0.00026291,
    eccentricity: 0.00859048,
    eccentricityRatePerCentury: 0.00005105,
    inclinationDegrees: 1.77004347,
    inclinationRateDegreesPerCentury: 0.00035372,
    meanLongitudeDegrees: -55.12002969,
    meanLongitudeRateDegreesPerCentury: 218.45945325,
    longitudeOfPerihelionDegrees: 44.96476227,
    longitudeOfPerihelionRateDegreesPerCentury: -0.32241464,
    longitudeOfAscendingNodeDegrees: 131.78422574,
    longitudeOfAscendingNodeRateDegreesPerCentury: -0.00508664,
  ),
};

/// Light travel time for one astronomical unit, in days. IAU 2012 definition of the au over the
/// speed of light: 499.004784 s.
const double _lightTimeDaysPerAu = 499.004784 / 86400.0;

/// Thrown when a date falls outside the interval JPL fitted the elements over.
///
/// Deliberately an error rather than a best effort. JPL's own words: "the elements are not valid
/// outside the given time-interval over which they were fit". An app that quietly extrapolates is
/// an app that lies on its 2051st birthday.
class OutsideValidRangeException implements Exception {
  OutsideValidRangeException(this.when);

  final DateTime when;

  @override
  String toString() =>
      'StarMap computes planet positions from JPL Table 1 elements, fitted for 1800-2050. '
      '${when.toUtc().toIso8601String()} is outside that range, so no position is given rather '
      'than a wrong one.';
}

/// Heliocentric position in the J2000 ecliptic frame, in au.
EclipticVector heliocentricPosition(Planet planet, DateTime when) =>
    _heliocentric(_elements[planet]!, centuriesSinceJ2000(when));

/// The Earth/Moon BARYCENTRE's heliocentric position in the J2000 ecliptic frame, in au.
///
/// This is what JPL's element set actually describes - the table calls it "EM Bary" - and it is
/// up to 4,670 km from the Earth's own centre, which is where the viewer is standing.
EclipticVector earthMoonBarycentrePosition(DateTime when) =>
    _heliocentric(_earthMoonBarycentre, centuriesSinceJ2000(when));

/// The EARTH's heliocentric position in the J2000 ecliptic frame, in au.
///
/// The barycentre, corrected towards the Earth by the Moon's share of the pair's mass. The
/// correction is a monthly wobble of up to 4,670 km, which is 6 arcseconds of direction for the
/// Sun and more for a close planet - small, but it is the difference between an error that
/// averages out and one that does not, and the Moon's position is already computed.
EclipticVector earthHeliocentricPosition(DateTime when) {
  final barycentre = earthMoonBarycentrePosition(when);
  final moon = eclipticOfDateToJ2000(moonGeocentricVectorOfDateAu(when), when);
  return barycentre - moon.scaled(moonMassFraction);
}

EclipticVector _heliocentric(_Elements e, double t) {
  final a = e.semiMajorAxisAu + e.semiMajorAxisRateAuPerCentury * t;
  final eccentricity = e.eccentricity + e.eccentricityRatePerCentury * t;
  final inclination =
      (e.inclinationDegrees + e.inclinationRateDegreesPerCentury * t) * degToRad;
  final meanLongitude =
      e.meanLongitudeDegrees + e.meanLongitudeRateDegreesPerCentury * t;
  final longitudeOfPerihelion = e.longitudeOfPerihelionDegrees +
      e.longitudeOfPerihelionRateDegreesPerCentury * t;
  final ascendingNode = (e.longitudeOfAscendingNodeDegrees +
          e.longitudeOfAscendingNodeRateDegreesPerCentury * t) *
      degToRad;

  final argumentOfPerihelion =
      longitudeOfPerihelion * degToRad - ascendingNode;
  // Table 1 needs no b, c, f, s correction terms - those belong to Table 2b, which is only for
  // the 3000 BC - 3000 AD element set.
  final meanAnomaly =
      normalizeDegreesSigned(meanLongitude - longitudeOfPerihelion) * degToRad;

  final eccentricAnomaly = _solveKepler(meanAnomaly, eccentricity);

  // Position in the orbital plane, x' toward perihelion.
  final xOrbit = a * (math.cos(eccentricAnomaly) - eccentricity);
  final yOrbit =
      a * math.sqrt(1 - eccentricity * eccentricity) * math.sin(eccentricAnomaly);

  final cosArg = math.cos(argumentOfPerihelion);
  final sinArg = math.sin(argumentOfPerihelion);
  final cosNode = math.cos(ascendingNode);
  final sinNode = math.sin(ascendingNode);
  final cosInc = math.cos(inclination);
  final sinInc = math.sin(inclination);

  return EclipticVector(
    (cosArg * cosNode - sinArg * sinNode * cosInc) * xOrbit +
        (-sinArg * cosNode - cosArg * sinNode * cosInc) * yOrbit,
    (cosArg * sinNode + sinArg * cosNode * cosInc) * xOrbit +
        (-sinArg * sinNode + cosArg * cosNode * cosInc) * yOrbit,
    (sinArg * sinInc) * xOrbit + (cosArg * sinInc) * yOrbit,
  );
}

/// Solve M = E - e sin E for E, by Newton's method.
///
/// Converges in a handful of iterations for every planet - the worst case is Mercury at e=0.206.
/// The iteration cap is a guard, not an expectation: if it is ever hit the result would be
/// silently wrong, so it throws.
double _solveKepler(double meanAnomalyRadians, double eccentricity) {
  var e = meanAnomalyRadians;
  for (var i = 0; i < 30; i++) {
    final delta = e - eccentricity * math.sin(e) - meanAnomalyRadians;
    if (delta.abs() < 1e-12) return e;
    e -= delta / (1 - eccentricity * math.cos(e));
  }
  throw StateError(
    'Kepler solver did not converge for M=$meanAnomalyRadians e=$eccentricity',
  );
}

/// Geocentric apparent position of a planet, referred to the equinox of date.
///
/// Corrected for light time (the planet is seen where it was, not where it is) and for annual
/// aberration (the observer is moving at 30 km/s, which displaces everything by up to 20
/// arcseconds). Nutation is NOT applied: it is at most 17 arcseconds and the orbital elements are
/// already coarser than that for every planet except Neptune.
Equatorial geocentricPosition(Planet planet, DateTime when) {
  _assertInRange(when);
  final earth = earthHeliocentricPosition(when);

  // Light time: iterate twice. The first pass is already good to a few milliarcseconds for the
  // inner planets; the second covers Neptune, where the light time is over four hours.
  var planetPosition = heliocentricPosition(planet, when);
  for (var i = 0; i < 2; i++) {
    final distance = (planetPosition - earth).length;
    final lightTimeDays = distance * _lightTimeDaysPerAu;
    planetPosition = heliocentricPosition(
      planet,
      when.subtract(Duration(microseconds: (lightTimeDays * 86400e6).round())),
    );
  }

  final geocentric = _applyAberration(planetPosition - earth, when);
  return eclipticVectorToEquatorialOfDate(geocentric, when);
}

/// Distance from Earth in au, at `when`.
double distanceFromEarthAu(Planet planet, DateTime when) {
  _assertInRange(when);
  return (heliocentricPosition(planet, when) - earthHeliocentricPosition(when))
      .length;
}

/// Annual aberration, applied as a rotation of the direction by the Earth's velocity over c.
///
/// The Earth's velocity is taken as the numerical derivative of its own position over ten
/// minutes, so there is one orbit model rather than two that can disagree.
EclipticVector _applyAberration(EclipticVector direction, DateTime when) {
  const stepSeconds = 600;
  final before = earthHeliocentricPosition(
    when.subtract(const Duration(seconds: stepSeconds)),
  );
  final after = earthHeliocentricPosition(
    when.add(const Duration(seconds: stepSeconds)),
  );
  final auPerDay = (after - before).scaled(1.0 / (2 * stepSeconds / 86400.0));
  // v/c in au/day over au/day: light covers 1/_lightTimeDaysPerAu au per day.
  final overC = auPerDay.scaled(_lightTimeDaysPerAu);
  final distance = direction.length;
  return direction + overC.scaled(distance);
}

void _assertInRange(DateTime when) {
  final utc = when.toUtc();
  if (utc.isBefore(validFrom) || utc.isAfter(validTo)) {
    throw OutsideValidRangeException(utc);
  }
}
