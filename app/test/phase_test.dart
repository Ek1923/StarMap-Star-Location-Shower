import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starmap/sky/phase.dart';

/// Is the Moon's phase right?
///
/// Checked against the `Illu%` column of NASA/JPL's ephemeris at the same sixteen epochs the
/// position tests use. This is a real external check, not self-consistency: the illuminated
/// fraction comes out of the Sun-Moon geometry, so if either body's longitude were wrong the
/// percentage would be wrong with it.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/horizons.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final moonRows = (fixture['observations'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((row) => row['body'] == 'moon')
      .toList();

  test('illuminated fraction against JPL', () {
    final errors = <double>[];
    for (final row in moonRows) {
      final when = DateTime.parse(row['utc'] as String).toUtc();
      final reference = (row['illuminated_percent'] as num).toDouble();
      final computed = moonPhase(when).illuminatedFraction * 100;
      errors.add((computed - reference).abs());
    }
    errors.sort();
    // ignore: avoid_print
    print(
      '\n  Moon illumination, 16 epochs: median '
      '${errors[errors.length ~/ 2].toStringAsFixed(3)} percentage points, '
      'worst ${errors.last.toStringAsFixed(3)}',
    );
    expect(errors.last, lessThan(1.0));
  });

  test('a full moon really is full, and a new moon really is new', () {
    final full = nextFullMoon(DateTime.utc(2026, 10, 3));
    final atFull = moonPhase(full);
    expect(atFull.elongationDegrees, closeTo(180, 0.01));
    expect(atFull.illuminatedFraction, greaterThan(0.999));

    final newMoon = nextNewMoon(DateTime.utc(2026, 10, 3));
    final atNew = moonPhase(newMoon);
    // Elongation near zero wraps, so test the distance to 0 or 360 rather than the raw value.
    final fromNew = atNew.elongationDegrees > 180
        ? 360 - atNew.elongationDegrees
        : atNew.elongationDegrees;
    expect(fromNew, lessThan(0.01));
    expect(atNew.illuminatedFraction, lessThan(0.001));
  });

  test('consecutive full moons are a synodic month apart', () {
    // Not a tautology: the search could lock onto the same crossing twice, or skip one. The
    // observed spacing varies by about half a day either side of the mean because the Moon's
    // orbit is eccentric, so the tolerance is real rather than slack.
    final first = nextFullMoon(DateTime.utc(2026, 1, 1));
    final second = nextFullMoon(first.add(const Duration(days: 1)));
    final gapDays = second.difference(first).inMinutes / (60 * 24);
    expect(gapDays, closeTo(meanSynodicMonthDays, 0.8));
  });

  test('the phase name follows the geometry', () {
    final full = nextFullMoon(DateTime.utc(2026, 10, 3));
    expect(moonPhase(full).name, 'Full moon');
    expect(moonPhase(nextNewMoon(DateTime.utc(2026, 10, 3))).name, 'New moon');
    // A week after new is a first quarter, waxing.
    final quarter = moonPhase(
      nextNewMoon(DateTime.utc(2026, 10, 3)).add(const Duration(days: 7, hours: 9)),
    );
    expect(quarter.isWaxing, isTrue);
    expect(quarter.illuminatedFraction, closeTo(0.5, 0.1));
  });
}
