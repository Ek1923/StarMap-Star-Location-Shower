import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starmap/sky/catalogue.dart';
import 'package:starmap/sky/planets.dart';
import 'package:starmap/ui/solar/camera.dart';
import 'package:starmap/ui/solar/solar_body.dart';
import 'package:starmap/ui/solar/starfield.dart';

/// Is the 3D scene showing the real solar system, or a nice animation?
///
/// The difference is the whole claim, so it is tested rather than asserted: the bodies must sit
/// at the distances the ephemeris gives, be the sizes the IAU publishes, spin at their own rates,
/// and the camera must put a near thing in front of a far one. A scene that looked right while
/// being wrong would be the worst possible outcome here.
void main() {
  group('the camera', () {
    const screenWidth = 800.0;
    const screenHeight = 600.0;

    test('a body at the target lands in the middle of the screen', () {
      final camera = SolarCamera(target: Vec3.zero, distanceAu: 3);
      final at = camera.project(
        Vec3.zero,
        0.1,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(at.isVisible, isTrue);
      expect(at.screenX, closeTo(screenWidth / 2, 0.01));
      expect(at.screenY, closeTo(screenHeight / 2, 0.01));
    });

    test('something behind the camera is not drawn in front of it', () {
      // The classic perspective bug: a negative depth divides through and projects a body behind
      // you to a mirrored position in front of you, where it appears as a ghost planet.
      final camera = SolarCamera(target: Vec3.zero, distanceAu: 3, yaw: 0, pitch: 0);
      final behind = camera.position * 2.0;
      final at = camera.project(
        behind,
        0.1,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      expect(at.isVisible, isFalse);
    });

    test('approaching a body makes it bigger, by the right amount', () {
      // Angular size goes as 1/depth. Halving the distance must DOUBLE the pixel radius, not
      // merely increase it - that is the difference between perspective and a zoom effect.
      //
      // The body is at the camera's target so that depth along the view direction equals the
      // distance. An off-axis body would not satisfy this ratio, and that is geometry rather
      // than a bug: the pixel radius divides by the depth, which for anything beside the axis is
      // shorter than the distance. The first version of this test got that wrong.
      final far = SolarCamera(target: Vec3.zero, distanceAu: 4);
      final near = SolarCamera(target: Vec3.zero, distanceAu: 2);
      final a = far.project(Vec3.zero, 0.05,
          screenWidth: screenWidth, screenHeight: screenHeight);
      final b = near.project(Vec3.zero, 0.05,
          screenWidth: screenWidth, screenHeight: screenHeight);
      expect(b.radiusPixels / a.radiusPixels, closeTo(2.0, 0.001));
    });

    test('pitch cannot reach the pole, where the up vector would collapse', () {
      final camera = SolarCamera();
      for (var i = 0; i < 100; i++) {
        camera.orbit(0, 1.0);
      }
      expect(camera.pitch.abs(), lessThan(1.5));
      // And the basis stays orthonormal, which is what the clamp is protecting.
      final b = camera.basis;
      expect(b.right.dot(b.up).abs(), lessThan(1e-6));
      expect(b.right.length, closeTo(1.0, 1e-9));
      expect(b.up.length, closeTo(1.0, 1e-9));
    });

    test('zoom is bounded so the camera cannot end up inside the Sun', () {
      final camera = SolarCamera();
      for (var i = 0; i < 200; i++) {
        camera.zoom(0.5);
      }
      // The Sun's radius is 0.00465 au. The floor has to be outside it.
      expect(camera.distanceAu, greaterThan(695700 / auKm));
    });
  });

  group('the bodies are the real ones', () {
    test('radii are the published values, so relative sizes are true', () {
      SolarBody body(String name) => solarBodies.firstWhere((b) => b.name == name);
      // Jupiter is 11.2 Earth radii. If this ratio were wrong the scene would look plausible and
      // be lying about the single most striking fact in the solar system.
      expect(
        body('Jupiter').equatorialRadiusKm / body('Earth').equatorialRadiusKm,
        closeTo(11.2, 0.05),
      );
      // The Sun is 109 Earth radii.
      expect(
        body('Sun').equatorialRadiusKm / body('Earth').equatorialRadiusKm,
        closeTo(109.1, 0.5),
      );
      // The Moon is just over a quarter of Earth.
      expect(
        body('Moon').equatorialRadiusKm / body('Earth').equatorialRadiusKm,
        closeTo(0.2724, 0.001),
      );
    });

    test('Venus and Uranus spin the way they really do', () {
      SolarBody body(String name) => solarBodies.firstWhere((b) => b.name == name);
      // Venus is retrograde: the sign is the fact, and a positive value would have it turning
      // the wrong way on screen.
      expect(body('Venus').rotationPeriodHours, lessThan(0));
      // And its day is longer than most planets' years.
      expect(body('Venus').rotationPeriodHours.abs(), greaterThan(5000));
      // Uranus is tipped past its own pole, which is why it rolls rather than spins.
      expect(body('Uranus').axialTiltDegrees, greaterThan(90));
      // Jupiter turns in under ten hours despite being the largest planet.
      expect(body('Jupiter').rotationPeriodHours, lessThan(10));
    });

    test('airless bodies have no atmospheric glow', () {
      // A rim light on the Moon or Mercury would be inventing an atmosphere. The scene is allowed
      // to exaggerate size, because it says so; it is not allowed to add physics.
      for (final name in ['Moon', 'Mercury']) {
        final body = solarBodies.firstWhere((b) => b.name == name);
        expect(body.rimStrength, 0.0, reason: '$name has no atmosphere');
      }
      expect(solarBodies.firstWhere((b) => b.name == 'Earth').rimStrength, greaterThan(0));
    });

    test('every body has a texture that is actually in the bundle', () {
      for (final body in solarBodies) {
        expect(
          File(body.textureAsset).existsSync(),
          isTrue,
          reason: '${body.name} points at ${body.textureAsset}, which is not on disk',
        );
      }
    });
  });

  group('the scene uses real positions', () {
    test('the planets are at their real distances from the Sun', () {
      // Semi-major axes, in au. If the scene drew planets on evenly spaced circles - which is
      // what almost every solar system illustration does - these would all be wrong.
      final when = DateTime.utc(2026, 10, 3, 12);
      const expected = {
        Planet.mercury: 0.387,
        Planet.venus: 0.723,
        Planet.mars: 1.524,
        Planet.jupiter: 5.203,
        Planet.saturn: 9.537,
        Planet.uranus: 19.19,
        Planet.neptune: 30.07,
      };
      for (final entry in expected.entries) {
        final r = heliocentricPosition(entry.key, when).length;
        // Within 25%: these are instantaneous distances and the orbits are eccentric, so the
        // tolerance is the eccentricity rather than slack.
        expect(
          r,
          closeTo(entry.value, entry.value * 0.25),
          reason: '${entry.key.displayName} is at $r au',
        );
      }
    });
  });

  group('the starfield is the real sky', () {
    late Catalogue catalogue;
    setUpAll(() {
      catalogue = Catalogue.parse(File('assets/stars.json').readAsStringSync());
    });

    test('every naked-eye star becomes a point on a unit sphere', () {
      // 8,404 of the catalogue's 9,096 rows are at magnitude 6.5 or brighter. The Yale catalogue
      // runs a little past its own nominal limit, so the remaining 692 are fainter than anything
      // a human eye resolves and are left out. Measured, not assumed - the first version of this
      // test expected all 9,096.
      final points = starPoints(catalogue);
      expect(points.length, 8404);
      for (final point in points.take(500)) {
        expect(point.direction.length, closeTo(1.0, 1e-6));
      }
    });

    test('brighter stars are drawn bigger', () {
      final points = starPoints(catalogue);
      // The catalogue is sorted brightest first, so the first point must not be smaller than a
      // later one.
      expect(points.first.radius, greaterThan(points.last.radius));
    });

    test('star colour follows the measured B-V index, not a palette', () {
      // A hot blue star and a cool red one must not come out the same colour. Rigel's B-V is
      // about -0.03 and Betelgeuse's about +1.85, and that difference is a temperature
      // measurement rather than a styling choice.
      final blue = catalogue.stars.firstWhere(
        (s) => s.colourIndex != null && s.colourIndex! < -0.1 && s.magnitude < 3,
      );
      final red = catalogue.stars.firstWhere(
        (s) => s.colourIndex != null && s.colourIndex! > 1.5 && s.magnitude < 3,
      );
      final points = starPoints(catalogue);
      final bluePoint = points[catalogue.stars.indexOf(blue)];
      final redPoint = points[catalogue.stars.indexOf(red)];
      // The blue one must be bluer: more blue than red channel, and the red one the reverse.
      expect(bluePoint.color.b, greaterThan(bluePoint.color.r));
      expect(redPoint.color.r, greaterThan(redPoint.color.b));
    });
  });
}
