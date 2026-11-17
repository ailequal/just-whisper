#!/usr/bin/env bash
# Transcribe recordings/<name>.wav to transcripts/<name>.{txt,srt,json,log}: scripts/transcribe.sh <name> [whisper-cli flags...]
# Defaults: WHISPER_LANG, beam search (whisper-cli default), Silero VAD with 500 ms padding, the vocabulary
# prompt of the language (see prompt_file in lib/common.sh), full JSON with token probabilities.
# WHISPER_VERBATIM=1 surrounds the prompt with the language's fillers so whisper keeps hesitations.
# Extra flags are appended and override the defaults.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

name="${1:-}"
[ -n "$name" ] || die "usage: scripts/transcribe.sh <name> [whisper-cli flags...]"
shift
in="$recordings_dir/$name.wav"
[ -f "$in" ] || die "$in not found: record with \`just record $name\` or convert with \`just convert <file> $name\`"
need_cli
need_model
[ -f "$vad_file" ] || die "VAD model missing at $vad_file: run \`just models\`"
mkdir -p "$transcripts_dir"
out="$transcripts_dir/$name"
[ ! -f "$out.txt" ] || echo "overwriting $out.{txt,srt,json,log} from a previous run"

prompt_src="$(prompt_file)"
prompt_text=""
[ -s "$prompt_src" ] && prompt_text="$(tr '\n' ' ' < "$prompt_src")"
if [ "$WHISPER_VERBATIM" = 1 ]; then
  [ -s "$fillers_file" ] || die "no fillers list for WHISPER_LANG=$WHISPER_LANG at $fillers_file (see config/lang/README.md)"
  fillers="$(paste -sd ',' "$fillers_file" | sed 's/,/, /g')"
  prompt_text="$fillers... $prompt_text $fillers."
fi
prompt_args=()
[ -n "$prompt_text" ] && prompt_args=(--prompt "$prompt_text")

# The log starts with what produced the transcript, so any take can be reproduced later.
{
  echo "# transcribed on $(date '+%Y-%m-%d %H:%M:%S') by scripts/transcribe.sh"
  echo "# whisper.cpp $(whisper_version) ($("$whisper_cli" --version 2>&1 | sed 's/whisper.cpp version: //'))"
  echo "# model $model_file ($(du -h "$model_file" | cut -f1)), vad $vad_file"
  echo "# prompt $prompt_src ($([ -s "$prompt_src" ] && echo used || echo none)$([ "$WHISPER_VERBATIM" = 1 ] && echo ", verbatim: fillers added")), language $WHISPER_LANG, threads $WHISPER_THREADS"
  if [ $# -gt 0 ]; then printf '# extra flags:'; printf ' %q' "$@"; echo; else echo "# extra flags: none"; fi
} > "$out.log"

# ${arr[@]+"${arr[@]}"} expands to nothing for an empty array under `set -u` on bash 3.2.
"$whisper_cli" \
  --model "$model_file" \
  --file "$in" \
  --language "$WHISPER_LANG" \
  --threads "$WHISPER_THREADS" \
  --vad --vad-model "$vad_file" --vad-speech-pad-ms 500 \
  --print-progress \
  --output-txt --output-srt --output-json-full \
  --output-file "$out" \
  ${prompt_args[@]+"${prompt_args[@]}"} \
  "$@" \
  2> >(tee -a "$out.log" >&2)
echo
echo "written: $out.txt $out.srt $out.json (log: $out.log)"
if [ ! -s "$out.txt" ] || ! grep -q '[[:alnum:]]' "$out.txt"; then
  echo "warning: no speech detected in $in (silent file, or nothing above the VAD threshold)" >&2
fi
