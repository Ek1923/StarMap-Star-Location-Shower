# StarMap — the app

The Flutter app. The project README at [`../README.md`](../README.md) has the measured accuracy
figures, the data sources and how the whole thing fits together; this file is only what you need
with a terminal open in this directory.

## Run it

The star catalogue is built by the Python pipeline and is not committed, so build it first:

```bash
py -3.12 ../data/sources.py
py -3.12 ../data/build_catalogue.py
```

Then:

```bash
flutter pub get
flutter run -d chrome     # or an attached phone
flutter test              # 20 tests; the accuracy ones print their error tables
flutter analyze
```

If the catalogue is missing the app does not fail silently - it shows a screen naming the two
commands above.

## What is where

```
lib/sky/   the astronomy. Pure Dart: no widgets, no I/O, no network.
lib/ui/    four screens and one theme. No astronomy.
test/      the engine measured against NASA, and every screen rendered with real data
test/fixtures/horizons.json   NASA/JPL reference positions, committed so tests need no network
assets/    the built catalogue (gitignored) and the Spectral typeface
```

The line between `sky/` and `ui/` is the one worth keeping: `computeSkyNow` is called once and all
four screens read the same result, so no two screens can disagree about where a planet is.

## Toolchain

Built and tested with **Flutter 3.47.6 / Dart 3.13.5**.

- **Android**: SDK with `compileSdk 36`, plus **JDK 17**. Flutter's Gradle plugin does not accept
  JDK 25. The geolocator plugin also pulls in NDK 28.2.13676358.
- **iOS**: needs a Mac with Xcode. The code and `Info.plist` are ready, but it cannot be built or
  tested on Windows.
- **Web**: works with no extra setup, and is the quickest way to see the app.

## Permissions

Two, and no more.

**Coarse location.** A kilometre of position error moves every figure the app shows by well under
an arcminute, so fine location would be asking for more than the app can use. Declining it is
handled rather than fatal: the app says what happened and falls back to a place you pick from a
list.

**Internet.** For exactly one host, `ssd.jpl.nasa.gov`, to replace the app's own planet positions
with NASA's when there is a connection. The request carries a body code and a timestamp. It does
NOT carry your coordinates - the app asks for geocentric positions and applies the observer
correction here, which `test/online_path_test.dart` measures as agreeing with NASA's own
topocentric figures to within 0.44 arcseconds. Blocking this traffic entirely leaves the app fully
working on its computed positions, and the Overhead screen says which source it used.
