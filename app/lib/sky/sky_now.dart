/// One call that answers "what is above me, right now".
///
/// Every screen reads from this. It exists so that no widget does astronomy: a widget that
/// computes its own position is a widget that can disagree with the one next to it, and two
/// screens disagreeing about where Jupiter is would be the fastest way to make the whole app
/// untrustworthy.
library;

import 'dart:math' as math;

import 'brightness.dart';
import 'catalogue.dart';
import 'coordinates.dart';
import 'moon.dart';
import 'observer.dart';
import 'phase.dart';
import 'planets.dart';
import 'sun.dart';
import 'zodiac.dart';

/// Anything the app can point at.
class SkyBody {
  const SkyBody({
    required this.name,
    required this.kind,
    required this.horizontal,
    required this.magnitude,
    required this.distanceAu,
    this.angularDiameterArcsec,
  });

  final String name;
  final SkyBodyKind kind;
  final Horizontal horizontal;

  /// Apparent visual magnitude. Lower is brighter.
  final double magnitude;

  final double distanceAu;

  /// Null for stars, which are points at any magnification this app cares about.
  final double? angularDiameterArcsec;

  bool get isAboveHorizon => horizontal.isAboveHorizon;

  /// Light actually arriving, in lux. The energy screen is built on this.
  double get illuminance => illuminanceLux(magnitude);

  /// How long this light has been travelling, in minutes.
  double get lightTravelMinutes => distanceAu * 499.004784 / 60.0;
}

enum SkyBodyKind { sun, moon, planet, star }

/// Everything at once, for one place and one moment.
class SkyNow {
  const SkyNow({
    required this.when,
    required this.observer,
    required this.sun,
    required this.moon,
    required this.moonPhase,
    required this.nextFull,
    required this.nextNew,
    required this.planets,
    required this.stars,
    required this.zodiac,
    required this.actualConstellationLatin,
  });

  final DateTime when;
  final Observer observer;

  final SkyBody sun;
  final SkyBody moon;
  final MoonPhase moonPhase;
  final DateTime nextFull;
  final DateTime nextNew;

  /// All seven, brightest first, whether or not they are up. An app that hid the ones below the
  /// horizon would leave people wondering where Saturn went.
  final List<SkyBody> planets;

  /// The bright stars that are currently above the horizon, brightest first.
  final List<SkyBody> stars;

  final ZodiacReading zodiac;

  /// The Latin name of the constellation the Sun is actually in, resolved from the catalogue here
  /// rather than in a widget - the UI has no business holding a constellation lookup table.
  final String? actualConstellationLatin;

  /// Is it dark enough to see anything? True astronomical twilight ends when the Sun is 18
  /// degrees down, but 6 degrees - civil twilight - is when the first stars appear, which is the
  /// honest threshold for "go outside and look".
  bool get isDark => sun.horizontal.altitudeDegrees < -6;

  /// Planets that are up, brightest first - the ones worth walking outside for.
  Iterable<SkyBody> get planetsUp => planets.where((p) => p.isAboveHorizon);
}

/// Compute the whole sky for one place and moment.
///
/// `starMagnitudeLimit` of 4.0 keeps the list to the few hundred stars a person can pick out
/// without a dark-sky site, which is what makes the list usable rather than exhaustive.
SkyNow computeSkyNow({
  required DateTime when,
  required Observer observer,
  required Catalogue catalogue,
  double starMagnitudeLimit = 4.0,
}) {
  final utc = when.toUtc();

  final sunTopocentric = toTopocentric(
    geocentric: sunPosition(utc),
    distanceAu: sunDistanceAu(utc),
    observer: observer,
    when: utc,
  );
  final sun = SkyBody(
    name: 'Sun',
    kind: SkyBodyKind.sun,
    horizontal: sunTopocentric.horizontal,
    // The Sun's apparent magnitude is a fixed published figure, not something this app computes:
    // it barely varies, and inventing a model for it would add error for no gain.
    magnitude: -26.74,
    distanceAu: sunTopocentric.distanceAu,
    angularDiameterArcsec: sunAngularDiameterArcseconds(utc),
  );

  final moonTopocentric = toTopocentric(
    geocentric: moonPosition(utc),
    distanceAu: moonDistanceKm(utc) / 149597870.7,
    observer: observer,
    when: utc,
  );
  final phase = moonPhase(utc);
  final moon = SkyBody(
    name: 'Moon',
    kind: SkyBodyKind.moon,
    horizontal: moonTopocentric.horizontal,
    magnitude: _moonMagnitude(phase),
    distanceAu: moonTopocentric.distanceAu,
    angularDiameterArcsec: moonAngularDiameterArcseconds(utc),
  );

  final planets = <SkyBody>[];
  for (final planet in Planet.values) {
    final topocentric = toTopocentric(
      geocentric: geocentricPosition(planet, utc),
      distanceAu: distanceFromEarthAu(planet, utc),
      observer: observer,
      when: utc,
    );
    planets.add(
      SkyBody(
        name: planet.displayName,
        kind: SkyBodyKind.planet,
        horizontal: topocentric.horizontal,
        magnitude: planetMagnitude(planet, utc),
        distanceAu: topocentric.distanceAu,
      ),
    );
  }
  planets.sort((a, b) => a.magnitude.compareTo(b.magnitude));

  final stars = <SkyBody>[];
  for (final star in catalogue.brighterThan(starMagnitudeLimit)) {
    final ofDate = precessEquatorialFromJ2000(
      star.rightAscensionJ2000,
      star.declinationJ2000,
      utc,
    );
    final horizontal = toHorizontal(
      position: ofDate,
      when: utc,
      latitudeDegrees: observer.latitudeDegrees,
      longitudeEastDegrees: observer.longitudeEastDegrees,
    );
    if (!horizontal.isAboveHorizon) continue;
    stars.add(
      SkyBody(
        name: catalogue.nameOf(star),
        kind: SkyBodyKind.star,
        horizontal: horizontal,
        magnitude: star.magnitude,
        // Stars have no meaningful distance in this app's units and no parallax worth applying;
        // a made-up number here would be the one place a fiction crept in.
        distanceAu: double.infinity,
      ),
    );
  }

  final reading = zodiacFor(utc, catalogue.boundaries);

  return SkyNow(
    when: utc,
    observer: observer,
    sun: sun,
    moon: moon,
    moonPhase: phase,
    nextFull: nextFullMoon(utc),
    nextNew: nextNewMoon(utc),
    planets: planets,
    stars: stars,
    zodiac: reading,
    actualConstellationLatin: reading.actualConstellation == null
        ? null
        : catalogue.constellations[reading.actualConstellation]?.latin,
  );
}

/// The Moon's apparent magnitude from its phase.
///
/// A full Moon is magnitude -12.7, a published figure. The fall-off with phase is steep and not
/// proportional - a half-lit Moon is roughly a tenth as bright as a full one, not a half - so the
/// standard logarithmic law is used rather than the intuitive wrong one.
///
/// This is the app's crudest number and it is labelled as such in the energy screen: the real
/// relation also depends on the opposition surge of the lunar surface, which is not modelled.
double _moonMagnitude(MoonPhase phase) {
  // Floor the lit fraction so the logarithm stays finite. At an exact new moon the Moon is
  // unobservable anyway, so the floor is below anything the app would show.
  final lit = phase.illuminatedFraction.clamp(0.0005, 1.0);
  return -12.7 - 2.5 * (math.log(lit) / math.ln10);
}
