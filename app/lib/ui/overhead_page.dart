/// What is above you, right now.
library;

import 'package:flutter/material.dart';

import '../sky/sky_now.dart';
import 'location_source.dart';
import 'sky_plot.dart';
import 'theme.dart';

class OverheadPage extends StatefulWidget {
  const OverheadPage({
    required this.sky,
    required this.place,
    required this.onChoosePlace,
    super.key,
  });

  final SkyNow sky;
  final LocatedObserver place;
  final ValueChanged<LocatedObserver> onChoosePlace;

  @override
  State<OverheadPage> createState() => _OverheadPageState();
}

class _OverheadPageState extends State<OverheadPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The one piece of motion in the app: the sky fills in from the horizon upward, once. It
    // shows that the plot's vertical axis is height, which is the thing a first-time viewer has
    // to understand before anything else makes sense.
    //
    // Here rather than in initState because it reads MediaQuery, and reading an inherited widget
    // in initState is not allowed - it throws in a widget test and misbehaves in release.
    // Respecting the reduce-motion setting is why it has to read MediaQuery at all.
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sky = widget.sky;
    final up = sky.planetsUp.toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      children: [
        const SizedBox(height: Space.block),
        _PlaceLine(place: widget.place, onChoosePlace: widget.onChoosePlace),
        const SizedBox(height: Space.block),
        Text(_headline(sky), style: Face.display),
        const SizedBox(height: Space.row),
        Text(_subhead(sky), style: Face.body),
        const SizedBox(height: Space.section),
        SizedBox(
          height: 320,
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, _) => SkyPlot(sky: sky, reveal: _entrance.value),
          ),
        ),
        const SizedBox(height: Space.section),
        for (final body in [sky.moon, ...up])
          if (body.isAboveHorizon) _BodyRow(body: body),
        if (up.isEmpty && !sky.moon.isAboveHorizon)
          const Text(
            'No planet and no Moon is above your horizon. The stars on the plot are still '
            'there - and that is a quieter sky than most nights.',
            style: Face.body,
          ),
        const SizedBox(height: Space.section),
        _BelowHorizon(sky: sky),
        const SizedBox(height: Space.section),
      ],
    );
  }

  String _headline(SkyNow sky) {
    if (!sky.isDark) {
      final altitude = sky.sun.horizontal.altitudeDegrees;
      return altitude > 0 ? 'The Sun is up.' : 'Still twilight.';
    }
    final brightest = sky.planetsUp.isEmpty ? null : sky.planetsUp.first;
    if (brightest == null) return 'Dark, and no planets up.';
    return '${brightest.name} is '
        '${formatAltitude(brightest.horizontal.altitudeDegrees)} up.';
  }

  String _subhead(SkyNow sky) {
    if (!sky.isDark) {
      final altitude = sky.sun.horizontal.altitudeDegrees;
      if (altitude > 0) {
        return 'Nothing else is visible while the Sun is ${formatAltitude(altitude)} above '
            'the horizon. The plot below still shows where everything is.';
      }
      return 'The Sun is ${formatAltitude(altitude)} below the horizon. Stars start showing '
          'once it passes 6° down.';
    }
    final brightest = sky.planetsUp.isEmpty ? null : sky.planetsUp.first;
    if (brightest == null) {
      return '${sky.stars.length} stars brighter than magnitude 4 are above your horizon.';
    }
    return 'Look ${formatBearing(brightest.horizontal.azimuthDegrees)}. '
        '${sky.stars.length} stars brighter than magnitude 4 are up with it.';
  }
}

class _PlaceLine extends StatelessWidget {
  const _PlaceLine({required this.place, required this.onChoosePlace});

  final LocatedObserver place;
  final ValueChanged<LocatedObserver> onChoosePlace;

  @override
  Widget build(BuildContext context) {
    final local = DateTime.now();
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _pick(context),
          behavior: HitTestBehavior.opaque,
          child: Text(
            '${place.label} at $time',
            style: Face.body.copyWith(color: Night.slate),
          ),
        ),
        if (place.note != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.tight),
            child: Text(
              '${place.note!} Showing ${place.label} instead - tap to change.',
              style: Face.quiet,
            ),
          ),
      ],
    );
  }

  void _pick(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Night.belowHorizon,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(Space.page),
              child: Text('Show the sky from', style: Face.title),
            ),
            for (final option in fallbackPlaces)
              ListTile(
                title: Text(option.label, style: Face.body),
                subtitle: Text(
                  '${option.observer.latitudeDegrees.toStringAsFixed(2)}°, '
                  '${option.observer.longitudeEastDegrees.toStringAsFixed(2)}°',
                  style: Face.quiet,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onChoosePlace(option);
                },
              ),
            const SizedBox(height: Space.block),
          ],
        ),
      ),
    );
  }
}

class _BodyRow extends StatelessWidget {
  const _BodyRow({required this.body});

  final SkyBody body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.block),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(body.name, style: Face.title),
                  Text(
                    '${formatBearing(body.horizontal.azimuthDegrees)}, '
                    '${formatAltitude(body.horizontal.altitudeDegrees)} up',
                    style: Face.quiet,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('magnitude ${body.magnitude.toStringAsFixed(1)}', style: Face.value),
                if (body.distanceAu.isFinite)
                  Text('light left ${formatLightTime(body.lightTravelMinutes)}',
                      style: Face.quiet),
              ],
            ),
          ],
        ),
      );
}

class _BelowHorizon extends StatelessWidget {
  const _BelowHorizon({required this.sky});

  final SkyNow sky;

  @override
  Widget build(BuildContext context) {
    final down = sky.planets.where((p) => !p.isAboveHorizon).toList();
    if (down.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Under your feet', style: Face.title),
        const SizedBox(height: Space.row),
        Text(
          '${down.map((p) => p.name).join(', ')} '
          '${down.length == 1 ? 'is' : 'are'} below the horizon right now. '
          'The Earth is in the way.',
          style: Face.body.copyWith(color: Night.slate),
        ),
      ],
    );
  }
}
