#!/usr/bin/env bash
# Play recordings/<name>.wav from the terminal: scripts/play.sh <name>
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

name="${1:-}"
[ -n "$name" ] || die "usage: scripts/play.sh <name>"
need_tool ffplay
ffplay -hide_banner -nodisp -autoexit "$recordings_dir/$name.wav"
