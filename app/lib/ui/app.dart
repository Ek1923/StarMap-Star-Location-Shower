/// The shell: load the catalogue, find out where we are, compute the sky, show four views of it.
///
/// One computation per minute feeds all four screens, so nothing on screen can disagree with
/// anything else on screen.
library;

import 'package:flutter/material.dart';

import '../sky/catalogue.dart';
import '../sky/sky_now.dart';
import 'energy_page.dart';
import 'location_source.dart';
import 'moon_page.dart';
import 'overhead_page.dart';
import 'sign_page.dart';
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
  Catalogue? _catalogue;
  LocatedObserver? _place;
  SkyNow? _sky;
  String? _failure;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _start();
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
        _sky = computeSkyNow(
          when: DateTime.now(),
          observer: place.observer,
          catalogue: catalogue,
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      // Named rather than hidden behind a spinner that never stops. The most likely cause is a
      // missing asset, and the fix is a command, so the message says the command.
      setState(() => _failure = '$error');
    }
  }

  void _choosePlace(LocatedObserver place) {
    final catalogue = _catalogue;
    if (catalogue == null) return;
    setState(() {
      _place = place;
      _sky = computeSkyNow(
        when: DateTime.now(),
        observer: place.observer,
        catalogue: catalogue,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failure != null) return _Failure(message: _failure!);
    final sky = _sky;
    final place = _place;
    if (sky == null || place == null) return const _Loading();

    final pages = [
      OverheadPage(sky: sky, place: place, onChoosePlace: _choosePlace),
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
    const labels = ['Overhead', 'Energy', 'Your sign', 'Moon'];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Night.ground,
        border: Border(top: BorderSide(color: Night.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.block),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
