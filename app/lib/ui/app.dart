/// The shell: load the catalogue, find out where we are, compute the sky, show four views of it.
///
/// The order matters and is the whole of the online/offline story:
///
///   1. Compute everything on the device. This is instant and always works.
///   2. Show it.
///   3. In the background, ask NASA/JPL for the same positions, one body at a time.
///   4. Each answer that arrives replaces one computed position, and the screen sharpens.
///
/// Nothing waits on the network. With no signal, step 3 quietly produces nothing and the app is
/// exactly what it was before - already accurate to a few arcminutes at worst. With a signal, the
/// positions become NASA's own. Either way the screen says which, and the viewer's coordinates
/// never leave the device in either case.
///
/// One computation feeds all four screens, so nothing on screen can disagree with anything else.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../net/horizons.dart';
import '../sky/catalogue.dart';
import '../sky/ephemeris.dart';
import '../sky/sky_now.dart';
import 'energy_page.dart';
import 'location_source.dart';
import 'moon_page.dart';
import 'overhead_page.dart';
import 'sign_page.dart';
import 'solar/solar_system_view.dart';
import 'theme.dart';

class StarMapApp extends StatelessWidget {
  const StarMapApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'StarMap',
        debugShowCheckedModeBanner: false,
        theme: starMapTheme(),
        home: const _Shell(),
      );
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  final HorizonsClient _horizons = HorizonsClient();

  Catalogue? _catalogue;
  LocatedObserver? _place;
  SkyNow? _sky;
  String? _failure;
  int _tab = 0;

  /// Readings gathered this session, keyed by body. Kept rather than re-fetched on every rebuild:
  /// a sky app that queried NASA whenever a tab changed would behave like a scraper, and NASA
  /// drops connections that do - measured while building the test fixtures.
  final Map<String, GeocentricReading> _reference = {};

  /// The instant `_reference` describes. Pinned before the first request so that all nine answers
  /// are for the same moment; mixing readings from different seconds would put the Moon in two
  /// places at once.
  DateTime? _referenceFor;

  StreamSubscription<GeocentricReading>? _refinement;
  bool _refining = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _refinement?.cancel();
    _horizons.close();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final catalogue = await Catalogue.load(DefaultAssetBundle.of(context));
      final source = LocationSource();
      final located = await source.locate();
      final place = located ??
          LocatedObserver(
            observer: fallbackPlaces.first.observer,
            label: fallbackPlaces.first.label,
            source: PositionSource.chosen,
            note: source.lastNote,
          );
      if (!mounted) return;
      setState(() {
        _catalogue = catalogue;
        _place = place;
      });
      _recompute();
      _refine();
    } on Object catch (error) {
      if (!mounted) return;
      // Named rather than hidden behind a spinner that never stops. The most likely cause is a
      // missing asset, and the fix is a command, so the message says the command.
      setState(() => _failure = '$error');
    }
  }

  /// Rebuild the sky from whatever is known right now.
  void _recompute() {
    final catalogue = _catalogue;
    final place = _place;
    if (catalogue == null || place == null) return;

    final when = _referenceFor ?? DateTime.now().toUtc();
    setState(() {
      _sky = computeSkyNow(
        when: when,
        observer: place.observer,
        catalogue: catalogue,
        reference: Map.of(_reference),
      );
    });
  }

  /// Ask NASA for the same positions, in the background, one at a time.
  void _refine() {
    _refinement?.cancel();
    final when = DateTime.now().toUtc();
    _reference.clear();
    _referenceFor = when;
    setState(() => _refining = true);
    _recompute();

    _refinement = _horizons.geocentricPositions(when: when).listen(
      (reading) {
        _reference[reading.body] = reading;
        _recompute();
      },
      onDone: () {
        if (mounted) setState(() => _refining = false);
      },
      onError: (Object _) {
        // Each body's failure is already swallowed inside the client, so reaching here means the
        // whole stream gave up. There is nothing to recover: the computed positions are still on
        // screen and the provenance line already says so.
        if (mounted) setState(() => _refining = false);
      },
      cancelOnError: false,
    );
  }

  void _choosePlace(LocatedObserver place) {
    setState(() => _place = place);
    _recompute();
  }

  @override
  Widget build(BuildContext context) {
    if (_failure != null) return _Failure(message: _failure!);
    final sky = _sky;
    final place = _place;
    if (sky == null || place == null) return const _Loading();

    final pages = [
      OverheadPage(
        sky: sky,
        place: place,
        onChoosePlace: _choosePlace,
        refining: _refining,
        onRefresh: _refine,
      ),
      // The 3D scene gets the catalogue because its starfield is the real one - the same 9,096
      // rows the Overhead plot draws from, so the two screens cannot show different skies.
      SolarSystemView(catalogue: _catalogue!),
      EnergyPage(sky: sky),
      SignPage(sky: sky),
      MoonPage(sky: sky),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: _Nav(
        index: _tab,
        onChanged: (index) => setState(() => _tab = index),
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // Words, in sentence case, each naming what the screen shows. No icons: four small pictures
    // of celestial objects would all look like the same dot.
    const labels = ['Overhead', 'Solar system', 'Energy', 'Your sign', 'Moon'];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Night.ground,
        border: Border(top: BorderSide(color: Night.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.block),
          // Scrollable rather than spaced-evenly: five labels overflow a narrow phone, and an
          // overflowing nav bar is a yellow-and-black stripe across the bottom of the app.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                GestureDetector(
                  onTap: () => onChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.row,
                      vertical: Space.tight,
                    ),
                    child: Text(
                      labels[i],
                      style: Face.body.copyWith(
                        color: i == index ? Night.amber : Night.slate,
                        fontWeight: i == index ? FontWeight.w600 : FontWeight.w300,
                      ),
                    ),
                  ),
                ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Text('Working out where you are.', style: Face.body),
        ),
      );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(Space.section),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The star catalogue did not load.', style: Face.title),
              const SizedBox(height: Space.block),
              const Text(
                'It is built from the source catalogues rather than committed. Build it and '
                'restart:',
                style: Face.body,
              ),
              const SizedBox(height: Space.block),
              const Text(
                'py -3.12 data/sources.py\n'
                'py -3.12 data/build_catalogue.py',
                style: Face.value,
              ),
              const SizedBox(height: Space.section),
              Text(message, style: Face.quiet),
            ],
          ),
        ),
      );
}
