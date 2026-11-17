#!/usr/bin/env bash
# Write transcripts/<name>.md: a Markdown file with what produced the transcript, the speech statistics
# and the transcript as one `[mm:ss] text` line per segment. One file to paste into a chat, an LLM
# prompt, a note or a document, with positions you can cite. The same `[mm:ss] text` lines alone go to
# transcripts/<name>.timestamps.txt, for when plain text with positions is all you need.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

name="${1:-}"
[ -n "$name" ] || die "usage: scripts/export.sh <name>"
json="$transcripts_dir/$name.json"
log="$transcripts_dir/$name.log"
[ -f "$json" ] || die "$json not found: run \`just transcribe $name\` first"
need_tool uv
out="$transcripts_dir/$name.md"
stamped="$transcripts_dir/$name.timestamps.txt"

{
  echo "# Transcript: $name"
  echo
  echo "Transcribed locally with whisper.cpp. Automatic text: expect missing punctuation, a few wrong names"
  echo "or foreign words, and an occasional merged or dropped sentence at a segment boundary."
  echo
  if [ -f "$log" ]; then
    # the first lines of the log say when, with which whisper.cpp, model, prompt and flags
    sed -n 's/^# //p' "$log" | sed 's/^/- /'
    echo
  fi
  echo '## Statistics'
  echo
  echo '```'
  scripts/stats.sh "$name" 2>&1 || true
  echo '```'
  echo
  echo '## Text'
  echo
  echo "One segment per line, prefixed with its start time. Lines marked \`[?]\` have a mean token confidence below $LOW_CONFIDENCE: listen again there."
  echo
  uv run python -I scripts/transcript-timestamps.py "$json" --low-confidence "$LOW_CONFIDENCE" | tee "$stamped"
} > "$out"
echo "written $out and $stamped"
