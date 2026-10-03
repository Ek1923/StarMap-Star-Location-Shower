/// The bodies in the scene, with their real numbers.
///
/// Radii, rotation periods and axial tilts are published values, not chosen for looks. They are
/// what makes Jupiter eleven times wider than Earth on screen, Uranus roll on its side, and
/// Venus turn backwards - all of which are true and none of which would happen if these were
/// picked by eye.
library;

import 'dart:ui' as ui;

import '../../sky/planets.dart';

/// One body: how big it is, how it spins, and which picture of it to use.
class SolarBody {
  const SolarBody({
    required this.name,
    required this.textureAsset,
    required this.equatorialRadiusKm,
    required this.rotationPeriodHours,
    required this.axialTiltDegrees,
    this.planet,
    this.isSun = false,
    this.isMoon = false,
    this.rimStrength = 0.0,
    this.rimColor = const ui.Color(0xFF7FB2FF),
    this.hasRings = false,
  });

  final String name;
  final String textureAsset;

  /// Equatorial radius in km, IAU values. The Sun's is the 2015 nominal radius.
  final double equatorialRadiusKm;

  /// Sidereal rotation period in hours. Negative means retrograde - Venus really does turn the
  /// other way, and so the scene shows it turning the other way.
  final double rotationPeriodHours;

  /// Obliquity in degrees. Uranus at 97.8 is why it appears to roll rather than spin.
  final double axialTiltDegrees;

  /// Which planet's orbit to ask the ephemeris for. Null for the Sun and the Moon, which are
  /// positioned differently.
  final Planet? planet;

  final bool isSun;
  final bool isMoon;

  /// How strongly to draw an atmospheric limb. Zero on airless bodies: the Moon and Mercury have
  /// no atmosphere and must not have a glow, or the scene starts lying about what is out there.
  final double rimStrength;

  final ui.Color rimColor;

  final bool hasRings;
}

/// The Sun, the eight planets and the Moon.
///
/// Sources for the numbers: IAU 2015 nominal values for the Sun and Earth, and the NASA planetary
/// fact sheets for the rest. Rotation periods are sidereal.
const List<SolarBody> solarBodies = [
  SolarBody(
    name: 'Sun',
    textureAsset: 'assets/planets/2k_sun.jpg',
    equatorialRadiusKm: 695700,
    rotationPeriodHours: 609.12, // about 25.4 days at the equator
    axialTiltDegrees: 7.25,
    isSun: true,
  ),
  SolarBody(
    name: 'Mercury',
    textureAsset: 'assets/planets/2k_mercury.jpg',
    equatorialRadiusKm: 2439.7,
    rotationPeriodHours: 1407.6,
    axialTiltDegrees: 0.034,
    planet: Planet.mercury,
    // No atmosphere worth the name, so no rim.
  ),
  SolarBody(
    name: 'Venus',
    textureAsset: 'assets/planets/2k_venus_atmosphere.jpg',
    equatorialRadiusKm: 6051.8,
    // Retrograde, and slower than its own year. The minus sign is the fact.
    rotationPeriodHours: -5832.5,
    axialTiltDegrees: 177.4,
    planet: Planet.venus,
    rimStrength: 0.55,
    rimColor: ui.Color(0xFFFFE6B0),
  ),
  SolarBody(
    name: 'Earth',
    textureAsset: 'assets/planets/2k_earth_daymap.jpg',
    equatorialRadiusKm: 6378.137,
    rotationPeriodHours: 23.9345,
    axialTiltDegrees: 23.4393,
    rimStrength: 0.75,
    rimColor: ui.Color(0xFF6FA8FF),
  ),
  SolarBody(
    name: 'Moon',
    textureAsset: 'assets/planets/2k_moon.jpg',
    equatorialRadiusKm: 1737.4,
    rotationPeriodHours: 655.72,
    axialTiltDegrees: 6.68,
    isMoon: true,
  ),
  SolarBody(
    name: 'Mars',
    textureAsset: 'assets/planets/2k_mars.jpg',
    equatorialRadiusKm: 3396.2,
    rotationPeriodHours: 24.6229,
    axialTiltDegrees: 25.19,
    planet: Planet.mars,
    rimStrength: 0.18,
    rimColor: ui.Color(0xFFFFB38A),
  ),
  SolarBody(
    name: 'Jupiter',
    textureAsset: 'assets/planets/2k_jupiter.jpg',
    equatorialRadiusKm: 71492,
    rotationPeriodHours: 9.9250,
    axialTiltDegrees: 3.13,
    planet: Planet.jupiter,
    rimStrength: 0.30,
    rimColor: ui.Color(0xFFFFD9A8),
  ),
  SolarBody(
    name: 'Saturn',
    textureAsset: 'assets/planets/2k_saturn.jpg',
    equatorialRadiusKm: 60268,
    rotationPeriodHours: 10.656,
    axialTiltDegrees: 26.73,
    planet: Planet.saturn,
    rimStrength: 0.26,
    rimColor: ui.Color(0xFFFFE9C4),
    hasRings: true,
  ),
  SolarBody(
    name: 'Uranus',
    textureAsset: 'assets/planets/2k_uranus.jpg',
    equatorialRadiusKm: 25559,
    rotationPeriodHours: -17.24,
    // 97.77 degrees. Uranus is tipped past its own pole, which is why it rolls.
    axialTiltDegrees: 97.77,
    planet: Planet.uranus,
    rimStrength: 0.34,
    rimColor: ui.Color(0xFF9FE8F2),
  ),
  SolarBody(
    name: 'Neptune',
    textureAsset: 'assets/planets/2k_neptune.jpg',
    equatorialRadiusKm: 24764,
    rotationPeriodHours: 16.11,
    axialTiltDegrees: 28.32,
    planet: Planet.neptune,
    rimStrength: 0.34,
    rimColor: ui.Color(0xFF7FA8FF),
  ),
];

/// One astronomical unit in km, for turning radii into the same units as the orbits.
const double auKm = 149597870.7;
