#!/usr/bin/env bash
# test.sh [--perf | --parity N]
# Headless: no browser, no display. Everything the exported page runs, run here.
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
$GODOT --headless --import >/dev/null 2>&1 || true
if [ $# -gt 0 ]; then
  exec $GODOT --headless --script res://scripts/tests.gd -- "$@"
fi
$GODOT --headless --script res://scripts/tests.gd
##
## The deadfall render check is a second process because it is a renderer, not
## an assertion over numbers: it rasterises the field from three angles and
## looks at the pixels. See scripts/blocks.gd for why a headless PNG is the only
## place on this host where a culling bug is visible at all.
##
exec $GODOT --headless --script res://scripts/blocks.gd
