/// Your star sign, and the constellation the Sun is actually in.
///
/// These are two different answers to one question, and showing both side by side is the most
/// interesting honest thing this app can do.
///
/// The TROPICAL SIGN is a tradition: the ecliptic cut into twelve equal thirty-degree slices
/// starting at the vernal equinox. It is computed exactly here - from the Sun's real ecliptic
/// longitude, not from a table of date ranges - but what it is computing is a convention, not a
/// position in the sky.
///
/// The CONSTELLATION is where the Sun physically is, by the IAU boundaries. The two disagree by
/// roughly one whole sign, because the slices were named when they lined up and the equinox has
/// since drifted about 30 degrees. That drift is precession, it is 1 degree every 72 years, and
/// it is why someone born "a Leo" very often has the Sun sitting in Cancer.
///
/// The app states which is which. Neither is presented as the other.
library;

import 'constellation_boundaries.dart';
import 'sun.dart';

/// The twelve signs of the tropical zodiac, in order from the vernal equinox.
enum ZodiacSign {
  aries('Aries', 'Ram'),
  taurus('Taurus', 'Bull'),
  gemini('Gemini', 'Twins'),
  cancer('Cancer', 'Crab'),
  leo('Leo', 'Lion'),
  virgo('Virgo', 'Maiden'),
  libra('Libra', 'Scales'),
  scorpio('Scorpio', 'Scorpion'),
  sagittarius('Sagittarius', 'Archer'),
  capricorn('Capricorn', 'Sea Goat'),
  aquarius('Aquarius', 'Water Bearer'),
  pisces('Pisces', 'Fishes');

  const ZodiacSign(this.name, this.symbolMeaning);

  final String name;
  final String symbolMeaning;
}

/// Both answers for one moment, with the gap between them.
class ZodiacReading {
  const ZodiacReading({
    required this.sign,
    required this.solarLongitudeDegrees,
    required this.degreesIntoSign,
    required this.actualConstellation,
  });

  /// The tropical sign. A convention, computed exactly.
  final ZodiacSign sign;

  /// The Sun's apparent ecliptic longitude, degrees from the vernal equinox of date.
  final double solarLongitudeDegrees;

  /// How far into its sign the Sun is, 0 to 30 degrees. Someone born at 29 degrees is a day from
  /// the next sign, which is worth seeing rather than rounding away.
  final double degreesIntoSign;

  /// The IAU constellation the Sun is physically in, or null if the boundary table could not
  /// answer - in which case the app says nothing rather than guessing.
  final String? actualConstellation;

  /// True when tradition and sky disagree, which is most of the time.
  bool get traditionDisagreesWithSky =>
      actualConstellation != null &&
      actualConstellation != _constellationAbbreviationForSign(sign);
}

/// Where the Sun is, read both ways, for `when`.
ZodiacReading zodiacFor(DateTime when, List<BoundaryBand> boundaries) {
  final longitude = sunEclipticLongitudeDegrees(when);
  final index = (longitude / 30.0).floor() % 12;
  final sunJ2000 = sunPositionJ2000(when);

  return ZodiacReading(
    sign: ZodiacSign.values[index],
    solarLongitudeDegrees: longitude,
    degreesIntoSign: longitude - index * 30.0,
    actualConstellation: constellationAt(
      rightAscensionJ2000Degrees: sunJ2000.rightAscensionDegrees,
      declinationJ2000Degrees: sunJ2000.declinationDegrees,
      bands: boundaries,
    ),
  );
}

/// The IAU abbreviation of the constellation a sign is NAMED after.
///
/// Only used to decide whether tradition and sky currently agree. Scorpio is the awkward one: the
/// sign is Scorpio, the constellation is Scorpius (Sco), and they are not the same word.
String _constellationAbbreviationForSign(ZodiacSign sign) => switch (sign) {
      ZodiacSign.aries => 'Ari',
      ZodiacSign.taurus => 'Tau',
      ZodiacSign.gemini => 'Gem',
      ZodiacSign.cancer => 'Cnc',
      ZodiacSign.leo => 'Leo',
      ZodiacSign.virgo => 'Vir',
      ZodiacSign.libra => 'Lib',
      ZodiacSign.scorpio => 'Sco',
      ZodiacSign.sagittarius => 'Sgr',
      ZodiacSign.capricorn => 'Cap',
      ZodiacSign.aquarius => 'Aqr',
      ZodiacSign.pisces => 'Psc',
    };
