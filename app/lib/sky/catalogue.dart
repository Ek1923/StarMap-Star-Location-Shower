/// The star catalogue, loaded from the asset the Python build produced.
///
/// Read once at startup and kept in memory: 9,096 stars is 450 KB of JSON and a few hundred
/// kilobytes of objects, which is nothing on a phone, and it means every later question about
/// the sky is answered without touching storage.
///
/// A JSON asset rather than the SQLite file that `data/build_catalogue.py` also writes, for one
/// practical reason: reading SQLite from Flutter needs a native plugin, native plugins do not
/// work on the web, and the web is a target here. The .db remains the canonical artefact and the
/// thing the Python tests assert against; this is the same data in a form every platform can
/// read with no dependency at all.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle;

import 'constellation_boundaries.dart';

/// One star, as the app needs it.
class Star {
  const Star({
    required this.hr,
    required this.rightAscensionJ2000,
    required this.declinationJ2000,
    required this.magnitude,
    required this.colourIndex,
    required this.constellation,
    required this.properName,
  });

  /// Harvard Revised number - the Yale catalogue's own identifier.
  final int hr;

  final double rightAscensionJ2000;
  final double declinationJ2000;

  /// Visual magnitude. Lower is brighter; the naked-eye limit in a dark sky is about 6.
  final double magnitude;

  /// B-V colour index, or null when the catalogue has none. Positive is redder.
  final double? colourIndex;

  /// IAU constellation abbreviation.
  final String constellation;

  /// The IAU-approved proper name, or null - which is the case for 8,755 of the 9,096. The app
  /// shows the designation instead rather than inventing a popular name.
  final String? properName;
}

/// One of the 88 constellations.
class Constellation {
  const Constellation({
    required this.abbreviation,
    required this.latin,
    required this.genitive,
    required this.english,
  });

  final String abbreviation;
  final String latin;
  final String genitive;
  final String english;
}

/// Everything the asset carries.
class Catalogue {
  Catalogue({
    required this.stars,
    required this.constellations,
    required this.boundaries,
    required this.source,
    required this.builtUtc,
  });

  /// Sorted brightest first, which is the order every screen wants.
  final List<Star> stars;

  final Map<String, Constellation> constellations;

  /// The IAU boundary bands, in catalogue order.
  final List<BoundaryBand> boundaries;

  /// Where the data came from, for the about screen. Shown, not hidden.
  final String source;

  final String builtUtc;

  /// Load from the bundled asset.
  static Future<Catalogue> load(AssetBundle bundle) async {
    final text = await bundle.loadString('assets/stars.json');
    return parse(text);
  }

  /// Parse the asset's JSON. Separate from `load` so tests can read the file directly.
  static Catalogue parse(String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final format = root['format'];
    if (format != 'starmap-stars-1') {
      throw FormatException(
        'assets/stars.json has format "$format", this build expects "starmap-stars-1". '
        'Rebuild it: py -3.12 data/build_catalogue.py',
      );
    }

    final stars = (root['stars'] as List<dynamic>).map((row) {
      final fields = row as List<dynamic>;
      return Star(
        hr: fields[0] as int,
        rightAscensionJ2000: (fields[1] as num).toDouble(),
        declinationJ2000: (fields[2] as num).toDouble(),
        magnitude: (fields[3] as num).toDouble(),
        colourIndex: (fields[4] as num?)?.toDouble(),
        constellation: fields[5] as String,
        properName: fields[6] as String?,
      );
    }).toList(growable: false);

    final constellations = (root['constellations'] as Map<String, dynamic>).map(
      (abbr, value) => MapEntry(
        abbr,
        Constellation(
          abbreviation: abbr,
          latin: (value as Map<String, dynamic>)['latin'] as String,
          genitive: value['genitive'] as String,
          english: value['english'] as String,
        ),
      ),
    );

    final boundaries = (root['boundaries'] as List<dynamic>).map((row) {
      final fields = row as List<dynamic>;
      return BoundaryBand(
        raLowHours: (fields[0] as num).toDouble(),
        raUpHours: (fields[1] as num).toDouble(),
        decLowDegrees: (fields[2] as num).toDouble(),
        constellation: fields[3] as String,
      );
    }).toList(growable: false);

    return Catalogue(
      stars: stars,
      constellations: constellations,
      boundaries: boundaries,
      source: root['source'] as String,
      builtUtc: root['built_utc'] as String,
    );
  }

  /// Stars brighter than `magnitude`, in brightest-first order.
  ///
  /// The default of 5.0 is not arbitrary: it is roughly what is visible from a suburban garden,
  /// and drawing all 9,096 in a city sky would show a field of stars nobody can see.
  Iterable<Star> brighterThan([double magnitude = 5.0]) =>
      stars.takeWhile((star) => star.magnitude < magnitude);

  /// The display name for a star: its IAU name when it has one, otherwise its catalogue number
  /// with the constellation, which is what astronomers would call it.
  String nameOf(Star star) {
    if (star.properName != null) return star.properName!;
    final constellation = constellations[star.constellation];
    return 'HR ${star.hr}${constellation == null ? '' : ' in ${constellation.latin}'}';
  }
}
