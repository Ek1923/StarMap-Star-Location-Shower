/// Getting a latitude and longitude, and coping when that fails.
///
/// The app is "what is above YOU", so a position is not optional - but a permission prompt is
/// something people say no to, and a GPS fix is something that does not arrive indoors. Both of
/// those are normal, neither is an error, and the app stays usable in both cases: it falls back
/// to a place you choose from a list and says plainly which position it is using.
///
/// Nothing is sent anywhere. The coordinates are used on the device to compute angles and are
/// never stored or transmitted - there is no network code in this app at all.
library;

import 'package:geolocator/geolocator.dart';

import '../sky/observer.dart';

/// Where the position came from, so the UI can be honest about it.
enum PositionSource {
  /// The device's own location.
  device,

  /// A city the viewer picked, because the device would not say.
  chosen,
}

class LocatedObserver {
  const LocatedObserver({
    required this.observer,
    required this.label,
    required this.source,
    this.note,
  });

  final Observer observer;

  /// What to call this place on screen.
  final String label;

  final PositionSource source;

  /// Why the fallback was used, when it was. Shown, not swallowed.
  final String? note;
}

/// A short list of places to fall back to, spread wide enough that the app is demonstrably not
/// hard-coded to one hemisphere.
const List<LocatedObserver> fallbackPlaces = [
  LocatedObserver(
    observer: Observer(latitudeDegrees: 52.3676, longitudeEastDegrees: 4.9041),
    label: 'Amsterdam',
    source: PositionSource.chosen,
  ),
  LocatedObserver(
    observer: Observer(latitudeDegrees: 41.0082, longitudeEastDegrees: 28.9784),
    label: 'Istanbul',
    source: PositionSource.chosen,
  ),
  LocatedObserver(
    observer: Observer(latitudeDegrees: 40.7128, longitudeEastDegrees: -74.0060),
    label: 'New York',
    source: PositionSource.chosen,
  ),
  LocatedObserver(
    observer: Observer(latitudeDegrees: -33.8688, longitudeEastDegrees: 151.2093),
    label: 'Sydney',
    source: PositionSource.chosen,
  ),
  LocatedObserver(
    observer: Observer(
      latitudeDegrees: -0.1807,
      longitudeEastDegrees: -78.4678,
      altitudeMetres: 2850,
    ),
    label: 'Quito',
    source: PositionSource.chosen,
  ),
];

/// Ask the device where it is. Returns null when it will not say, with the reason in `lastNote`.
class LocationSource {
  String? lastNote;

  Future<LocatedObserver?> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        lastNote = 'Location is switched off on this device.';
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        lastNote = 'Location permission was declined.';
        return null;
      }
      if (permission == LocationPermission.deniedForever) {
        lastNote = 'Location permission is blocked in system settings.';
        return null;
      }

      // Low accuracy on purpose. A kilometre of error moves every angle in this app by well under
      // an arcminute, so asking for a precise fix would cost battery and a longer wait for
      // nothing a viewer could see.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );

      lastNote = null;
      return LocatedObserver(
        observer: Observer(
          latitudeDegrees: position.latitude,
          longitudeEastDegrees: position.longitude,
          altitudeMetres: position.altitude,
        ),
        label: _describe(position.latitude, position.longitude),
        source: PositionSource.device,
      );
    } on Object catch (error) {
      // Anything at all: no fix in time, no platform support, a plugin that is not registered on
      // this platform. The app does not care which - it needs a position and there is a fallback.
      lastNote = 'Could not get a location fix ($error).';
      return null;
    }
  }

  /// Coordinates, written the way a chart writes them.
  static String _describe(double latitude, double longitude) {
    final ns = latitude >= 0 ? 'N' : 'S';
    final ew = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(2)}° $ns, '
        '${longitude.abs().toStringAsFixed(2)}° $ew';
  }
}
