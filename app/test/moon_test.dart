import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starmap/sky/angles.dart';
import 'package:starmap/sky/moon.dart';
import 'package:starmap/sky/observer.dart';

/// How wrong is this app about the Moon?
///
/// Separate from `accuracy_test.dart` because the Moon is a different kind of problem: its
/// position comes from a 60-term trigonometric series rather than from orbital elements, and its
/// diurnal parallax is a thousand times larger than any planet's. A single mistyped coefficient
/// would show up here as arcminutes, which is why the series was typed in and then measured
/// rather than trusted.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/horizons.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final sites = (fixture['sites'] as Map<String, dynamic>).map(
    (name, value) => MapEntry(
      name,
      Observer(
        latitudeDegrees: (value['lat_deg'] as num).toDouble(),
        longitudeEastDegrees: (value['lon_east_deg'] as num).toDouble(),
        altitudeMetres: (value['alt_km'] as num).toDouble() * 1000.0,
      ),
    ),
  );

  final moonRows = (fixture['observations'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((row) => row['body'] == 'moon')
      .toList();

  test('the Moon, measured against JPL Horizons at four sites and four epochs', () {
    expect(moonRows, hasLength(16));

    final separations = <double>[];
    final elevationErrors = <double>[];
    final distanceErrors = <double>[];
    final diameterErrors = <double>[];

    for (final row in moonRows) {
      final observer = sites[row['site']]!;
      final when = DateTime.parse(row['utc'] as String).toUtc();

      final topocentric = toTopocentric(
        geocentric: moonPosition(when),
        distanceAu: moonDistanceKm(when) / 149597870.7,
        observer: observer,
        when: when,
      );

      separations.add(
        angularSeparationDegrees(
              topocentric.position.rightAscensionDegrees,
              topocentric.position.declinationDegrees,
              (row['ra_deg'] as num).toDouble(),
              (row['dec_deg'] as num).toDouble(),
            ) *
            3600,
      );
      elevationErrors.add(
        (topocentric.horizontal.altitudeDegrees -
                    (row['elevation_deg'] as num).toDouble())
                .abs() *
            3600,
      );
      distanceErrors.add(
        ((topocentric.distanceAu - (row['distance_au'] as num).toDouble()) *
                149597870.7)
            .abs(),
      );
      // Horizons quotes the topocentric angular diameter; ours is geocentric, so this is only
      // expected to agree to the few percent that parallax accounts for.
      diameterErrors.add(
        (moonAngularDiameterArcseconds(when) -
                (row['angular_diameter_arcsec'] as num).toDouble())
            .abs(),
      );
    }

    separations.sort();
    elevationErrors.sort();
    distanceErrors.sort();
    diameterErrors.sort();

    // ignore: avoid_print
    print(
      '\n  Moon, 16 topocentric comparisons against JPL Horizons\n'
      '    position   median ${_arcsec(separations[separations.length ~/ 2])}'
      '   worst ${_arcsec(separations.last)}\n'
      '    elevation  worst  ${_arcsec(elevationErrors.last)}\n'
      '    distance   worst  ${distanceErrors.last.toStringAsFixed(1)} km '
      'of about 385,000\n'
      '    diameter   worst  ${diameterErrors.last.toStringAsFixed(1)}" '
      '(ours is geocentric, Horizons topocentric)',
    );

    expect(
      separations.last,
      lessThan(60),
      reason:
          'the Moon is off by ${_arcsec(separations.last)}. Anything above an arcminute points '
          'at a mistyped coefficient in the ELP series, not at truncation.',
    );
    expect(distanceErrors.last, lessThan(50));
  });

  test('parallax is actually being applied', () {
    // The same instant from two places 86 degrees of latitude apart. If the observer vector were
    // ignored, these would be identical; the Moon's parallax makes them differ by most of a
    // degree. This is the test that would have caught a silently geocentric app.
    final when = DateTime.utc(2026, 10, 3, 21);
    final north = toTopocentric(
      geocentric: moonPosition(when),
      distanceAu: moonDistanceKm(when) / 149597870.7,
      observer: const Observer(latitudeDegrees: 52.3676, longitudeEastDegrees: 4.9041),
      when: when,
    );
    final south = toTopocentric(
      geocentric: moonPosition(when),
      distanceAu: moonDistanceKm(when) / 149597870.7,
      observer: const Observer(latitudeDegrees: -33.8688, longitudeEastDegrees: 151.2093),
      when: when,
    );

    final difference = angularSeparationDegrees(
      north.position.rightAscensionDegrees,
      north.position.declinationDegrees,
      south.position.rightAscensionDegrees,
      south.position.declinationDegrees,
    );
    expect(difference, greaterThan(0.5), reason: 'lunar parallax must exceed half a degree here');
    expect(difference, lessThan(2.0));
  });
}

String _arcsec(double value) =>
    value < 60 ? '${value.toStringAsFixed(1)}"' : '${(value / 60).toStringAsFixed(2)}\'';
