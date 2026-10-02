/// The energy screen: which planet is actually delivering the most light to you, right now.
///
/// This is the screen that answers "does Jupiter have more energy than Mars" with a measurement
/// instead of a claim. The quantity is illuminance - light power weighted by the sensitivity of
/// the human eye - which is the correct physical answer to "how much of this can a person
/// receive". It is computed from each planet's apparent magnitude and arrives in lux.
///
/// The ranking changes from month to month as the planets move, and tonight there is a real
/// winner. That is the interesting part, and it needs no astrology to be interesting.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sky/brightness.dart';
import '../sky/sky_now.dart';
import 'sky_plot.dart';
import 'theme.dart';

class EnergyPage extends StatelessWidget {
  const EnergyPage({required this.sky, super.key});

  final SkyNow sky;

  @override
  Widget build(BuildContext context) {
    final up = sky.planetsUp.toList();
    final down = sky.planets.where((p) => !p.isAboveHorizon).toList();
    final winner = up.isEmpty ? null : up.first;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      children: [
        const SizedBox(height: Space.section),
        Text(
          winner == null
              ? 'No planet is above your horizon.'
              : '${winner.name} is winning tonight.',
          style: Face.display,
        ),
        const SizedBox(height: Space.row),
        Text(
          winner == null
              ? 'None of their light is reaching you from where you are standing. The ranking '
                  'below is what each one would deliver if it were up.'
              : 'Of everything in the solar system above your horizon, ${winner.name} is putting '
                  'the most light on you - ${formatLux(winner.illuminance)}.',
          style: Face.body,
        ),
        const SizedBox(height: Space.section),
        for (final planet in up) _EnergyRow(body: planet, isUp: true),
        if (down.isNotEmpty) ...[
          const SizedBox(height: Space.block),
          Text(
            'Below the horizon - none of this reaches you',
            style: Face.quiet.copyWith(color: Night.slate),
          ),
          const SizedBox(height: Space.block),
          for (final planet in down) _EnergyRow(body: planet, isUp: false),
        ],
        const SizedBox(height: Space.section),
        const _ScaleNote(),
        const SizedBox(height: Space.section),
        const _HonestNote(),
        const SizedBox(height: Space.section),
      ],
    );
  }
}

class _EnergyRow extends StatelessWidget {
  const _EnergyRow({required this.body, required this.isUp});

  final SkyBody body;
  final bool isUp;

  @override
  Widget build(BuildContext context) {
    final colour = isUp ? Night.parchment : Night.slate;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.block),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(body.name, style: Face.title.copyWith(color: colour)),
              ),
              Text(
                formatLux(body.illuminance),
                style: Face.value.copyWith(color: isUp ? Night.amber : Night.slate),
              ),
            ],
          ),
          const SizedBox(height: Space.tight),
          // A bar, because the numbers span six orders of magnitude and a column of exponents
          // tells a reader nothing at a glance. Logarithmic, and labelled as such.
          _LogBar(lux: body.illuminance, isUp: isUp),
          const SizedBox(height: Space.tight),
          Text(
            '${(ReferenceIlluminance.fullMoonLux / body.illuminance).round()} times fainter '
            'than a full Moon. This light left '
            '${formatLightTime(body.lightTravelMinutes)}.',
            style: Face.quiet,
          ),
        ],
      ),
    );
  }
}

class _LogBar extends StatelessWidget {
  const _LogBar({required this.lux, required this.isUp});

  final double lux;
  final bool isUp;

  @override
  Widget build(BuildContext context) {
    // The scale runs from 1e-10 lux - fainter than anything here - up to the full Moon's 0.25,
    // whose base-10 logarithm is -0.6. Logarithmic because the values span six orders of
    // magnitude: on a linear bar every planet would be an invisible sliver against Venus.
    const floor = -10.0;
    const ceiling = -0.6;
    final exponent =
        lux <= 0 ? floor : (math.log(lux) / math.ln10).clamp(floor, ceiling);
    final fraction = ((exponent - floor) / (ceiling - floor)).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Container(height: 3, color: Night.hairline),
          Container(
            height: 3,
            width: constraints.maxWidth * fraction,
            color: isUp ? Night.amber : Night.slate,
          ),
        ],
      ),
    );
  }
}

class _ScaleNote extends StatelessWidget {
  const _ScaleNote();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('For scale', style: Face.title),
          const SizedBox(height: Space.row),
          Text(
            'Direct sunlight is about ${ReferenceIlluminance.sunlightLux.round()} lux. '
            'A full Moon overhead is about ${ReferenceIlluminance.fullMoonLux} lux. '
            'A clear, moonless night sky is about ${ReferenceIlluminance.starlightLux} lux. '
            'Every planet above sits far below all three.',
            style: Face.body,
          ),
        ],
      );
}

class _HonestNote extends StatelessWidget {
  const _HonestNote();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What this is, and is not', style: Face.title),
          const SizedBox(height: Space.row),
          const Text(
            'This is light, measured. Each figure comes from the planet\'s apparent brightness '
            'and its real distance, which the app computes from NASA/JPL orbital elements.',
            style: Face.body,
          ),
          const SizedBox(height: Space.row),
          const Text(
            'It is not an influence. Nothing a planet does reaches a human body in any way that '
            'has been measured - the light above is millions of times weaker than moonlight, and '
            'a planet\'s gravitational pull on you is smaller than that of the person standing '
            'next to you. The numbers are here because they are true and the ranking really does '
            'change, not because they mean anything about your week.',
            style: Face.body,
          ),
          const SizedBox(height: Space.row),
          Text(
            'Mercury\'s brightness is the app\'s weakest figure: its phase model is off by up to '
            '0.7 magnitudes against JPL, which is a factor of about two in the lux above. Every '
            'other planet is within 0.3 magnitudes.',
            style: Face.quiet,
          ),
        ],
      );
}
