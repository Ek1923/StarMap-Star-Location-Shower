/// Where the viewer is standing, and what difference that makes.
///
/// It makes more difference than people expect. A body's direction seen from a point on the
/// Earth's surface differs from its direction seen from the Earth's centre by the diurnal
/// parallax, which is the Earth's radius divided by the distance:
///
///     the Moon      up to  1 degree     - obvious, and the reason this file exists
///     Mars at best         23 arcsec
///     the Sun               8.8 arcsec
///     Jupiter               2 arcsec
///
/// A sky app that skips it is wrong about the Moon by twice its own width.
library;

import 'dart:math' as math;

import 'angles.dart';
import 'coordinates.dart';
import 'nutation.dart';

/// Equatorial radius of the Earth in km, WGS84.
const double _earthEquatorialRadiusKm = 6378.137;

/// Flattening of the WGS84 ellipsoid, 1/298.257223563. The Earth is 21 km wider than it is tall,
/// so treating it as a sphere misplaces an observer at mid-latitude by about 10 km - a tenth of
/// the Moon's parallax, which is small but free to get right.
const double _earthFlattening = 1.0 / 298.257223563;

const double _auKm = 149597870.7;

/// A place on the Earth.
class Observer {
  const Observer({
    required this.latitudeDegrees,
    required this.longitudeEastDegrees,
    this.altitudeMetres = 0,
  });

  /// Positive north.
  final double latitudeDegrees;

  /// Positive EAST. The most common bug in this whole app would be getting this backwards,
  /// which is why the accuracy tests include Quito at -78 degrees.
  final double longitudeEastDegrees;

  final double altitudeMetres;
}

/// The observer's position relative to the Earth's centre, as a rectangular vector in au,
/// in the equatorial frame of date.
EclipticVector observerGeocentricVectorAu(Observer observer, DateTime when) {
  final latitude = observer.latitudeDegrees * degToRad;
  final altitudeKm = observer.altitudeMetres / 1000.0;

  // Geodetic latitude to geocentric distance on the WGS84 ellipsoid.
  final c = 1.0 / math.sqrt(
        math.pow(math.cos(latitude), 2) +
            math.pow((1 - _earthFlattening) * math.sin(latitude), 2),
      );
  final rhoCos = (_earthEquatorialRadiusKm * c + altitudeKm) * math.cos(latitude);
  final rhoSin = (_earthEquatorialRadiusKm * c * math.pow(1 - _earthFlattening, 2) +
          altitudeKm) *
      math.sin(latitude);

  final lst =
      localApparentSiderealTimeDegrees(when, observer.longitudeEastDegrees) * degToRad;

  return EclipticVector(
    rhoCos * math.cos(lst) / _auKm,
    rhoCos * math.sin(lst) / _auKm,
    rhoSin / _auKm,
  );
}

/// Shift a geocentric apparent position to the observer's point of view.
///
/// `distanceAu` is the geocentric distance; the result carries the topocentric distance, which is
/// what the app should quote when it says how far away something is.
TopocentricPosition toTopocentric({
  required Equatorial geocentric,
  required double distanceAu,
  required Observer observer,
  required DateTime when,
}) {
  assert(
    geocentric.equinox == Equinox.ofDate,
    'the observer vector is built in the frame of date, so the body must be too',
  );

  final ra = geocentric.rightAscensionDegrees * degToRad;
  final dec = geocentric.declinationDegrees * degToRad;
  final body = EclipticVector(
    distanceAu * math.cos(dec) * math.cos(ra),
    distanceAu * math.cos(dec) * math.sin(ra),
    distanceAu * math.sin(dec),
  );

  final shifted = body - observerGeocentricVectorAu(observer, when);
  final distance = shifted.length;
  final position = Equatorial(
    rightAscensionDegrees: normalizeDegrees(math.atan2(shifted.y, shifted.x) * radToDeg),
    declinationDegrees: math.asin((shifted.z / distance).clamp(-1.0, 1.0)) * radToDeg,
    equinox: Equinox.ofDate,
  );

  return TopocentricPosition(
    position: position,
    distanceAu: distance,
    horizontal: toHorizontal(
      position: position,
      when: when,
      latitudeDegrees: observer.latitudeDegrees,
      longitudeEastDegrees: observer.longitudeEastDegrees,
    ),
  );
}

/// A body as actually seen from one place at one moment.
class TopocentricPosition {
  const TopocentricPosition({
    required this.position,
    required this.distanceAu,
    required this.horizontal,
  });

  final Equatorial position;
  final double distanceAu;
  final Horizontal horizontal;
}
