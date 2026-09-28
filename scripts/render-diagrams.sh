#!/bin/bash
# Renders Mermaid authored in DocC Markdown and embeds the SVGs in the Pages artifact.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_DIR="${1:?Usage: scripts/render-diagrams.sh <DocC output directory>}"
if [[ "$SITE_DIR" != /* ]]; then
  SITE_DIR="$ROOT/$SITE_DIR"
fi

WORK_DIR="$(mktemp -d)"
MERMAID_CONFIG="$(mktemp)"
PUPPETEER_CONFIG="$(mktemp)"
MMDC=(npx --yes -p @mermaid-js/mermaid-cli mmdc)
trap 'rm -rf "$WORK_DIR"; rm -f "$MERMAID_CONFIG" "$PUPPETEER_CONFIG"' EXIT

# Plain-SVG text labels avoid <foreignObject>, which can lose text when loaded
# through <img>. Sequence spacing keeps the diagram readable in DocC's column.
printf '{"htmlLabels": false, "flowchart": {"htmlLabels": false}, "sequence": {"actorMargin": 100, "messageMargin": 20, "boxMargin": 5}}' > "$MERMAID_CONFIG"
# Chromium sandbox flags for GitHub-hosted CI runners.
printf '{"args": ["--no-sandbox", "--disable-setuid-sandbox"]}' > "$PUPPETEER_CONFIG"

stamp_intrinsic_size() {
  local svg="$1"
  local viewbox width height
  viewbox="$(grep -o 'viewBox="[^"]*"' "$svg" | head -1 | sed -E 's/viewBox="([^"]*)"/\1/')"
  width="$(echo "$viewbox" | awk '{print $3}')"
  height="$(echo "$viewbox" | awk '{print $4}')"
  [ -n "$width" ] && [ -n "$height" ] || return 0
  perl -i -pe "s/width=\"100%\"/width=\"${width}\" height=\"${height}\"/ if !\$done++" "$svg"
}

render_diagram() {
  local source="$1" output_dir="$2" name="$3"
  mkdir -p "$output_dir"
  echo "Rendering $source"
  "${MMDC[@]}" -i "$source" -o "$output_dir/$name.svg" \
    -c "$MERMAID_CONFIG" -p "$PUPPETEER_CONFIG" -t neutral -b white
  "${MMDC[@]}" -i "$source" -o "$output_dir/$name~dark.svg" \
    -c "$MERMAID_CONFIG" -p "$PUPPETEER_CONFIG" -t dark -b transparent
  stamp_intrinsic_size "$output_dir/$name.svg"
  stamp_intrinsic_size "$output_dir/$name~dark.svg"
}

MANIFEST="$WORK_DIR/manifest.json"
python3 "$ROOT/scripts/mermaid-docs.py" prepare "$ROOT" "$WORK_DIR" "$MANIFEST"
while IFS= read -r source; do
  module="$(basename "$(dirname "$source")")"
  name="$(basename "$source" .mmd)"
  render_diagram "$source" "$SITE_DIR/images/$module" "$name"
done < <(python3 "$ROOT/scripts/mermaid-docs.py" render-inputs "$MANIFEST")
python3 "$ROOT/scripts/mermaid-docs.py" embed "$SITE_DIR" "$MANIFEST"

# The README uses a checked-in light/dark pair under the lowercase asset/ directory.
for source in "$ROOT"/asset/*.mmd; do
  [ -f "$source" ] || continue
  render_diagram "$source" "$ROOT/asset" "$(basename "$source" .mmd)"
done
