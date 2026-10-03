import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starmap/net/horizons.dart';
import 'package:starmap/sky/angles.dart';
import 'package:starmap/sky/catalogue.dart';
import 'package:starmap/sky/coordinates.dart';
import 'package:starmap/sky/ephemeris.dart';
import 'package:starmap/sky/observer.dart';
import 'package:starmap/sky/sky_now.dart';

/// Is the online path right, and is the offline path still there when it is not?
///
/// The online path has two halves that can each be wrong: a reply parsed off the wire, and the
/// observer correction applied to it on the device. Both are tested here with NO NETWORK - the
/// parser against a real saved reply, and the correction against NASA's own topocentric figures
/// for the same bodies at the same instants.
///
/// That second test is the one that matters. The app asks Horizons for GEOCENTRIC positions so
/// that the viewer's coordinates never leave the phone, which only works if the device-side
/// correction reproduces what Horizons would have returned had it been told where you are. This
/// measures exactly that.
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

  final topocentric = (fixture['observations'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final geocentric = (fixture['geocentric'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  group('parsing a real Horizons reply', () {
    final reply = File('test/fixtures/horizons_raw_saturn.txt').readAsStringSync();

    test('reads the row NASA actually sent', () {
      final reading = parseHorizonsReply('saturn', reply);
      expect(reading, isNotNull);
      // The committed reply is Saturn, geocentric, 2026-10-03 21:00:00 UTC. These are its own
      // numbers, not a rounding of them.
      expect(reading!.rightAscensionDegrees, closeTo(11.499278743, 1e-9));
      expect(reading.declinationDegrees, closeTo(1.992873111, 1e-9));
      expect(reading.distanceAu, closeTo(8.43433250139003, 1e-12));
      expect(reading.magnitude, closeTo(0.331, 1e-9));
      expect(reading.angularDiameterArcsec, closeTo(19.70452, 1e-9));
    });

    test('a reply with no ephemeris block gives null, not a wrong number', () {
      // This is what an error page, a rate-limit notice or a changed format looks like. The app
      // must fall back to its own computation rather than parse nonsense out of it.
      expect(parseHorizonsReply('saturn', '{"error": "rate limited"}'), isNull);
      expect(parseHorizonsReply('saturn', ''), isNull);
      expect(parseHorizonsReply('saturn', r'$$SOE' '\n' r'$$EOE'), isNull);
    });

    test('a reply with more rows than were asked for gives null', () {
      // One epoch is requested, so one row is expected. Quietly taking the first of several would
      // hide a request that did not mean what it said.
      final twoRows = reply.replaceFirst(
        r'$$EOE',
        ' 2026-Oct-04 21:00:00.000, , ,  11.5, 2.0, 0.3, 6.5, 19.7, 8.4, -0.4,\n' r'$$EOE',
      );
      expect(parseHorizonsReply('saturn', twoRows), isNull);
    });

    test('the request carries a time and a body, and never a location', () {
      // The privacy claim, asserted against the code that builds the request rather than against
      // a comment about it.
      final client = HorizonsClient();
      addTearDown(client.close);
      // `geocentricPositions` builds its URI internally; what is checked here is that the only
      // centre this app ever names is the Earth's, and that no site coordinate key exists.
      final source = File('lib/net/horizons.dart').readAsStringSync();
      expect(source, contains("'CENTER': \"'500@399'\""));
      expect(source, isNot(contains('SITE_COORD')));
      expect(source, isNot(contains('COORD_TYPE')));
    });
  });

  group('the device-side observer correction reproduces NASA topocentric', () {
    test('every body, every site, every epoch', () {
      final byKey = <String, Map<String, dynamic>>{
        for (final row in geocentric) '${row['body']}|${row['utc']}': row,
      };

      final errors = <String, List<double>>{};
      for (final row in topocentric) {
        final key = '${row['body']}|${row['utc']}';
        final geo = byKey[key];
        expect(geo, isNotNull, reason: 'no geocentric row for $key');

        final observer = sites[row['site']]!;
        final when = DateTime.parse(row['utc'] as String).toUtc();

        final corrected = toTopocentric(
          geocentric: Equatorial(
            rightAscensionDegrees: (geo!['ra_deg'] as num).toDouble(),
            declinationDegrees: (geo['dec_deg'] as num).toDouble(),
            equinox: Equinox.ofDate,
          ),
          distanceAu: (geo['distance_au'] as num).toDouble(),
          observer: observer,
          when: when,
        );

        final separation = angularSeparationDegrees(
          corrected.position.rightAscensionDegrees,
          corrected.position.declinationDegrees,
          (row['ra_deg'] as num).toDouble(),
          (row['dec_deg'] as num).toDouble(),
        );
        errors.putIfAbsent(row['body'] as String, () => []).add(separation * 3600);
      }

      final names = errors.keys.toList()..sort();
      // ignore: avoid_print
      print(
        '\n  NASA geocentric + this app\'s observer correction, against NASA topocentric\n'
        '  body      n   worst',
      );
      // ignore: avoid_print
      print('  ${'-' * 30}');
      for (final name in names) {
        final worst = errors[name]!.reduce((a, b) => a > b ? a : b);
        // ignore: avoid_print
        print(
          '  ${name.padRight(9)} ${errors[name]!.length.toString().padLeft(2)}   '
          '${worst.toStringAsFixed(2)}"',
        );
      }

      for (final name in names) {
        final worst = errors[name]!.reduce((a, b) => a > b ? a : b);
        // The Moon is the test: its parallax is up to a degree, so if the correction were wrong
        // this would be enormous rather than marginal. Two arcseconds leaves no room for a
        // mistake to hide, and it is what makes asking for geocentric positions - and keeping
        // the viewer's location off the network - a free choice rather than a trade-off.
        expect(
          worst,
          lessThan(2.0),
          reason: '$name is off by ${worst.toStringAsFixed(2)}" after the observer correction',
        );
      }
    });
  });

  group('the sky falls back when the reference is absent or partial', () {
    late Catalogue catalogue;
    setUpAll(() {
      catalogue = Catalogue.parse(File('assets/stars.json').readAsStringSync());
    });

    const observer = Observer(latitudeDegrees: 52.3676, longitudeEastDegrees: 4.9041);
    final when = DateTime.utc(2026, 10, 3, 21);

    test('with no reference at all, everything is computed and says so', () {
      final sky = computeSkyNow(when: when, observer: observer, catalogue: catalogue);
      expect(sky.provenance.source, EphemerisSource.computedOnDevice);
      expect(sky.provenance.bodiesFromReference, 0);
      expect(sky.provenance.description, 'Positions computed on this device');
    });

    test('with a partial reference, it reports the count rather than claiming "online"', () {
      // One body out of nine, which is what a throttled or slow connection actually produces.
      final sky = computeSkyNow(
        when: when,
        observer: observer,
        catalogue: catalogue,
        reference: {
          'saturn': const GeocentricReading(
            body: 'saturn',
            rightAscensionDegrees: 11.499278743,
            declinationDegrees: 1.992873111,
            distanceAu: 8.43433250139003,
            magnitude: 0.331,
          ),
        },
      );
      expect(sky.provenance.bodiesFromReference, 1);
      expect(sky.provenance.isFullyReferenced, isFalse);
      expect(sky.provenance.description, contains('1 of 9'));
    });

    test('a reference position actually changes the answer, measurably', () {
      // Saturn is the body this app is worst about, so feeding it NASA's own position should move
      // it by something close to the measured 4-5 arcminute error - not by zero, which would mean
      // the override was ignored, and not by degrees, which would mean it was misapplied.
      final offline = computeSkyNow(when: when, observer: observer, catalogue: catalogue);
      final online = computeSkyNow(
        when: when,
        observer: observer,
        catalogue: catalogue,
        reference: {
          'saturn': const GeocentricReading(
            body: 'saturn',
            rightAscensionDegrees: 11.499278743,
            declinationDegrees: 1.992873111,
            distanceAu: 8.43433250139003,
            magnitude: 0.331,
          ),
        },
      );

      final before = offline.planets.firstWhere((p) => p.name == 'Saturn');
      final after = online.planets.firstWhere((p) => p.name == 'Saturn');
      final shiftArcmin = angularSeparationDegrees(
            before.horizontal.azimuthDegrees,
            before.horizontal.altitudeDegrees,
            after.horizontal.azimuthDegrees,
            after.horizontal.altitudeDegrees,
          ) *
          60;
      // ignore: avoid_print
      print('\n  Saturn moved ${shiftArcmin.toStringAsFixed(2)}\' when NASA\'s position was used');
      expect(shiftArcmin, greaterThan(0.5));
      expect(shiftArcmin, lessThan(30));
      // And the magnitude came along with it.
      expect(after.magnitude, closeTo(0.331, 1e-9));
    });
  });
}
