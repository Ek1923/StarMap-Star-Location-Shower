/// The solar system, as it is arranged right now, that you can fly through.
///
/// What is real here, because that is the only reason to build it this way rather than animate a
/// diagram:
///
///   * Every planet is where it actually is at the moment on screen. The positions come from the
///     same ephemeris the rest of the app is measured against - JPL's orbital elements - so the
///     alignment you are looking at is tonight's alignment.
///   * Every planet looks like itself. The textures are real maps, laid onto a raytraced sphere
///     and lit from the Sun's actual direction, so the day/night terminator falls where it falls.
///   * Every planet spins at its own rate and on its own axis. Jupiter turns in under ten hours,
///     Venus turns backwards, Uranus rolls on its side because its axis is tipped 97.8 degrees.
///   * The stars behind them are the 9,096 of the Yale catalogue, at their catalogued positions.
///
/// The one thing that is not to scale is SIZE, and it cannot be. At true scale, from three
/// astronomical units away, Earth is one hundredth of a pixel across - the solar system really is
/// almost entirely empty space, and a truthful render of it is a black screen. So radii are
/// exaggerated, the factor is on screen, and a slider takes it back to 1x so you can see what the
/// honest version looks like. Distances are never exaggerated.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show rootBundle;

import '../../sky/catalogue.dart';
import '../../sky/moon.dart';
import '../../sky/planets.dart';
import '../theme.dart';
import 'camera.dart';
import 'solar_body.dart';
import 'starfield.dart';

class SolarSystemView extends StatefulWidget {
  const SolarSystemView({required this.catalogue, super.key});

  final Catalogue catalogue;

  @override
  State<SolarSystemView> createState() => _SolarSystemViewState();
}

class _SolarSystemViewState extends State<SolarSystemView>
    with SingleTickerProviderStateMixin {
  final SolarCamera _camera = SolarCamera();
  late final List<StarPoint> _stars = starPoints(widget.catalogue);
  late final Ticker _ticker;

  final Map<String, ui.Image> _textures = {};
  ui.FragmentShader? _shader;
  String? _loadFailure;

  /// How much bigger than life the bodies are drawn. Stated on screen, never hidden.
  double _sizeExaggeration = 1200;

  /// What the camera is looking at. Changing it flies there rather than cutting.
  String _focus = 'Sun';
  Vec3 _targetDestination = Vec3.zero;

  /// Wall-clock moment the scene depicts. Real time, so the planets are where they are.
  DateTime _when = DateTime.now().toUtc();

  /// Minutes of simulated time per real second. 0 is live.
  double _timeScale = 0;

  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    for (final image in _textures.values) {
      image.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/planet.frag');
      final loaded = <String, ui.Image>{};
      for (final body in solarBodies) {
        final data = await rootBundle.load(body.textureAsset);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        loaded[body.name] = (await codec.getNextFrame()).image;
      }
      if (!mounted) return;
      setState(() {
        _shader = program.fragmentShader();
        _textures.addAll(loaded);
      });
    } on Object catch (error) {
      if (!mounted) return;
      // Named rather than left as a black screen. The likely causes are a missing texture asset
      // or a platform without shader support, and both need saying out loud.
      setState(() => _loadFailure = '$error');
    }
  }

  void _onTick(Duration elapsed) {
    final delta = _lastTick == Duration.zero
        ? Duration.zero
        : elapsed - _lastTick;
    _lastTick = elapsed;
    final seconds = delta.inMicroseconds / 1e6;

    setState(() {
      if (_timeScale == 0) {
        _when = DateTime.now().toUtc();
      } else {
        _when = _when.add(
          Duration(microseconds: (seconds * _timeScale * 60 * 1e6).round()),
        );
      }
      // Ease towards whatever the camera is meant to be looking at. Exponential, so arriving is
      // smooth and the first moment of the move is the fastest - which is how a camera move in a
      // film is cut.
      final k = 1 - math.pow(0.004, seconds).toDouble();
      _camera.target = Vec3.lerp(_camera.target, _targetDestination, k);
    });
  }

  /// Heliocentric position of every body, in au, in the ecliptic frame the camera uses.
  Map<String, Vec3> _positions() {
    final out = <String, Vec3>{'Sun': Vec3.zero};
    final earth = earthHeliocentricPosition(_when);
    // The engine's frame has z as the ecliptic pole; the camera uses y, so the axes are swapped
    // once here rather than in every projection.
    Vec3 toCamera(double x, double y, double z) => Vec3(x, z, y);

    out['Earth'] = toCamera(earth.x, earth.y, earth.z);
    final moon = moonGeocentricVectorOfDateAu(_when);
    out['Moon'] = toCamera(earth.x + moon.x, earth.y + moon.y, earth.z + moon.z);

    for (final body in solarBodies) {
      final planet = body.planet;
      if (planet == null) continue;
      final p = heliocentricPosition(planet, _when);
      out[body.name] = toCamera(p.x, p.y, p.z);
    }
    return out;
  }

  void _focusOn(String name, Map<String, Vec3> positions) {
    final body = solarBodies.firstWhere((b) => b.name == name);
    setState(() {
      _focus = name;
      _targetDestination = positions[name] ?? Vec3.zero;
      // Pull in to a distance that frames the body: a few of its own exaggerated radii. Without
      // this, flying to Mercury leaves it a dot in the middle of the screen.
      final radiusAu = body.equatorialRadiusKm / auKm * _sizeExaggeration;
      _camera.distanceAu = math.max(radiusAu * 6, 0.02);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailure != null) {
      return _SceneFailure(message: _loadFailure!);
    }
    final shader = _shader;
    if (shader == null) {
      return const ColoredBox(
        color: Night.ground,
        child: Center(child: Text('Building the solar system.', style: Face.body)),
      );
    }

    final positions = _positions();

    return ColoredBox(
      color: const Color(0xFF02030A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onScaleStart: (_) {},
            onScaleUpdate: (details) {
              setState(() {
                if (details.scale != 1.0) {
                  _camera.zoom(1 / details.scale.clamp(0.5, 2.0));
                }
                _camera.orbit(
                  -details.focalPointDelta.dx * 0.005,
                  details.focalPointDelta.dy * 0.005,
                );
              });
            },
            child: CustomPaint(
              painter: StarfieldPainter(stars: _stars, camera: _camera),
              child: CustomPaint(
                painter: _OrbitPainter(camera: _camera, when: _when),
                child: _PlanetLayer(
                  shader: shader,
                  textures: _textures,
                  camera: _camera,
                  positions: positions,
                  when: _when,
                  exaggeration: _sizeExaggeration,
                ),
              ),
            ),
          ),
          _Hud(
            focus: _focus,
            when: _when,
            exaggeration: _sizeExaggeration,
            timeScale: _timeScale,
            onFocus: (name) => _focusOn(name, positions),
            onExaggeration: (value) => setState(() => _sizeExaggeration = value),
            onTimeScale: (value) => setState(() => _timeScale = value),
          ),
        ],
      ),
    );
  }
}

/// Draws the bodies, farthest first, each through the sphere shader.
class _PlanetLayer extends StatelessWidget {
  const _PlanetLayer({
    required this.shader,
    required this.textures,
    required this.camera,
    required this.positions,
    required this.when,
    required this.exaggeration,
  });

  final ui.FragmentShader shader;
  final Map<String, ui.Image> textures;
  final SolarCamera camera;
  final Map<String, Vec3> positions;
  final DateTime when;
  final double exaggeration;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _PlanetPainter(
          shader: shader,
          textures: textures,
          camera: camera,
          positions: positions,
          when: when,
          exaggeration: exaggeration,
        ),
      );
}

class _PlanetPainter extends CustomPainter {
  _PlanetPainter({
    required this.shader,
    required this.textures,
    required this.camera,
    required this.positions,
    required this.when,
    required this.exaggeration,
  });

  final ui.FragmentShader shader;
  final Map<String, ui.Image> textures;
  final SolarCamera camera;
  final Map<String, Vec3> positions;
  final DateTime when;
  final double exaggeration;

  @override
  void paint(Canvas canvas, Size size) {
    // Back to front, so a near planet covers a far one. This is the depth sort that a real 3D
    // pipeline would do with a z-buffer; with ten opaque spheres, sorting is simpler and exact.
    final drawable = <({SolarBody body, Projected at})>[];
    for (final body in solarBodies) {
      final world = positions[body.name];
      final texture = textures[body.name];
      if (world == null || texture == null) continue;
      final radiusAu = body.equatorialRadiusKm / auKm * exaggeration;
      final at = camera.project(
        world,
        radiusAu,
        screenWidth: size.width,
        screenHeight: size.height,
      );
      if (!at.isVisible || at.radiusPixels < 0.3) continue;
      drawable.add((body: body, at: at));
    }
    drawable.sort((a, b) => b.at.distanceAu.compareTo(a.at.distanceAu));

    for (final entry in drawable) {
      _paintBody(canvas, size, entry.body, entry.at);
    }
  }

  void _paintBody(Canvas canvas, Size size, SolarBody body, Projected at) {
    final texture = textures[body.name]!;
    final world = positions[body.name]!;

    // The quad is wider than the body so the atmospheric halo has room to fall off.
    final half = at.radiusPixels * 1.95;
    final rect = Rect.fromCenter(
      center: Offset(at.screenX, at.screenY),
      width: half * 2,
      height: half * 2,
    );

    // Direction from the body to the Sun, expressed in camera axes, which is what the shader
    // lights by. For the Sun itself this is unused.
    final basis = camera.basis;
    final toSun = (Vec3.zero - world).normalized;
    final sunX = toSun.dot(basis.right);
    final sunY = toSun.dot(basis.up);
    final sunZ = -toSun.dot(basis.forward);

    // Rotation about the body's own axis. Real period, so Jupiter visibly turns while you watch
    // and Venus goes the other way.
    final hours = when.difference(DateTime.utc(2000, 1, 1, 12)).inSeconds / 3600.0;
    final rotation = (hours / body.rotationPeriodHours) * 2 * math.pi;

    if (body.hasRings) {
      _paintRings(canvas, body, at);
    }

    shader
      ..setFloat(0, rect.width)
      ..setFloat(1, rect.height)
      ..setFloat(2, at.radiusPixels)
      ..setFloat(3, sunX)
      ..setFloat(4, sunY)
      ..setFloat(5, sunZ)
      ..setFloat(6, rotation % (2 * math.pi))
      ..setFloat(7, body.axialTiltDegrees * math.pi / 180.0)
      ..setFloat(8, body.isSun ? 1.0 : 0.0)
      ..setFloat(9, body.rimStrength)
      ..setFloat(10, body.rimColor.r)
      ..setFloat(11, body.rimColor.g)
      ..setFloat(12, body.rimColor.b)
      ..setImageSampler(0, texture);

    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, rect.width, rect.height),
      Paint()..shader = shader,
    );
    canvas.restore();

    // A name, once the body is big enough that a label is not noise.
    if (at.radiusPixels > 3) {
      final painter = TextPainter(
        text: TextSpan(
          text: body.name,
          style: Face.quiet.copyWith(
            color: Night.parchment.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(at.screenX + at.radiusPixels + 8, at.screenY - 7),
      );
    }
  }

  /// Saturn's rings, as a flattened ellipse in the plane of its equator.
  ///
  /// Drawn as a ring rather than with the ring texture mapped properly: a correct ring needs the
  /// ring plane projected through the camera and the planet's shadow cast onto it, which is a
  /// second shader. This is honest about being simpler - it is the right shape, in the right
  /// plane, at the right radius (the A ring's outer edge is 2.27 Saturn radii).
  void _paintRings(Canvas canvas, SolarBody body, Projected at) {
    final outer = at.radiusPixels * 2.27;
    final inner = at.radiusPixels * 1.24;
    // The tilt squashes the ellipse. Saturn's 26.7 degree obliquity is why the rings open and
    // close over its 29-year orbit.
    final squash = math.sin(body.axialTiltDegrees * math.pi / 180.0).abs().clamp(0.08, 1.0);

    canvas.save();
    canvas.translate(at.screenX, at.screenY);
    canvas.scale(1.0, squash);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outer - inner
      ..color = const Color(0xFFD9C9A8).withValues(alpha: 0.55);
    canvas.drawCircle(Offset.zero, (outer + inner) / 2, paint);
    // The Cassini division, which is a real 4,800 km gap and visible in any photograph.
    canvas.drawCircle(
      Offset.zero,
      at.radiusPixels * 1.95,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, (outer - inner) * 0.08)
        ..color = const Color(0xFF02030A).withValues(alpha: 0.7),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlanetPainter old) => true;
}

/// The orbits, sampled from the same ephemeris that places the planets.
///
/// Not drawn as circles. Each path is the planet's real orbit, evaluated at points around one of
/// its own years, so Mercury's is visibly off-centre and Pluto-like eccentricity would show if
/// anything here had it.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.camera, required this.when});

  final SolarCamera camera;
  final DateTime when;

  /// Orbital periods in days, for sampling one full loop each.
  static const Map<Planet, double> _periodDays = {
    Planet.mercury: 87.969,
    Planet.venus: 224.701,
    Planet.mars: 686.980,
    Planet.jupiter: 4332.589,
    Planet.saturn: 10759.22,
    Planet.uranus: 30685.4,
    Planet.neptune: 60189.0,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF2A3550).withValues(alpha: 0.55);

    for (final entry in _periodDays.entries) {
      final path = Path();
      var started = false;
      const samples = 96;
      for (var i = 0; i <= samples; i++) {
        final at = when.add(
          Duration(seconds: ((entry.value * 86400) * i / samples).round()),
        );
        // Outside the elements' fitted range there is no position, and an orbit drawn from a
        // refusal would be a guess. Neptune's 165-year period runs past 2050 from here, so this
        // is reached in normal use rather than being defensive clutter.
        final Vec3 point;
        try {
          final p = heliocentricPosition(entry.key, at);
          point = Vec3(p.x, p.z, p.y);
        } on OutsideValidRangeException {
          break;
        }
        final projected = camera.project(
          point,
          0,
          screenWidth: size.width,
          screenHeight: size.height,
        );
        if (!projected.isVisible) {
          started = false;
          continue;
        }
        final offset = Offset(projected.screenX, projected.screenY);
        if (!started) {
          path.moveTo(offset.dx, offset.dy);
          started = true;
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => true;
}

/// The controls, and the one disclosure the scene cannot do without.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.focus,
    required this.when,
    required this.exaggeration,
    required this.timeScale,
    required this.onFocus,
    required this.onExaggeration,
    required this.onTimeScale,
  });

  final String focus;
  final DateTime when;
  final double exaggeration;
  final double timeScale;
  final ValueChanged<String> onFocus;
  final ValueChanged<double> onExaggeration;
  final ValueChanged<double> onTimeScale;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.block),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${when.toLocal().day}/${when.toLocal().month}/${when.toLocal().year}  '
                '${when.toLocal().hour.toString().padLeft(2, '0')}:'
                '${when.toLocal().minute.toString().padLeft(2, '0')}',
                style: Face.quiet.copyWith(color: Night.parchment),
              ),
              Text(
                timeScale == 0
                    ? 'Live. Every planet is where it is right now.'
                    : '${timeScale.round()} minutes per second.',
                style: Face.quiet,
              ),
              const Spacer(),
              // The disclosure. The scene is a lie about one thing and this is where it says so.
              Text(
                exaggeration <= 1.01
                    ? 'True scale. Earth is the pixel you cannot find - the solar system is '
                        'almost entirely empty space.'
                    : 'Bodies drawn ${exaggeration.round()}x life size. Distances are real.',
                style: Face.quiet,
              ),
              Slider(
                value: math.log(exaggeration) / math.ln10,
                min: 0,
                max: 3.7,
                activeColor: Night.amber,
                inactiveColor: Night.hairline,
                onChanged: (value) => onExaggeration(math.pow(10, value).toDouble()),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final body in solarBodies)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.block),
                        child: GestureDetector(
                          onTap: () => onFocus(body.name),
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            body.name,
                            style: Face.body.copyWith(
                              color: body.name == focus ? Night.amber : Night.slate,
                              fontWeight:
                                  body.name == focus ? FontWeight.w600 : FontWeight.w300,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _SceneFailure extends StatelessWidget {
  const _SceneFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Night.ground,
        child: Padding(
          padding: const EdgeInsets.all(Space.section),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The solar system did not load.', style: Face.title),
              const SizedBox(height: Space.block),
              const Text(
                'It needs the planet textures and a device that can compile fragment shaders. '
                'The rest of the app does not, so the other screens still work.',
                style: Face.body,
              ),
              const SizedBox(height: Space.section),
              Text(message, style: Face.quiet),
            ],
          ),
        ),
      );
}
