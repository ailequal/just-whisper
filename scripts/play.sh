#!/usr/bin/env bash
# Play a recording from the terminal: scripts/play.sh <name>
# The full-quality file in recordings/originals/ is played when there is one (a microphone take, or the
# source of `just convert`); otherwise recordings/<name>.wav, the 16 kHz mono file whisper reads.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

name="${1:-}"
[ -n "$name" ] || die "usage: scripts/play.sh <name>"
need_tool ffplay
src="$recordings_dir/$name.wav"
for original in "$originals_dir/$name".*; do
  file="${original##*/}"
  if [ -f "$original" ] && [ "${file%.*}" = "$name" ]; then
    src="$original"
    break
  fi
done
[ -f "$src" ] || die "$src not found"
echo "playing $src"
ffplay -hide_banner -nodisp -autoexit "$src"
