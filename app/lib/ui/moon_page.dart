/// The Moon: what shape it is tonight, and when it is next full.
///
/// The disc is drawn from the real illuminated fraction and the real terminator curve, not from a
/// set of eight phase icons. It is the one place in the app where a picture is more useful than a
/// number, because "41% lit and waxing" is a shape, and a shape is what you look up and see.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sky/sky_now.dart';
import 'sky_plot.dart';
import 'theme.dart';

class MoonPage extends StatelessWidget {
  const MoonPage({required this.sky, super.key});

  final SkyNow sky;

  @override
  Widget build(BuildContext context) {
    final phase = sky.moonPhase;
    final percent = (phase.illuminatedFraction * 100);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      children: [
        const SizedBox(height: Space.section),
        Text(phase.name, style: Face.display),
        const SizedBox(height: Space.row),
        Text(
          '${percent.toStringAsFixed(percent < 10 ? 1 : 0)}% lit, '
          '${phase.isWaxing ? 'growing' : 'shrinking'}, '
          '${phase.ageDays.toStringAsFixed(1)} days since the last new moon.',
          style: Face.body,
        ),
        const SizedBox(height: Space.section),
        Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _MoonDisc(
                illuminatedFraction: phase.illuminatedFraction,
                isWaxing: phase.isWaxing,
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.section),
        _Row(
          label: sky.moon.isAboveHorizon ? 'Up now' : 'Below the horizon',
          value: sky.moon.isAboveHorizon
              ? '${formatBearing(sky.moon.horizontal.azimuthDegrees)}, '
                  '${formatAltitude(sky.moon.horizontal.altitudeDegrees)} up'
              : formatAltitude(sky.moon.horizontal.altitudeDegrees),
          dim: !sky.moon.isAboveHorizon,
        ),
        _Row(
          label: 'Distance',
          value: '${(sky.moon.distanceAu * 149597870.7).round()} km',
        ),
        _Row(
          label: 'Apparent width',
          value: '${(sky.moon.angularDiameterArcsec! / 60).toStringAsFixed(1)} arcminutes',
        ),
        const SizedBox(height: Space.section),
        _Row(label: 'Next full moon', value: _when(sky.nextFull, sky.when)),
        _Row(label: 'Next new moon', value: _when(sky.nextNew, sky.when)),
        const SizedBox(height: Space.section),
        const Text('How this is worked out', style: Face.title),
        const SizedBox(height: Space.row),
        const Text(
          'The phase is the real angle between the Sun and the Moon as seen from the Earth, so '
          'it is right for any moment rather than read off a calendar. The full and new moon '
          'times come from searching that same angle for the instant it crosses 180° and 0°.',
          style: Face.body,
        ),
        const SizedBox(height: Space.row),
        Text(
          'The Moon\'s position is measured against NASA/JPL\'s own ephemeris at 1.9 arcseconds, '
          'and the lit percentage to within 0.9 points.',
          style: Face.quiet,
        ),
        const SizedBox(height: Space.section),
      ],
    );
  }

  /// A date people can act on, with how far off it is.
  String _when(DateTime moment, DateTime from) {
    final local = moment.toLocal();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final days = moment.difference(from).inHours / 24;
    final away = days < 1
        ? 'in ${moment.difference(from).inHours} hours'
        : 'in ${days.round()} days';
    return '${local.day} ${months[local.month - 1]}, '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')} ($away)';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.dim = false});

  final String label;
  final String value;
  final bool dim;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.block),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: Face.body)),
            Text(
              value,
              textAlign: TextAlign.right,
              style: Face.value.copyWith(color: dim ? Night.slate : Night.amber),
            ),
          ],
        ),
      );
}

/// The lit part of the Moon, drawn from the real illuminated fraction.
///
/// The terminator - the line between lit and dark - is an ellipse, not a straight edge, and its
/// width is what the illuminated fraction actually means. Drawing it as a straight edge would be
/// wrong on every night except the quarters, which are the only two nights people would notice.
class _MoonDisc extends CustomPainter {
  _MoonDisc({required this.illuminatedFraction, required this.isWaxing});

  final double illuminatedFraction;
  final bool isWaxing;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // The unlit disc stays visible as a faint circle: the Moon does not disappear, it goes dark,
    // and showing the whole outline is what makes a crescent read as a sphere.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = Night.hairline
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = Night.slate.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final lit = illuminatedFraction.clamp(0.0, 1.0);
    if (lit < 0.005) return;

    // The terminator's half-width, as a fraction of the radius. Positive when the lit side is
    // gibbous, negative when it is a crescent.
    final terminator = radius * (1 - 2 * lit).abs();
    final isCrescent = lit < 0.5;

    final path = Path();
    // The outer limb: a half circle on the lit side.
    final start = isWaxing ? -math.pi / 2 : math.pi / 2;
    path.addArc(
      Rect.fromCircle(center: centre, radius: radius),
      start,
      math.pi,
    );
    // The terminator, closing the shape back to the starting point.
    path.arcTo(
      Rect.fromCenter(
        center: centre,
        width: terminator * 2,
        height: radius * 2,
      ),
      math.pi / 2 * (isWaxing ? 1 : -1),
      math.pi * (isCrescent ? -1 : 1) * (isWaxing ? 1 : -1),
      false,
    );
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = Night.parchment
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_MoonDisc old) =>
      old.illuminatedFraction != illuminatedFraction || old.isWaxing != isWaxing;
}
