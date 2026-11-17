#!/usr/bin/env bash
# Duration, speaking time, words, pace, pauses, filler words and low-confidence segments of transcripts/<name>.json.
# The fillers list is the one of the language recorded in the transcript (config/lang/<code>/fillers.txt).
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

name="${1:-}"
[ -n "$name" ] || die "usage: scripts/stats.sh <name>"
json="$transcripts_dir/$name.json"
[ -f "$json" ] || die "$json not found: run \`just transcribe $name\` first"
need_tool uv

# STATS_TARGET_WPM is optional: with it, the pace is compared with that target.
target_args=()
[ -n "$STATS_TARGET_WPM" ] && target_args=(--target-wpm "$STATS_TARGET_WPM")
uv run python -I "$stats_script" "$json" --lang-root "$lang_root" --low-confidence "$LOW_CONFIDENCE" ${target_args[@]+"${target_args[@]}"}
