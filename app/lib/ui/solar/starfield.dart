/// The real stars, behind the planets.
///
/// Not a noise function and not a sprinkle of random dots: these are the stars of the Yale Bright
/// Star Catalogue at their catalogued right ascension and declination, sized by their measured
/// magnitude and coloured by their measured B-V index. Fly to Neptune and the constellations
/// behind it are the ones that are really behind it.
///
/// 8,404 of the catalogue's 9,096 rows are drawn at the default limit - the rest are fainter than
/// magnitude 6.5, which is past what any eye resolves.
///
/// They are drawn on a sphere far outside the orbits rather than at their true distances. The
/// nearest star is 268,000 au away; at true scale every one of them would be a single pixel in an
/// unchanging place however far the camera travelled, so there would be nothing to gain and a
/// great deal of floating-point precision to lose.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sky/angles.dart';
import '../../sky/catalogue.dart';
import 'camera.dart';

/// A star reduced to what drawing it needs: a direction, a size and a colour.
class StarPoint {
  const StarPoint({required this.direction, required this.radius, required this.color});

  final Vec3 direction;
  final double radius;
  final Color color;
}

/// Turn catalogue rows into drawable points, once.
///
/// `magnitudeLimit` of 6.5 is the naked-eye limit in a dark sky, and takes 8,404 of the
/// catalogue's 9,096 rows. There is no reason to draw fewer: this is space, there is no light
/// pollution, and eight thousand points is nothing to a GPU.
List<StarPoint> starPoints(Catalogue catalogue, {double magnitudeLimit = 6.5}) {
  final points = <StarPoint>[];
  for (final star in catalogue.stars) {
    if (star.magnitude > magnitudeLimit) break; // sorted brightest first
    final ra = star.rightAscensionJ2000 * degToRad;
    final dec = star.declinationJ2000 * degToRad;

    // Equatorial to ecliptic, at the J2000 obliquity, because the orbits are in the ecliptic
    // frame and the stars have to share it or the whole sky is tilted by 23 degrees.
    const obliquity = 23.439291111 * degToRad;
    final x = math.cos(dec) * math.cos(ra);
    final yEq = math.cos(dec) * math.sin(ra);
    final zEq = math.sin(dec);
    final y = yEq * math.cos(obliquity) + zEq * math.sin(obliquity);
    final z = -yEq * math.sin(obliquity) + zEq * math.cos(obliquity);

    points.add(
      StarPoint(
        // The ecliptic frame used by the camera has y as the pole, so the axes are reordered here
        // rather than rotating every frame.
        direction: Vec3(x, z, y),
        radius: _radiusFor(star.magnitude),
        color: _colorFor(star.colourIndex),
      ),
    );
  }
  return points;
}

/// Dot size from magnitude, the way a star chart does it.
double _radiusFor(double magnitude) => (2.6 - magnitude * 0.38).clamp(0.45, 3.2);

/// Colour from the B-V index, which is a real temperature measurement.
///
/// B-V runs from about -0.3 for the hottest blue stars through 0.65 for the Sun to above 1.5 for
/// cool red ones. Rigel really is blue and Betelgeuse really is red, and this is why.
Color _colorFor(double? bv) {
  if (bv == null) return const Color(0xFFFFF4E6);
  final t = ((bv + 0.35) / 1.95).clamp(0.0, 1.0);
  // Blue-white -> white -> amber -> red, interpolated in two legs so the white in the middle does
  // not turn grey.
  if (t < 0.5) {
    final k = t / 0.5;
    return Color.lerp(const Color(0xFFBBD4FF), const Color(0xFFFFF8F0), k)!;
  }
  final k = (t - 0.5) / 0.5;
  return Color.lerp(const Color(0xFFFFF8F0), const Color(0xFFFFB38A), k)!;
}

/// Paints the starfield for one camera.
class StarfieldPainter extends CustomPainter {
  StarfieldPainter({required this.stars, required this.camera});

  final List<StarPoint> stars;
  final SolarCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final star in stars) {
      final projected = camera.projectDirection(
        star.direction,
        screenWidth: size.width,
        screenHeight: size.height,
      );
      if (!projected.isVisible) continue;
      // Off-screen stars are skipped rather than drawn and clipped: at 9,096 points the saving is
      // most of the work on a zoomed-in view.
      if (projected.screenX < -4 ||
          projected.screenY < -4 ||
          projected.screenX > size.width + 4 ||
          projected.screenY > size.height + 4) {
        continue;
      }
      paint.color = star.color;
      canvas.drawCircle(
        Offset(projected.screenX, projected.screenY),
        star.radius,
        paint,
      );
      // The brightest few get a soft bloom, which is what a bright star does to a camera lens and
      // to an eye. Only the brightest: on all of them it would be a white fog.
      if (star.radius > 2.2) {
        canvas.drawCircle(
          Offset(projected.screenX, projected.screenY),
          star.radius * 3.0,
          Paint()..color = star.color.withValues(alpha: 0.13),
        );
      }
    }
  }

  @override
  bool shouldRepaint(StarfieldPainter old) => true;
}
