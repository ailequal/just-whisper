#!/usr/bin/env bash
# Second opinion on the low-confidence segments of a transcript: scripts/recheck.sh <name>
# Each segment that `just stats` lists under confidence is transcribed again, alone, with the full
# RECHECK_MODEL (large-v3: same encoder, 32 decoder layers instead of 4). The result goes to
# transcripts/<name>.recheck.md, original and second reading side by side; the transcript itself is not changed.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

name="${1:-}"
[ -n "$name" ] || die "usage: scripts/recheck.sh <name>"
json="$transcripts_dir/$name.json"
wav="$recordings_dir/$name.wav"
[ -f "$json" ] || die "$json not found: run \`just transcribe $name\` first"
[ -f "$wav" ] || die "$wav not found: the recording is needed to listen again"
need_cli
need_tool uv
recheck_model="$WHISPER_MODELS_DIR/ggml-$RECHECK_MODEL.bin"
[ -f "$recheck_model" ] || die "$recheck_model missing: download it once with \`WHISPER_MODEL=$RECHECK_MODEL just models\` (large-v3 is 2.9 GiB)"
out="$transcripts_dir/$name.recheck.md"

prompt_src="$(prompt_file)"
prompt_args=()
[ -s "$prompt_src" ] && prompt_args=(--prompt "$(tr '\n' ' ' < "$prompt_src")")

# "from_ms<TAB>to_ms<TAB>confidence<TAB>text" per low-confidence segment
low="$(uv run python -I scripts/transcript-timestamps.py "$json" --low-confidence "$LOW_CONFIDENCE" --list-low)"
if [ -z "$low" ]; then
  echo "no segment below $LOW_CONFIDENCE in $json: nothing to recheck"
  exit 0
fi
count="$(printf '%s\n' "$low" | wc -l | tr -d ' ')"
echo "rechecking $count segment(s) of $name with $RECHECK_MODEL"

{
  echo "# Recheck: $name"
  echo
  echo "Segments with a mean token confidence below $LOW_CONFIDENCE, transcribed again on their own with \`$RECHECK_MODEL\`."
  echo "The second reading is not automatically better: it is a different decoder's opinion on the same audio, to compare and to listen again where they disagree. The transcript files are unchanged."
  echo
  echo "| Start | Confidence | Original ($WHISPER_MODEL) | Second reading ($RECHECK_MODEL) |"
  echo "| --- | ---: | --- | --- |"
  while IFS="$(printf '\t')" read -r from to conf text; do
    # half a second of context on each side, so the first and last word are not cut
    start=$(( from > 500 ? from - 500 : 0 ))
    length=$(( to - start + 500 ))
    second="$("$whisper_cli" --model "$recheck_model" --file "$wav" --language "$WHISPER_LANG" --threads "$WHISPER_THREADS" \
      --offset-t "$start" --duration "$length" --no-timestamps --no-prints ${prompt_args[@]+"${prompt_args[@]}"} 2>/dev/null \
      | tr '\n' ' ' | sed -E 's/^ +| +$//g; s/  +/ /g; s/\|/\\|/g')"
    s=$(( from / 1000 ))
    printf '| %02d:%02d | %s | %s | %s |\n' $(( s / 60 )) $(( s % 60 )) "$conf" "$(printf '%s' "$text" | sed 's/|/\\|/g')" "${second:-(nothing)}"
  done <<< "$low"
} > "$out"
echo "written $out"
