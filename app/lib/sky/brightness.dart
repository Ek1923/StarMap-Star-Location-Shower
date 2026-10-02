/// How bright a body looks, and how much light energy that actually puts on you.
///
/// This file is the honest answer to "does Jupiter have more energy than Mars tonight".
///
/// It does not answer it with astrology. There is no measurable influence of a planet on a human
/// body - the numbers below are exactly why, and they are more interesting than the claim they
/// replace. What a planet genuinely delivers is LIGHT, and light is energy, and it is measurable:
/// Jupiter really does put more photons on your face than Mars does, or sometimes fewer, and
/// which one wins changes from month to month. That is a fact, it is computable, and it is a
/// better thing to look at than a horoscope.
///
/// Illuminance is used rather than watts per square metre because illuminance is already weighted
/// by the sensitivity of the human eye. For the question "how much of this can a person actually
/// receive", that is the correct physical quantity, not a simplification of it.
///
/// Magnitude models: the standard Astronomical Almanac polynomials. Their measured error against
/// NASA/JPL's own published magnitudes is in `test/brightness_test.dart`.
library;

import 'dart:math' as math;

import 'planets.dart';

/// Illuminance in lux produced by a point source of apparent magnitude `magnitude`, above the
/// atmosphere.
///
/// E = 10^(-0.4 (m + 13.98)) lux, the standard V-band relation: magnitude 0 gives 2.56e-6 lux.
/// Nothing in this app scales or fudges it.
double illuminanceLux(double magnitude) =>
    math.pow(10.0, -0.4 * (magnitude + 13.98)).toDouble();

/// Reference illuminances, for the comparison that makes the planet numbers mean something.
///
/// These are standard published figures for a clear sky at the Earth's surface, not computed
/// here, and they are labelled as references rather than as results.
class ReferenceIlluminance {
  /// Direct sunlight, roughly.
  static const double sunlightLux = 100000.0;

  /// A full Moon at the zenith, roughly.
  static const double fullMoonLux = 0.25;

  /// A moonless, starlit night sky, roughly.
  static const double starlightLux = 0.002;
}

/// Apparent visual magnitude of a planet.
///
/// Astronomical Almanac polynomials in the phase angle. Lower is brighter; Venus reaches about
/// -4.5, Neptune sits near +7.8 and is invisible without binoculars.
double planetMagnitude(Planet planet, DateTime when) {
  final heliocentric = heliocentricPosition(planet, when);
  final earth = earthHeliocentricPosition(when);
  final geocentric = heliocentric - earth;

  final r = heliocentric.length; // planet to Sun, au
  final delta = geocentric.length; // planet to Earth, au
  final sunToEarth = earth.length;

  // Phase angle at the planet, between the Sun and the Earth, by the cosine rule.
  final cosPhase =
      (r * r + delta * delta - sunToEarth * sunToEarth) / (2 * r * delta);
  final phaseDegrees = math.acos(cosPhase.clamp(-1.0, 1.0)) * 180.0 / math.pi;

  final distanceTerm = 5 * (math.log(r * delta) / math.ln10);
  final a = phaseDegrees;

  switch (planet) {
    case Planet.mercury:
      return -0.42 +
          distanceTerm +
          0.0380 * a -
          0.000273 * a * a +
          2.00e-6 * a * a * a;
    case Planet.venus:
      return -4.40 +
          distanceTerm +
          0.0009 * a +
          2.39e-4 * a * a -
          6.5e-7 * a * a * a;
    case Planet.mars:
      return -1.52 + distanceTerm + 0.016 * a;
    case Planet.jupiter:
      return -9.40 + distanceTerm + 0.005 * a;
    case Planet.saturn:
      // No ring term. Saturn's rings contribute up to about 0.8 magnitudes depending on how open
      // they are to us, and modelling that needs the ring tilt, which needs Saturn's pole
      // orientation. Left out, and the resulting error is measured rather than guessed at - see
      // the brightness test. Saturn is the one body whose brightness this app gets visibly wrong.
      return -8.88 + distanceTerm;
    case Planet.uranus:
      return -7.19 + distanceTerm + 0.0028 * a;
    case Planet.neptune:
      return -6.87 + distanceTerm;
  }
}

/// A body ranked by the light it is actually delivering, for the energy screen.
class LightDelivery implements Comparable<LightDelivery> {
  const LightDelivery({
    required this.name,
    required this.magnitude,
    required this.distanceAu,
    required this.altitudeDegrees,
  });

  final String name;
  final double magnitude;
  final double distanceAu;

  /// Degrees above the horizon. Below it, none of this light reaches you at all, which the UI
  /// must say rather than quietly ranking an invisible planet first.
  final double altitudeDegrees;

  double get illuminance => illuminanceLux(magnitude);

  bool get isAboveHorizon => altitudeDegrees > 0;

  /// How many minutes ago this light left.
  double get lightTravelMinutes => distanceAu * 499.004784 / 60.0;

  /// How many times fainter than a full Moon. Always greater than one for every planet, and that
  /// is the point of showing it.
  double get timesFainterThanFullMoon =>
      ReferenceIlluminance.fullMoonLux / illuminance;

  /// Brightest first.
  @override
  int compareTo(LightDelivery other) => magnitude.compareTo(other.magnitude);
}
