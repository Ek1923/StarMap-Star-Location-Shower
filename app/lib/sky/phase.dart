/// The Moon's phase, and when it is next full or new.
///
/// The phase is not looked up in a table of dates. It is computed from the real angle between the
/// Sun and the Moon as seen from the Earth, which means it is correct for any moment, anywhere,
/// and it cannot drift out of date.
///
/// The full and new moon times are found by searching that same angle for the moment it crosses
/// 180 or 0 degrees - a bracket and then a bisection. Slower than an almanac formula and exactly
/// as accurate as the position series underneath it, which measures 1.9 arcseconds against NASA.
/// The Moon moves about half an arcsecond per second of time, so a one-arcsecond position is a
/// two-second answer, which is finer than anyone needs for "Saturday night".
library;

import 'dart:math' as math;

import 'angles.dart';
import 'moon.dart';
import 'sun.dart';

/// Where the Moon is in its cycle.
class MoonPhase {
  const MoonPhase({
    required this.elongationDegrees,
    required this.illuminatedFraction,
    required this.isWaxing,
    required this.ageDays,
  });

  /// The Sun-Earth-Moon angle, 0 at new moon, 180 at full.
  final double elongationDegrees;

  /// Lit fraction of the disc, 0 to 1.
  final double illuminatedFraction;

  /// Growing towards full, rather than shrinking towards new.
  final bool isWaxing;

  /// Days since the last new moon.
  final double ageDays;

  /// The name people use.
  ///
  /// Classified on the elongation alone, because elongation runs 0 to 360 across the whole cycle
  /// and so already says which way the Moon is going. The earlier version split on a separate
  /// waxing flag and asked whether the elongation was below 7 degrees - which is false at a new
  /// moon, where it comes out at 359.99 and wraps. That called every new moon a full moon, and
  /// `test/phase_test.dart` caught it.
  ///
  /// The named instants get a window rather than an instant on purpose: "first quarter" is a
  /// night, not a timestamp.
  String get name {
    if (elongationDegrees < 7 || elongationDegrees > 353) return 'New moon';
    if (elongationDegrees > 173 && elongationDegrees < 187) return 'Full moon';
    if (elongationDegrees > 83 && elongationDegrees < 97) return 'First quarter';
    if (elongationDegrees > 263 && elongationDegrees < 277) return 'Last quarter';
    if (elongationDegrees < 90) return 'Waxing crescent';
    if (elongationDegrees < 180) return 'Waxing gibbous';
    if (elongationDegrees < 270) return 'Waning gibbous';
    return 'Waning crescent';
  }
}

/// The mean synodic month in days - new moon to new moon on average. Used only to size the
/// search window and to estimate the Moon's age, never to predict a phase.
const double meanSynodicMonthDays = 29.530588;

/// The Moon's phase at `when`.
MoonPhase moonPhase(DateTime when) {
  final elongation = _elongationDegrees(when);
  // Elongation below 180 is the half of the cycle between new and full, so it IS waxing. No
  // second position evaluation needed, and no ambiguity at the wrap.
  final waxing = elongation < 180;

  // The illuminated fraction follows from the phase angle at the Moon, which for the Earth-Moon
  // -Sun triangle is 180 degrees minus the elongation to within a fraction of a degree.
  final phaseAngle = (180.0 - elongation) * degToRad;
  final illuminated = (1 + math.cos(phaseAngle)) / 2;

  return MoonPhase(
    elongationDegrees: elongation,
    illuminatedFraction: illuminated.clamp(0.0, 1.0),
    isWaxing: waxing,
    // Elongation runs 0 to 360 from one new moon to the next, so it IS the fraction of the
    // cycle elapsed. Mean month rather than this month's, which is why it is called an age and
    // not a date.
    ageDays: elongation / 360.0 * meanSynodicMonthDays,
  );
}

/// The next full moon at or after `from`.
DateTime nextFullMoon(DateTime from) => _nextCrossing(from, 180.0);

/// The next new moon at or after `from`.
DateTime nextNewMoon(DateTime from) => _nextCrossing(from, 0.0);

/// The next time the Sun-Moon elongation passes `targetDegrees`.
///
/// Walks forward in six-hour steps until the signed distance to the target changes sign, then
/// bisects. Six hours is small enough that the elongation - which moves about 12 degrees a day -
/// cannot step past the target and back inside one stride.
DateTime _nextCrossing(DateTime from, double targetDegrees) {
  const stepHours = 6;
  var previous = from;
  var previousDifference =
      _signedDifference(_elongationDegrees(previous), targetDegrees);

  // A synodic month plus a margin: the crossing has to be in there.
  final limit = from.add(
    Duration(hours: ((meanSynodicMonthDays + 2) * 24).round()),
  );

  var current = from.add(const Duration(hours: stepHours));
  while (current.isBefore(limit)) {
    final difference =
        _signedDifference(_elongationDegrees(current), targetDegrees);
    // A sign change from negative to positive is the crossing we want: approaching the target
    // from behind. The opposite sign change is the Moon moving away from it.
    if (previousDifference < 0 && difference >= 0) {
      return _bisect(previous, current, targetDegrees);
    }
    previous = current;
    previousDifference = difference;
    current = current.add(const Duration(hours: stepHours));
  }

  throw StateError(
    'no elongation crossing of $targetDegrees found within a synodic month of '
    '${from.toUtc().toIso8601String()} - the search step or the Moon series is wrong',
  );
}

DateTime _bisect(DateTime low, DateTime high, double targetDegrees) {
  var lower = low;
  var upper = high;
  // Thirty halvings of six hours reaches well under a millisecond; twenty-five is already under
  // a second, and the loop stops early when the window is a second wide.
  for (var i = 0; i < 30; i++) {
    if (upper.difference(lower).inMilliseconds <= 1000) break;
    final middle = lower.add(
      Duration(microseconds: upper.difference(lower).inMicroseconds ~/ 2),
    );
    final difference =
        _signedDifference(_elongationDegrees(middle), targetDegrees);
    if (difference < 0) {
      lower = middle;
    } else {
      upper = middle;
    }
  }
  return lower.add(
    Duration(microseconds: upper.difference(lower).inMicroseconds ~/ 2),
  );
}

/// The Sun-Moon difference in ecliptic longitude, 0 to 360.
double _elongationDegrees(DateTime when) => normalizeDegrees(
      moonEclipticLongitudeDegrees(when) - sunEclipticLongitudeDegrees(when),
    );

/// `a - b`, wrapped to -180..180, so a crossing of 0 or 360 is not mistaken for a jump.
double _signedDifference(double a, double b) => normalizeDegreesSigned(a - b);
