/// The hero: the real sky, plotted against the two axes that decide where you look.
///
/// Across is compass bearing, north through east to north again. Up is height above the horizon,
/// from the horizon line to straight overhead. Every dot sits at a body's actual measured
/// altitude and azimuth, so the plot is not an illustration of the sky - it is the sky, flattened
/// the way a chart flattens a coastline.
///
/// Why this and not a dome you pan around. A dome looks impressive and answers the wrong
/// question: it shows you a picture of the sky you are already standing under. Standing outside,
/// the only thing you need is which way to turn and how far up to look, and those are exactly the
/// two numbers this plot is made of. Below-horizon bodies are drawn below the line in cool grey
/// rather than hidden, because "Saturn is up but behind you" and "Saturn has set" are different
/// answers and an app that shows neither is useless.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sky/sky_now.dart';
import 'theme.dart';

class SkyPlot extends StatelessWidget {
  const SkyPlot({
    required this.sky,
    required this.reveal,
    super.key,
  });

  final SkyNow sky;

  /// 0 to 1. Drives the single entrance: bodies appear from the horizon upward, lowest first,
  /// which is the order they would rise in. One sequence on load, nothing else moves.
  final double reveal;

  @override
  Widget build(BuildContext context) {
    final bodies = <SkyBody>[
      ...sky.planets,
      sky.moon,
      if (sky.sun.isAboveHorizon) sky.sun,
      ...sky.stars.take(60),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _SkyPlotPainter(bodies: bodies, reveal: reveal),
      ),
    );
  }
}

class _SkyPlotPainter extends CustomPainter {
  _SkyPlotPainter({required this.bodies, required this.reveal});

  final List<SkyBody> bodies;
  final double reveal;

  /// The horizon sits two thirds down: there is more to say about what is up than what is down,
  /// but what is down still gets room.
  static const double _horizonFraction = 0.72;

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * _horizonFraction;

    canvas.drawRect(
      Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY),
      Paint()..color = Night.belowHorizon,
    );

    final hairline = Paint()
      ..color = Night.hairline
      ..strokeWidth = 1;

    // Altitude grid at 30 and 60 degrees. Two lines, not five: they are there to make "about
    // halfway up" readable, not to be read off precisely.
    for (final altitude in [30.0, 60.0]) {
      final y = horizonY - (altitude / 90.0) * horizonY;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hairline);
      _label(canvas, '$altitude°'.replaceAll('.0', ''), Offset(4, y - 16), Face.quiet);
    }

    // The horizon itself, drawn heavier than the grid because it means more.
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(size.width, horizonY),
      Paint()
        ..color = Night.slate
        ..strokeWidth = 1.4,
    );

    // Compass bearings along the horizon.
    // A plain list rather than a map: a const map cannot be keyed by doubles, and the pairing
    // of bearing to letter is clearer written out anyway.
    for (final (bearing, letter) in const [(0.0, 'N'), (90.0, 'E'), (180.0, 'S'), (270.0, 'W')]) {
      final x = (bearing / 360.0) * size.width;
      canvas.drawLine(Offset(x, horizonY - 5), Offset(x, horizonY + 5), hairline);
      _label(canvas, letter, Offset(x + 4, horizonY + 6), Face.quiet);
    }

    // Faintest first, so the bright things land on top of the faint ones.
    final ordered = [...bodies]..sort((a, b) => b.magnitude.compareTo(a.magnitude));
    for (final body in ordered) {
      _paintBody(canvas, size, horizonY, body);
    }
  }

  void _paintBody(Canvas canvas, Size size, double horizonY, SkyBody body) {
    final altitude = body.horizontal.altitudeDegrees;
    final x = (body.horizontal.azimuthDegrees / 360.0) * size.width;
    final y = altitude >= 0
        ? horizonY - (altitude.clamp(0, 90) / 90.0) * horizonY
        : horizonY +
            (-altitude.clamp(-90, 0) / 90.0) * (size.height - horizonY);

    // The entrance: a body appears once `reveal` passes its own height. Lowest first.
    final threshold = altitude >= 0 ? (altitude.clamp(0, 90) / 90.0) * 0.8 : 0.0;
    if (reveal < threshold) return;
    final opacity = ((reveal - threshold) / 0.2).clamp(0.0, 1.0);

    final isUp = altitude > 0;
    final radius = _radiusFor(body);
    final colour = (isUp ? Night.amber : Night.slate).withValues(
      alpha: (isUp ? 1.0 : 0.55) * opacity,
    );

    if (isUp && body.kind != SkyBodyKind.star) {
      // A soft halo on the bright, nearby things only. On stars it would turn the plot into mush.
      canvas.drawCircle(
        Offset(x, y),
        radius * 3.2,
        Paint()..color = Night.amber.withValues(alpha: 0.10 * opacity),
      );
    }
    canvas.drawCircle(Offset(x, y), radius, Paint()..color = colour);

    if (body.kind != SkyBodyKind.star) {
      _label(
        canvas,
        body.name,
        Offset(x + radius + 6, y - 9),
        (isUp ? Face.body : Face.quiet).copyWith(
          fontSize: 13,
          color: (isUp ? Night.parchment : Night.slate).withValues(alpha: opacity),
        ),
      );
    }
  }

  /// Dot size from magnitude, the way a star chart does it: brighter is bigger, on a scale that
  /// keeps a magnitude 4 star visible without letting Venus swallow the plot.
  double _radiusFor(SkyBody body) {
    if (body.kind == SkyBodyKind.sun) return 9;
    if (body.kind == SkyBodyKind.moon) return 8;
    final size = 4.2 - body.magnitude * 0.7;
    return size.clamp(1.1, 6.5);
  }

  void _label(Canvas canvas, String text, Offset at, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SkyPlotPainter old) =>
      old.reveal != reveal || old.bodies != bodies;
}

/// Degrees as people read them off a plot: whole degrees, with the sign kept for below-horizon.
String formatAltitude(double degrees) =>
    '${degrees >= 0 ? '' : '−'}${degrees.abs().round()}°';

/// A compass bearing and the direction word together, which is how you would say it out loud.
String formatBearing(double azimuthDegrees) {
  final rounded = (azimuthDegrees % 360).round() % 360;
  const names = ['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west'];
  final index = (((azimuthDegrees % 360) + 22.5) / 45).floor() % 8;
  return '$rounded° ${names[index]}';
}

/// Light travel time, said the way it is worth saying.
String formatLightTime(double minutes) {
  if (!minutes.isFinite) return 'years';
  if (minutes < 1) return '${(minutes * 60).round()} seconds ago';
  if (minutes < 90) return '${minutes.round()} minutes ago';
  final hours = minutes / 60;
  return '${hours.toStringAsFixed(hours < 10 ? 1 : 0)} hours ago';
}

/// A lux value at the scale starlight actually arrives in.
String formatLux(double lux) {
  if (lux >= 0.01) return '${lux.toStringAsFixed(3)} lux';
  final exponent = (math.log(lux) / math.ln10).floor();
  final mantissa = lux / math.pow(10, exponent);
  return '${mantissa.toStringAsFixed(1)}e$exponent lux';
}
