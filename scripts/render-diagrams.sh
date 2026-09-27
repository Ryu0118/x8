#!/bin/bash
# Renders Mermaid diagram sources into DocC catalog resources and README assets.
#
# Neither DocC nor GitHub's view of a .docc article renders ```mermaid blocks,
# so diagram sources live as .mmd files under <catalog>.docc/Diagrams/ and are
# pre-rendered here into the catalog root, next to the articles.
#
# Convention: Diagrams/<name>.mmd renders to <catalog>.docc/<name>.svg (light)
# and <name>~dark.svg (dark). Articles reference the file name with extension:
#   ![alt text](<name>.svg)
# GitHub resolves that path relative to the article; DocC finds the file by
# name anywhere in the catalog and pairs it with the ~dark variant. A
# subdirectory path such as Resources/<name>.svg breaks DocC's lookup.
#
# The top-level Diagrams/ directory holds README diagrams, rendered in place
# with the same convention. All rendered SVGs are committed because nothing
# renders them for GitHub; re-run this script after editing any .mmd source
# and commit the result.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MMDC=(npx --yes -p @mermaid-js/mermaid-cli mmdc)

# Plain-SVG text labels (htmlLabels renders via <foreignObject>, which can
# drop label text when the SVG is loaded through <img>, as DocC does).
#
# The sequence.* overrides widen actor spacing and tighten message spacing.
# DocC's article images are capped at max-height:560px, and a sequence
# diagram's natural shape (actors side by side, messages stacked downward)
# is otherwise tall enough that the resulting width shrinks well below the
# article's text column; this doesn't fix that, but narrows the gap.
MERMAID_CONFIG="$(mktemp)"
printf '{"htmlLabels": false, "flowchart": {"htmlLabels": false}, "sequence": {"actorMargin": 100, "messageMargin": 20, "boxMargin": 5}}' > "$MERMAID_CONFIG"

# Chromium sandbox flags for CI runners where the sandbox is unavailable.
PUPPETEER_CONFIG="$(mktemp)"
printf '{"args": ["--no-sandbox", "--disable-setuid-sandbox"]}' > "$PUPPETEER_CONFIG"
trap 'rm -f "$MERMAID_CONFIG" "$PUPPETEER_CONFIG"' EXIT

# mmdc emits `width="100%"` with no `height`, so a viewer without other size
# hints (DocC included) falls back to a tiny default box instead of the
# diagram's real proportions. Stamp explicit pixel width/height from the
# viewBox onto each SVG so it renders at its intended size.
stamp_intrinsic_size() {
  local svg="$1"
  local viewbox width height
  viewbox="$(grep -o 'viewBox="[^"]*"' "$svg" | head -1 | sed -E 's/viewBox="([^"]*)"/\1/')"
  width="$(echo "$viewbox" | awk '{print $3}')"
  height="$(echo "$viewbox" | awk '{print $4}')"
  [ -n "$width" ] && [ -n "$height" ] || return 0
  perl -i -pe "s/width=\"100%\"/width=\"${width}\" height=\"${height}\"/ if !\$done++" "$svg"
}

render_diagrams() {
  local diagrams_dir="$1" output_dir="$2"
  local src name
  mkdir -p "$output_dir"
  for src in "$diagrams_dir"/*.mmd; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .mmd)"
    echo "Rendering $src"
    "${MMDC[@]}" -i "$src" -o "$output_dir/$name.svg" \
      -c "$MERMAID_CONFIG" -p "$PUPPETEER_CONFIG" -t neutral -b white
    "${MMDC[@]}" -i "$src" -o "$output_dir/$name~dark.svg" \
      -c "$MERMAID_CONFIG" -p "$PUPPETEER_CONFIG" -t dark -b transparent
    stamp_intrinsic_size "$output_dir/$name.svg"
    stamp_intrinsic_size "$output_dir/$name~dark.svg"
  done
}

for diagrams_dir in "$ROOT"/Sources/*/*.docc/Diagrams; do
  [ -d "$diagrams_dir" ] || continue
  render_diagrams "$diagrams_dir" "$(dirname "$diagrams_dir")"
done

if [ -d "$ROOT/Diagrams" ]; then
  render_diagrams "$ROOT/Diagrams" "$ROOT/Diagrams"
fi
