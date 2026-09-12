#!/bin/sh
SRCROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$SRCROOT/.gitnagg.yml" ] || exit 0

if command -v mise >/dev/null 2>&1; then
  GITNAGG="mise exec -q -- gitnagg"
elif command -v gitnagg >/dev/null 2>&1; then
  GITNAGG=$(command -v gitnagg)
else
  exit 0
fi

$GITNAGG check --config "$SRCROOT/.gitnagg.yml" --claude-hook
