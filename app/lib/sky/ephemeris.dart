/// Where a position came from, and the shape a reference source hands one over in.
///
/// The app has two ways to know where a planet is, and it never hides which one it used:
///
///   * **Computed on this device** - always available, works with no signal, and wrong by the
///     amounts measured in `test/accuracy_test.dart`: a couple of arcseconds for the Moon, up to
///     five arcminutes for Saturn.
///   * **NASA/JPL Horizons** - the same ephemeris those measurements are taken against, so when
///     it is reachable the residual error is zero by definition.
///
/// The reference is asked for GEOCENTRIC positions, with no observer coordinates in the request,
/// and the observer correction is applied on the device afterwards. That is not an optimisation:
/// it is what keeps the viewer's latitude and longitude off the network entirely. Only a
/// timestamp leaves the phone.
library;

/// A geocentric apparent position, as a reference source states it.
///
/// Only position, distance and brightness. Phase, the next full moon and the zodiac stay computed
/// on the device: each is a search over many instants, and fetching them would turn one request
/// into hundreds for figures that are already accurate to a fraction of a percent.
class GeocentricReading {
  const GeocentricReading({
    required this.body,
    required this.rightAscensionDegrees,
    required this.declinationDegrees,
    required this.distanceAu,
    this.magnitude,
    this.angularDiameterArcsec,
  });

  /// Lower-case body name: `sun`, `moon`, `mercury` ... `neptune`.
  final String body;

  /// Apparent right ascension, equinox of date.
  final double rightAscensionDegrees;

  /// Apparent declination, equinox of date.
  final double declinationDegrees;

  /// Geocentric distance in au.
  final double distanceAu;

  /// Apparent visual magnitude, when the source gives one.
  final double? magnitude;

  final double? angularDiameterArcsec;
}

/// Which source a figure came from.
enum EphemerisSource {
  /// Computed here, from orbital elements and series.
  computedOnDevice,

  /// NASA/JPL Horizons, fetched this session.
  nasaHorizons,
}

/// What the app actually managed to use, so a screen can say so rather than imply it.
class EphemerisProvenance {
  const EphemerisProvenance({
    required this.source,
    required this.bodiesFromReference,
    required this.bodiesTotal,
    this.note,
  });

  final EphemerisSource source;

  /// How many of the nine came from the reference. A partial result is normal - one slow request
  /// out of nine should not throw away the other eight - and the count is shown rather than
  /// rounded up to "online".
  final int bodiesFromReference;

  final int bodiesTotal;

  /// Why the reference was not used, when it was not. Shown, not swallowed.
  final String? note;

  bool get isFullyReferenced => bodiesFromReference == bodiesTotal;

  /// One line for the screen. Says what is true, including when it is half true.
  String get description {
    if (bodiesFromReference == 0) {
      return 'Positions computed on this device';
    }
    if (isFullyReferenced) {
      return 'Positions from NASA/JPL Horizons';
    }
    return '$bodiesFromReference of $bodiesTotal positions from NASA/JPL, '
        'the rest computed here';
  }
}
