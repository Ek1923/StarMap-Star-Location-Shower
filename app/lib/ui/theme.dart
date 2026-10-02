/// The app's visual vocabulary, in one place.
///
/// The design idea, so that later changes have something to argue with:
///
/// This is an ALMANAC, not a planetarium. Every other sky app draws a glowing dome and asks you
/// to pan around it; this one reports measured numbers from a named source, and its hero is a
/// plot of the real sky against two real axes - compass bearing across, height above the horizon
/// up. The horizon is a line in the layout because the horizon is the fact that decides whether
/// you can see something at all.
///
/// The palette is chosen for the condition the app is used in: outdoors, at night, by eyes that
/// have begun to dark-adapt. The ground is a deep blue-black rather than pure black because real
/// night sky is blue-black and because pure black with bright text is harsh when your pupils are
/// wide. Warm amber carries everything that is currently above the horizon - warm light preserves
/// night vision far better than blue-white, which is why observatories work in warm light - and a
/// cool slate carries everything below it. Colour therefore means something here: warm is
/// visible now, cool is not.
library;

import 'package:flutter/material.dart';

/// Colours, each with the job it does. Nothing here is decorative.
///
/// Named `Night` rather than `Ink` because Flutter already exports an `Ink` widget, and two
/// things called the same name in the same file is a compile error waiting to happen.
abstract final class Night {
  /// The ground the whole app sits on. Deep blue-black, the colour of a real moonless
  /// sky away from town - not pure black, which is harsh on eyes that have started to
  /// dark-adapt and is a tell of a palette nobody chose.
  static const Color ground = Color(0xFF05060A);

  /// Slightly lifted, for the band below the horizon line. It makes the horizon readable without
  /// drawing a heavy rule across the screen.
  static const Color belowHorizon = Color(0xFF0D1220);

  /// Primary text. A warm off-white, like ink on an old chart, and gentler than pure white on
  /// dark-adapted eyes.
  static const Color parchment = Color(0xFFE8E4DA);

  /// Anything currently above the horizon: live values, the bodies on the plot, the figure being
  /// reported. Warm, because warm light is what you use at a telescope.
  static const Color amber = Color(0xFFE0A33E);

  /// Below the horizon, or secondary. Cool and quiet - the app still shows these, it just does
  /// not pretend you can see them.
  static const Color slate = Color(0xFF5A6273);

  /// Separators, axis lines, tick marks.
  static const Color hairline = Color(0xFF1B2230);
}

/// One family, Spectral, doing all the work through size and weight.
///
/// Named `Face` - as in typeface - rather than `Type`, which would shadow dart:core's `Type`.
///
/// A serif, which is unusual for an app and deliberate here: this thing reports measurements from
/// a catalogue, and a book face says that more honestly than the interface sans every app ships
/// with. Spectral was designed for screens and has lining figures that line up in a column, which
/// matters when the content is mostly numbers.
abstract final class Face {
  static const String family = 'Spectral';

  /// The one big number or name on a screen.
  static const TextStyle display = TextStyle(
    fontFamily: family,
    fontSize: 40,
    fontWeight: FontWeight.w300,
    height: 1.1,
    color: Night.parchment,
  );

  /// Screen titles and the name of the thing being reported.
  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: Night.parchment,
  );

  /// Running text. Kept under about 70 characters a line by the layout.
  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: Night.parchment,
  );

  /// A measured value in a row.
  static const TextStyle value = TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: Night.amber,
  );

  /// Supporting detail: units, provenance, the honest caveat.
  static const TextStyle quiet = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w300,
    height: 1.5,
    color: Night.slate,
  );
}

/// Spacing, on a 4-point rhythm.
abstract final class Space {
  static const double tight = 4;
  static const double row = 8;
  static const double block = 16;
  static const double section = 32;
  static const double page = 20;
}

ThemeData starMapTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Night.ground,
    fontFamily: Face.family,
    colorScheme: const ColorScheme.dark(
      surface: Night.ground,
      primary: Night.amber,
      onPrimary: Night.ground,
      secondary: Night.slate,
      onSurface: Night.parchment,
    ),
    textTheme: const TextTheme(
      displayLarge: Face.display,
      titleLarge: Face.title,
      bodyMedium: Face.body,
      labelSmall: Face.quiet,
    ),
    dividerColor: Night.hairline,
    splashFactory: NoSplash.splashFactory,
  );
}
