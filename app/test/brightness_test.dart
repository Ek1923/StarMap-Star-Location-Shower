import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starmap/sky/brightness.dart';
import 'package:starmap/sky/planets.dart';

/// How wrong is this app about brightness?
///
/// Measured against the `APmag` column of NASA/JPL's own ephemeris. This matters more than it
/// looks: the whole energy screen is derived from magnitude, so an error here propagates straight
/// into the illuminance figures the app puts in front of people.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/horizons.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  const planetsByName = {
    'mercury': Planet.mercury,
    'venus': Planet.venus,
    'mars': Planet.mars,
    'jupiter': Planet.jupiter,
    'saturn': Planet.saturn,
    'uranus': Planet.uranus,
    'neptune': Planet.neptune,
  };

  test('planet magnitudes against JPL', () {
    // Magnitude does not depend on where on Earth you stand, so one site is enough; taking all
    // four would report the same four numbers four times and hide that.
    final rows = (fixture['observations'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((row) => row['site'] == 'amsterdam')
        .where((row) => planetsByName.containsKey(row['body']))
        .toList();

    final errors = <String, List<double>>{};
    for (final row in rows) {
      final planet = planetsByName[row['body']]!;
      final when = DateTime.parse(row['utc'] as String).toUtc();
      final reference = (row['apparent_magnitude'] as num).toDouble();
      final computed = planetMagnitude(planet, when);
      errors
          .putIfAbsent(row['body'] as String, () => [])
          .add((computed - reference).abs());
    }

    final names = errors.keys.toList()..sort();
    // ignore: avoid_print
    print('\n  body      worst magnitude error');
    // ignore: avoid_print
    print('  ${'-' * 34}');
    for (final name in names) {
      final worst = errors[name]!.reduce(math.max);
      // ignore: avoid_print
      print('  ${name.padRight(9)} ${worst.toStringAsFixed(3)} mag');
    }

    // One budget per planet, each set just above what was actually MEASURED on 2026-10-03, so a
    // regression trips the test instead of hiding inside a single generous bound. The numbers are
    // the measurement, not a target:
    //
    //   jupiter 0.007   uranus 0.018   mars 0.115   neptune 0.130
    //   venus   0.225   saturn 0.293   mercury 0.700
    //
    // Mercury is the bad one, by a factor of five. Two reasons, both real: the Almanac polynomial
    // is only valid between about 2 and 170 degrees of phase angle and Mercury spends much of its
    // time near those limits, and an inferior planet's phase term is a cubic that diverges fast.
    // It is left as it is rather than patched with a better-fitting curve nobody published,
    // because Mercury never leaves the Sun's glare anyway and the app says so. A 0.7 magnitude
    // error is a factor of 1.9 in the illuminance figure, which the energy screen discloses.
    const budget = <String, double>{
      'jupiter': 0.05,
      'uranus': 0.05,
      'mars': 0.20,
      'neptune': 0.20,
      'venus': 0.30,
      'saturn': 0.40,
      'mercury': 0.80,
    };
    for (final name in names) {
      final worst = errors[name]!.reduce(math.max);
      expect(
        worst,
        lessThan(budget[name]!),
        reason: '$name magnitude is off by ${worst.toStringAsFixed(3)}, '
            'budget ${budget[name]}',
      );
    }
  });

  test('the illuminance relation matches its definition', () {
    // Magnitude 0 is 2.56e-6 lux by the standard V-band relation. Anchoring the zero point is
    // what stops the whole energy screen from being off by a constant factor.
    expect(illuminanceLux(0), closeTo(2.56e-6, 0.02e-6));
    // Five magnitudes is a factor of exactly 100, by definition.
    expect(illuminanceLux(0) / illuminanceLux(5), closeTo(100.0, 1e-9));
  });

  test('every planet is fainter than a full Moon, by a lot', () {
    // Not a tautology worth skipping: it is the sanity check behind the honest line the app shows
    // next to the energy ranking. If any planet came out comparable to the Moon, the zero point
    // would be wrong.
    final when = DateTime.utc(2026, 10, 3, 21);
    for (final planet in Planet.values) {
      final delivery = LightDelivery(
        name: planet.displayName,
        magnitude: planetMagnitude(planet, when),
        distanceAu: distanceFromEarthAu(planet, when),
        altitudeDegrees: 30,
      );
      expect(
        delivery.timesFainterThanFullMoon,
        greaterThan(1000),
        reason: '${planet.displayName} should be thousands of times fainter than a full Moon',
      );
    }
  });
}
