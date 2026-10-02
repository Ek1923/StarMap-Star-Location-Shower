/// Your star sign, next to where the Sun actually is.
///
/// Both are shown, and which is which is never blurred. The sign is a tradition, computed exactly
/// from the Sun's real ecliptic longitude. The constellation is a measurement. They disagree by
/// about one whole sign, and that gap has a name and a cause, which is the most interesting thing
/// on this screen.
library;

import 'package:flutter/material.dart';

import '../sky/sky_now.dart';
import 'theme.dart';

class SignPage extends StatelessWidget {
  const SignPage({required this.sky, super.key});

  final SkyNow sky;

  @override
  Widget build(BuildContext context) {
    final reading = sky.zodiac;
    final actual = sky.actualConstellationLatin;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      children: [
        const SizedBox(height: Space.section),
        Text('The Sun is in ${reading.sign.name}.', style: Face.display),
        const SizedBox(height: Space.row),
        Text(
          'Anyone born today is ${_article(reading.sign.name)} ${reading.sign.name} - '
          '${reading.degreesIntoSign.toStringAsFixed(1)}° into the sign, of thirty.',
          style: Face.body,
        ),
        const SizedBox(height: Space.section),
        _Pair(
          leftTitle: reading.sign.name,
          leftBody: 'The tropical zodiac. The ecliptic cut into twelve equal thirty-degree '
              'slices, counted from the spring equinox. The Sun is at '
              '${reading.solarLongitudeDegrees.toStringAsFixed(1)}° along it.',
          leftKind: 'tradition',
          rightTitle: actual ?? 'unknown',
          rightBody: actual == null
              ? 'The boundary table could not place the Sun, which means the catalogue needs '
                  'rebuilding.'
              : 'Where the Sun physically is tonight, by the constellation boundaries the IAU '
                  'drew in 1930.',
          rightKind: 'measured',
        ),
        const SizedBox(height: Space.section),
        if (reading.traditionDisagreesWithSky && actual != null) const _Precession(),
        const SizedBox(height: Space.section),
      ],
    );
  }

  String _article(String name) =>
      'AEIOU'.contains(name[0].toUpperCase()) ? 'an' : 'a';
}

class _Pair extends StatelessWidget {
  const _Pair({
    required this.leftTitle,
    required this.leftBody,
    required this.leftKind,
    required this.rightTitle,
    required this.rightBody,
    required this.rightKind,
  });

  final String leftTitle;
  final String leftBody;
  final String leftKind;
  final String rightTitle;
  final String rightBody;
  final String rightKind;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Half(title: leftTitle, body: leftBody, kind: leftKind, measured: false),
          const SizedBox(height: Space.section),
          _Half(title: rightTitle, body: rightBody, kind: rightKind, measured: true),
        ],
      );
}

class _Half extends StatelessWidget {
  const _Half({
    required this.title,
    required this.body,
    required this.kind,
    required this.measured,
  });

  final String title;
  final String body;
  final String kind;

  /// Measured things are warm; the tradition is cool. The palette carries the distinction so the
  /// screen does not have to keep repeating it in words.
  final bool measured;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                title,
                style: Face.title.copyWith(
                  fontSize: 28,
                  color: measured ? Night.amber : Night.parchment,
                ),
              ),
              const SizedBox(width: Space.row),
              Text(kind, style: Face.quiet),
            ],
          ),
          const SizedBox(height: Space.row),
          Text(body, style: Face.body),
        ],
      );
}

class _Precession extends StatelessWidget {
  const _Precession();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Why they do not match', style: Face.title),
          const SizedBox(height: Space.row),
          const Text(
            'The twelve slices were named when they lined up with the constellations behind '
            'them, roughly two thousand years ago. Since then the Earth\'s axis has swung slowly '
            'round, dragging the spring equinox - and therefore the whole set of slices - about '
            'thirty degrees westward against the stars.',
            style: Face.body,
          ),
          const SizedBox(height: Space.row),
          const Text(
            'That drift is one degree every seventy-two years, and it is why most people\'s sign '
            'is one constellation off from where the Sun was on the day they were born. Nothing '
            'has gone wrong: the sign is a calendar, the constellation is a place.',
            style: Face.body,
          ),
          const SizedBox(height: Space.row),
          Text(
            'This app corrects for that drift everywhere it matters - the same correction is what '
            'puts each of its 9,096 stars in the right constellation.',
            style: Face.quiet,
          ),
        ],
      );
}
