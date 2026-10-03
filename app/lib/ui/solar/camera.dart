/// A camera you can fly through the solar system with.
///
/// An orbit camera rather than a free-floating one, and deliberately: six degrees of freedom on a
/// touchscreen means being lost in black space within about four seconds. This always looks at
/// something - the Sun, or a planet you pick - and lets you swing around it and move in and out.
/// Flying "through" the system is then choosing a new thing to look at and watching the camera
/// travel there, which is the part that feels like the films.
library;

import 'dart:math' as math;

/// A right-handed 3D vector in the J2000 ecliptic frame, in astronomical units.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const Vec3 zero = Vec3(0, 0, 0);

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  Vec3 get normalized {
    final l = length;
    return l == 0 ? zero : Vec3(x / l, y / l, z / l);
  }

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  static Vec3 lerp(Vec3 a, Vec3 b, double t) =>
      Vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
}

/// Where a body landed on screen, and how big it is there.
class Projected {
  const Projected({
    required this.screenX,
    required this.screenY,
    required this.radiusPixels,
    required this.distanceAu,
    required this.isVisible,
  });

  final double screenX;
  final double screenY;
  final double radiusPixels;

  /// Distance from the camera, in au. Used to sort back to front, which is what makes one planet
  /// pass in front of another correctly.
  final double distanceAu;

  /// False when the body is behind the camera or off the near plane. Checked rather than clamped:
  /// a body behind you projects to a mirrored position in front of you, which looks like a ghost.
  final bool isVisible;
}

/// An orbit camera with a vertical field of view.
class SolarCamera {
  SolarCamera({
    this.target = Vec3.zero,
    this.distanceAu = 3.0,
    this.yaw = 0.6,
    this.pitch = 0.35,
    this.verticalFovDegrees = 50.0,
  });

  /// The point the camera looks at, in au.
  Vec3 target;

  /// How far back it sits from that point.
  double distanceAu;

  /// Rotation about the ecliptic pole, radians.
  double yaw;

  /// Elevation above the ecliptic plane, radians. Clamped short of the poles so the up vector
  /// never degenerates.
  double pitch;

  final double verticalFovDegrees;

  static const double _maxPitch = 1.45; // just under 83 degrees

  /// The camera's own position in world space.
  Vec3 get position {
    final cp = math.cos(pitch);
    return target +
        Vec3(
          math.cos(yaw) * cp,
          math.sin(pitch),
          math.sin(yaw) * cp,
        ) *
            distanceAu;
  }

  void orbit(double deltaYaw, double deltaPitch) {
    yaw += deltaYaw;
    pitch = (pitch + deltaPitch).clamp(-_maxPitch, _maxPitch);
  }

  /// Multiplicative zoom, so a pinch feels the same at every scale.
  void zoom(double factor) {
    // The floor is about four Sun radii, so the camera cannot end up inside a body. The ceiling
    // is well outside Neptune, which is as far out as the orbits go.
    distanceAu = (distanceAu * factor).clamp(0.013, 120.0);
  }

  /// The three basis vectors of camera space: right, up, and forward (towards the target).
  ({Vec3 right, Vec3 up, Vec3 forward}) get basis {
    final forward = (target - position).normalized;
    // The ecliptic pole as the world up. Near the poles the cross product shrinks, which is why
    // pitch is clamped rather than left free.
    const worldUp = Vec3(0, 1, 0);
    final right = forward.cross(worldUp).normalized;
    final up = right.cross(forward).normalized;
    return (right: right, up: up, forward: forward);
  }

  /// Project a world point onto the screen.
  ///
  /// `radiusAu` is the body's own radius in au; the returned pixel radius is its true angular
  /// size at this distance, so a planet grows as you approach it exactly as it should.
  Projected project(
    Vec3 world,
    double radiusAu, {
    required double screenWidth,
    required double screenHeight,
  }) {
    final b = basis;
    final relative = world - position;
    final depth = relative.dot(b.forward);

    // The near plane. Anything closer is behind the lens or clipping through it.
    if (depth <= 1e-7) {
      return Projected(
        screenX: 0,
        screenY: 0,
        radiusPixels: 0,
        distanceAu: relative.length,
        isVisible: false,
      );
    }

    final halfFov = verticalFovDegrees * math.pi / 180.0 / 2.0;
    // Pixels per unit of tangent at unit depth.
    final focal = (screenHeight / 2.0) / math.tan(halfFov);

    final x = relative.dot(b.right) / depth * focal + screenWidth / 2.0;
    final y = -relative.dot(b.up) / depth * focal + screenHeight / 2.0;
    final radiusPixels = radiusAu / depth * focal;

    return Projected(
      screenX: x,
      screenY: y,
      radiusPixels: radiusPixels,
      distanceAu: relative.length,
      isVisible: true,
    );
  }

  /// Project a direction only, for the stars - which have no useful distance here.
  ///
  /// Stars are placed on a sphere far outside the orbits rather than at their real distances.
  /// Proxima Centauri is 268,000 au away; at true scale every star would be one pixel at the
  /// same place no matter where the camera went, so there would be nothing to gain and a great
  /// deal of floating-point precision to lose.
  Projected projectDirection(
    Vec3 direction, {
    required double screenWidth,
    required double screenHeight,
  }) =>
      project(
        position + direction.normalized * 1000.0,
        0,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
}
