#!/usr/bin/env bash
# Transcribe every recordings/*.wav that has no transcripts/<name>.txt yet.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

found=0
for wav in "$recordings_dir"/*.wav; do
  [ -e "$wav" ] || continue
  found=1
  name="$(basename "$wav" .wav)"
  if [ -f "$transcripts_dir/$name.txt" ]; then
    echo "skip $name (already transcribed)"
    continue
  fi
  scripts/transcribe.sh "$name"
done
[ "$found" = 1 ] || echo "no recordings in $recordings_dir/"
