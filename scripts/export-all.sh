#!/usr/bin/env bash
# Export every transcript that has a JSON file, then write transcripts/INDEX.md with one row per transcript.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need_tool uv
found=0
for json in "$transcripts_dir"/*.json; do
  [ -e "$json" ] || continue
  found=1
  scripts/export.sh "$(basename "$json" .json)"
done
[ "$found" = 1 ] || die "no transcripts in $transcripts_dir/"
uv run python -I scripts/transcript-index.py "$transcripts_dir" > "$transcripts_dir/INDEX.md"
echo "written $transcripts_dir/INDEX.md"
