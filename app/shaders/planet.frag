#version 460 core
#include <flutter/runtime_effect.glsl>

// One lit, textured sphere, raytraced in screen space.
//
// Why one sphere per invocation rather than the whole solar system in a loop: GLSL requires
// constant indices for sampler arrays, so a loop over ten planets cannot pick the right texture.
// Drawing one body per shader pass sidesteps that entirely - Flutter supplies the texture, the
// position and the radius, and composites the results back to front. Simpler, and it makes each
// planet's own appearance a thing that can be looked at on its own.
//
// The sphere is traced analytically. A ray is fired per pixel, intersected with the sphere, and
// the hit point gives both a surface normal for lighting and a latitude/longitude for the texture
// lookup. That is what makes the terminator - the day/night line - land in the right place and
// curve the way a real sphere's does, rather than being a gradient painted over a circle.

uniform vec2 uSize;        // quad size in pixels
uniform float uRadiusPx;   // apparent radius of the body in pixels
uniform vec3 uSunDir;      // unit vector from the body towards the Sun, in camera space
uniform float uRotation;   // rotation about the body's own axis, radians
uniform float uAxialTilt;  // obliquity, radians
uniform float uIsSun;      // 1 for the Sun: emits instead of being lit
uniform float uRimStrength;// atmospheric rim light, 0 for airless bodies
uniform vec3 uRimColor;
uniform sampler2D uTexture;

out vec4 fragColor;

const float PI = 3.14159265359;

void main() {
  vec2 centre = uSize * 0.5;
  vec2 fromCentre = FlutterFragCoord().xy - centre;
  float distanceFromCentre = length(fromCentre);

  // Everything outside the disc is transparent. The quad is larger than the body so the rim glow
  // has somewhere to fall.
  if (distanceFromCentre > uRadiusPx * 1.9) {
    fragColor = vec4(0.0);
    return;
  }

  // Normalised coordinates on the disc. Outside 1.0 we are past the limb.
  vec2 disc = fromCentre / uRadiusPx;
  float r2 = dot(disc, disc);

  if (r2 > 1.0) {
    // Past the limb: only the atmospheric halo remains, falling off fast.
    float halo = exp(-(sqrt(r2) - 1.0) * 7.0) * uRimStrength;
    // The Sun gets a far wider corona, because it is the only thing here that emits.
    if (uIsSun > 0.5) {
      halo = exp(-(sqrt(r2) - 1.0) * 1.6) * 0.9;
      fragColor = vec4(vec3(1.0, 0.82, 0.52) * halo, halo);
      return;
    }
    fragColor = vec4(uRimColor * halo, halo * 0.75);
    return;
  }

  // The sphere's surface normal at this pixel, in camera space. z points at the viewer.
  float z = sqrt(max(0.0, 1.0 - r2));
  vec3 normal = normalize(vec3(disc.x, -disc.y, z));

  // Undo the axial tilt so the texture's poles sit on the body's own axis rather than the
  // camera's. Earth's 23.4 degrees is why its terminator is not vertical at a solstice.
  float ct = cos(uAxialTilt);
  float st = sin(uAxialTilt);
  vec3 bodyNormal = vec3(
    normal.x,
    normal.y * ct - normal.z * st,
    normal.y * st + normal.z * ct
  );

  // Latitude and longitude from the normal, and the body's own rotation applied to the longitude.
  float latitude = asin(clamp(bodyNormal.y, -1.0, 1.0));
  float longitude = atan(bodyNormal.z, bodyNormal.x) + uRotation;
  vec2 uv = vec2(
    mod(longitude / (2.0 * PI), 1.0),
    0.5 - latitude / PI
  );

  vec3 albedo = texture(uTexture, uv).rgb;

  if (uIsSun > 0.5) {
    // The Sun is not lit by anything; it is the light. Brightened towards the limb rather than
    // darkened, which is what makes it read as a source instead of a ball.
    float limb = 0.75 + 0.45 * (1.0 - z);
    fragColor = vec4(albedo * limb * 1.35, 1.0);
    return;
  }

  // Lambert, with a soft terminator. A hard cosine cut looks like a cardboard cutout; real
  // terminators are softened by surface roughness and, where there is one, by atmosphere.
  float lambert = dot(normal, uSunDir);
  float lit = smoothstep(-0.12, 0.28, lambert);

  // A trace of light on the night side, from reflected light elsewhere in the system. Without it
  // the dark half is a black hole punched in the starfield.
  vec3 colour = albedo * (lit * 1.08 + 0.035);

  // Rim light where the atmosphere is: brightest at the limb and only on the lit side, which is
  // the thin bright crescent you see on a photograph of Earth.
  float rim = pow(1.0 - z, 3.0) * uRimStrength * max(0.0, lambert + 0.25);
  colour += uRimColor * rim;

  fragColor = vec4(colour, 1.0);
}
