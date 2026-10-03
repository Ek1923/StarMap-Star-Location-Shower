#!/usr/bin/env bash
# Fetch the planet surface maps the 3D view needs.
#
# Not committed to the repository: they are 5.1 MB of somebody else's images, licensed CC BY 4.0
# by Solar System Scope (INOVE), and five megabytes of JPEG in git history is five megabytes
# nobody can review. See app/assets/planets/README.md for the attribution the licence requires.
#
# Run from the repository root:  bash scripts/fetch_planet_textures.sh
set -euo pipefail

DEST="app/assets/planets"
BASE="https://www.solarsystemscope.com/textures/download"
mkdir -p "$DEST"

files=(
  2k_sun.jpg 2k_mercury.jpg 2k_venus_atmosphere.jpg 2k_earth_daymap.jpg 2k_moon.jpg
  2k_mars.jpg 2k_jupiter.jpg 2k_saturn.jpg 2k_uranus.jpg 2k_neptune.jpg
  2k_saturn_ring_alpha.png
)

failed=0
for f in "${files[@]}"; do
  printf '%-28s ' "$f"
  curl -fsS --max-time 120 -o "$DEST/$f" "$BASE/$f" || { echo "FAILED"; failed=1; continue; }
  # A 200 response carrying an HTML error page is the usual way a scripted download goes wrong,
  # so the magic bytes are checked rather than the status code.
  magic=$(head -c4 "$DEST/$f" | xxd -p)
  case "$magic" in
    ffd8ff*) echo "ok, JPEG, $(stat -c%s "$DEST/$f") bytes" ;;
    89504e47) echo "ok, PNG, $(stat -c%s "$DEST/$f") bytes" ;;
    *)       echo "NOT AN IMAGE (magic $magic) - deleting"; rm -f "$DEST/$f"; failed=1 ;;
  esac
done

[ "$failed" -eq 0 ] || { echo; echo "Some textures are missing. The 3D view will show its own error screen."; exit 1; }
echo
echo "All ${#files[@]} textures present in $DEST"
