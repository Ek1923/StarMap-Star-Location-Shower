import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starmap/sky/catalogue.dart';
import 'package:starmap/sky/observer.dart';
import 'package:starmap/sky/sky_now.dart';
import 'package:starmap/ui/energy_page.dart';
import 'package:starmap/ui/location_source.dart';
import 'package:starmap/ui/moon_page.dart';
import 'package:starmap/ui/overhead_page.dart';
import 'package:starmap/ui/sign_page.dart';
import 'package:starmap/ui/theme.dart';

/// Does every screen actually render, with the real catalogue and real numbers behind it?
///
/// Not a smoke test for its own sake. These screens divide by distances, take logarithms of
/// illuminances and build a path from a phase fraction, and every one of those has an input that
/// breaks it: an infinite distance for a star, a vanishing illuminance, a new moon with nothing
/// lit, a southern latitude. Each case below is one of those, chosen on purpose.
void main() {
  late Catalogue catalogue;

  setUpAll(() {
    // Read straight off disk rather than through a mocked asset bundle: the asset is written by
    // the Python pipeline, and a mock would stop this catching a format change.
    catalogue = Catalogue.parse(File('assets/stars.json').readAsStringSync());
  });

  SkyNow skyAt(DateTime when, {Observer? observer}) => computeSkyNow(
        when: when,
        observer: observer ??
            const Observer(latitudeDegrees: 52.3676, longitudeEastDegrees: 4.9041),
        catalogue: catalogue,
      );

  Widget wrap(Widget child) => MaterialApp(
        theme: starMapTheme(),
        home: Scaffold(body: child),
      );

  test('the catalogue the app ships is the one the build wrote', () {
    expect(catalogue.stars, hasLength(9096));
    expect(catalogue.constellations, hasLength(88));
    expect(catalogue.boundaries, hasLength(357));
    // Brightest first is relied on by every screen that takes the first few.
    expect(catalogue.stars.first.properName, 'Sirius');
    expect(catalogue.stars.first.constellation, 'CMa');
  });

  test('a star gets its real name, never an invented one', () {
    final named = catalogue.stars.firstWhere((s) => s.properName != null);
    final unnamed = catalogue.stars.firstWhere((s) => s.properName == null);
    expect(catalogue.nameOf(named), named.properName);
    // An unnamed star falls back to its catalogue number, not to a popular nickname.
    expect(catalogue.nameOf(unnamed), startsWith('HR ${unnamed.hr}'));
  });

  testWidgets('Overhead renders at night', (tester) async {
    final sky = skyAt(DateTime.utc(2026, 10, 3, 22));
    await tester.pumpWidget(
      wrap(
        OverheadPage(
          sky: sky,
          place: fallbackPlaces.first,
          onChoosePlace: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Overhead renders in daylight, and says so', (tester) async {
    // Midday in Amsterdam: the Sun is up, nothing else can be seen, and the screen has to say
    // that rather than listing planets nobody can look at.
    final sky = skyAt(DateTime.utc(2026, 7, 1, 11));
    expect(sky.isDark, isFalse);
    await tester.pumpWidget(
      wrap(
        OverheadPage(sky: sky, place: fallbackPlaces.first, onChoosePlace: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Sun is up'), findsOneWidget);
  });

  testWidgets('Energy renders, brightest planet first', (tester) async {
    final sky = skyAt(DateTime.utc(2026, 10, 3, 22));
    await tester.pumpWidget(wrap(EnergyPage(sky: sky)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final planet in sky.planets.skip(1)) {
      expect(sky.planets.first.magnitude, lessThanOrEqualTo(planet.magnitude));
    }
  });

  testWidgets('Your sign renders, and labels both answers', (tester) async {
    final sky = skyAt(DateTime.utc(2026, 10, 3, 22));
    await tester.pumpWidget(wrap(SignPage(sky: sky)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Which sign it is depends on the date, so the assertion is on the labels: the screen must
    // always say which of the two answers is tradition and which is measured.
    expect(find.text('tradition'), findsOneWidget);
    expect(find.text('measured'), findsOneWidget);
  });

  testWidgets('Moon renders at a new moon, where nothing is lit', (tester) async {
    // The painter builds a path from the terminator width, which collapses at a new moon. This is
    // the input that would throw if that were handled carelessly.
    final sky = skyAt(DateTime.utc(2026, 10, 3, 22));
    await tester.pumpWidget(wrap(MoonPage(sky: skyAt(sky.nextNew))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('New moon'), findsOneWidget);
  });

  testWidgets('Moon renders at a full moon', (tester) async {
    final sky = skyAt(DateTime.utc(2026, 10, 3, 22));
    await tester.pumpWidget(wrap(MoonPage(sky: skyAt(sky.nextFull))));
    await tester.pumpAndSettle();
    expect(find.text('Full moon'), findsOneWidget);
  });

  testWidgets('the southern hemisphere is not an afterthought', (tester) async {
    // The same instant from opposite hemispheres. A latitude sign error would put the whole sky
    // in the wrong half of the plot, and this is the cheapest way to notice.
    final when = DateTime.utc(2026, 10, 3, 12);
    final north = skyAt(when);
    final south = skyAt(
      when,
      observer: const Observer(latitudeDegrees: -33.8688, longitudeEastDegrees: 151.2093),
    );
    expect(
      north.sun.horizontal.altitudeDegrees,
      isNot(closeTo(south.sun.horizontal.altitudeDegrees, 1)),
    );
    await tester.pumpWidget(
      wrap(OverheadPage(sky: south, place: fallbackPlaces.last, onChoosePlace: (_) {})),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
