/// The one thing this app talks to: NASA/JPL's Horizons ephemeris.
///
/// What goes out: a body code and a timestamp. That is the whole request.
///
/// What does NOT go out: your latitude and longitude. Horizons can compute a position for an
/// observer at a given spot on Earth, and asking it to would mean sending that spot. Instead the
/// app asks for GEOCENTRIC coordinates - as seen from the Earth's centre - and applies the
/// observer correction itself, with the same code the offline path uses. The result is identical
/// and your position stays on the device. `test/online_path_test.dart` measures that the two
/// halves really do add back up.
///
/// Three things learned by measuring this service rather than assuming:
///
///   * **It rate-limits.** 45 requests issued back to back ended with the remote host closing the
///     connection. So requests go out one at a time with a gap, never in a burst, and the app is
///     already usable before the first one returns.
///   * **It sends no CORS header.** A browser therefore blocks the request, so the web build
///     always runs on computed positions. That is not a failure - the offline path is the normal
///     path - but it is why the web build never says "from NASA".
///   * **It answers in plain text**, not JSON, with the data between `$$SOE` and `$$EOE`.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../sky/ephemeris.dart';

/// Horizons body codes. 10 is the Sun, 301 the Moon, n99 a planet's own centre.
const Map<String, String> horizonsBodyCodes = {
  'sun': '10',
  'moon': '301',
  'mercury': '199',
  'venus': '299',
  'mars': '499',
  'jupiter': '599',
  'saturn': '699',
  'uranus': '799',
  'neptune': '899',
};

/// The bodies worth asking about first.
///
/// Ordered by how wrong this app is about them on its own, worst first, measured in
/// `test/accuracy_test.dart`: Saturn 5.0', Jupiter 2.1', Neptune 35", then everything else inside
/// half an arcminute. If the connection is slow or the service throttles, the requests that do
/// land are the ones that change the answer.
const List<String> refinementOrder = [
  'saturn',
  'jupiter',
  'neptune',
  'venus',
  'mars',
  'mercury',
  'uranus',
  'sun',
  'moon',
];

class HorizonsClient {
  HorizonsClient({http.Client? client, this.gapBetweenRequests = const Duration(milliseconds: 250)})
      : _client = client ?? http.Client();

  static const String _endpoint = 'https://ssd.jpl.nasa.gov/api/horizons.api';

  final http.Client _client;

  /// Space between requests. Not politeness theatre - see the rate-limit note above.
  final Duration gapBetweenRequests;

  /// Fetch geocentric positions one body at a time, yielding each as it arrives.
  ///
  /// A stream rather than a single future so the screen can sharpen as answers come in instead of
  /// waiting for all nine. A body that fails is skipped; the caller keeps its computed value.
  Stream<GeocentricReading> geocentricPositions({
    required DateTime when,
    List<String> bodies = refinementOrder,
    Duration perRequestTimeout = const Duration(seconds: 6),
  }) async* {
    var first = true;
    for (final body in bodies) {
      final code = horizonsBodyCodes[body];
      if (code == null) continue;
      if (!first) await Future<void>.delayed(gapBetweenRequests);
      first = false;
      try {
        final reading = await _fetchOne(body, code, when, perRequestTimeout);
        if (reading != null) yield reading;
      } on Object {
        // Any failure at all - no connection, a timeout, a throttle, a changed reply format.
        // The caller already has a computed position for this body, so there is nothing to
        // recover and nothing to report beyond the count the UI shows.
        continue;
      }
    }
  }

  Future<GeocentricReading?> _fetchOne(
    String body,
    String code,
    DateTime when,
    Duration timeout,
  ) async {
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'format': 'text',
        'COMMAND': "'$code'",
        'EPHEM_TYPE': 'OBSERVER',
        // The Earth's centre. Deliberately not 'coord@399', which would require sending the
        // viewer's coordinates.
        'CENTER': "'500@399'",
        'TLIST': "'${_horizonsTime(when)}'",
        // 2 apparent RA/Dec, 9 magnitude, 13 angular diameter, 20 distance.
        'QUANTITIES': "'2,9,13,20'",
        'ANG_FORMAT': 'DEG',
        'CSV_FORMAT': 'YES',
        'EXTRA_PREC': 'YES',
      },
    );

    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) return null;
    return parseHorizonsReply(body, response.body);
  }

  void close() => _client.close();

  /// 'YYYY-MM-DD HH:MM:SS', which is what TLIST accepts.
  static String _horizonsTime(DateTime when) {
    final utc = when.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  }
}

/// Parse one Horizons reply into a reading. Returns null if it carries no ephemeris.
///
/// A top-level function so it can be tested against a saved reply with no network and no client.
/// The committed fixture in `test/fixtures/` is a real response, byte for byte.
GeocentricReading? parseHorizonsReply(String body, String reply) {
  final lines = reply.split('\n');
  final start = lines.indexWhere((line) => line.startsWith(r'$$SOE'));
  final end = lines.indexWhere((line) => line.startsWith(r'$$EOE'));
  if (start < 0 || end <= start + 1) return null;

  // One epoch was requested, so one row is expected. Anything else means the request or the
  // reply format changed, and a silent first-row-wins would hide that.
  final rows = lines
      .sublist(start + 1, end)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (rows.length != 1) return null;

  // date, flag, flag, RA, Dec, APmag, S-brt, Ang-diam, delta, deldot
  final fields = rows.single.split(',');
  if (fields.length < 9) return null;

  final ra = double.tryParse(fields[3].trim());
  final dec = double.tryParse(fields[4].trim());
  final distance = double.tryParse(fields[8].trim());
  if (ra == null || dec == null || distance == null) return null;

  return GeocentricReading(
    body: body,
    rightAscensionDegrees: ra,
    declinationDegrees: dec,
    distanceAu: distance,
    magnitude: double.tryParse(fields[5].trim()),
    angularDiameterArcsec: double.tryParse(fields[7].trim()),
  );
}
