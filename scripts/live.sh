#!/usr/bin/env bash
# Live transcription from the microphone with whisper-stream; Ctrl+C stops it.
# --step 0 waits for a pause and transcribes the last utterance (up to --length ms) instead of a sliding window.
# The session is kept: the printed text in transcripts/live-<date>.txt and the audio in recordings/live-<date>.wav
# (16 kHz mono, from the full-quality recordings/originals/live-<date>.flac), recorded in parallel by the recorder
# of `just record` (whisper-stream's own --save-audio duplicates audio in this mode), so the take can be
# transcribed again offline with `just transcribe live-<date>`.
# Both programs listen to the same input: the macOS default one, or MIC_DEVICE (an index or a name from `just devices`).
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need_macos live.sh
[ -x "$whisper_stream" ] || die "whisper-stream missing (needs sdl2): run \`just deps\`, then \`just build\`"
need_model
need_tool ffmpeg
need_mic_capture
stamp="$(date +%Y-%m-%d-%H%M)"
mkdir -p "$transcripts_dir" "$originals_dir"
text_out="$transcripts_dir/live-$stamp.txt"
audio_out="$recordings_dir/live-$stamp.wav"
audio_take="$originals_dir/live-$stamp.wav"   # written by the recorder, then replaced by the FLAC

mic="$(mic_device)"
mic_name="$("$mic_capture_bin" resolve "$mic")" || die "no microphone to listen to (MIC_DEVICE='$MIC_DEVICE', see \`just devices\`)"
# whisper-stream numbers the inputs its own way (SDL): -1 is the macOS default input, and a chosen input is
# found by name in the list whisper-stream prints when it starts. A model path that does not exist makes it
# print that list and stop at once.
capture_id=-1
if [ -n "$MIC_DEVICE" ]; then
  stream_inputs="$("$whisper_stream" --model "$whisper_build/no-such-model" 2>&1 | sed -n "s/.*Capture device #\([0-9][0-9]*\): '\(.*\)'\$/\1 \2/p" || true)"
  capture_id="$(printf '%s\n' "$stream_inputs" | while read -r id stream_name; do
    if [ "$stream_name" = "$mic_name" ]; then echo "$id"; break; fi
  done)"
  [ -n "$capture_id" ] || die "whisper-stream does not list an input named '$mic_name'; it lists: $(printf '%s' "$stream_inputs" | tr '\n' ';')"
fi

# The recorder reads the same input in the background; macOS lets two programs read the microphone.
"$mic_capture_bin" record "$mic" "$audio_take" < /dev/null &
rec_pid=$!

cleanup() {
  # Ctrl+C already reached the recorder (same process group); this covers every other exit path.
  kill -INT "$rec_pid" 2>/dev/null || true
  wait "$rec_pid" 2>/dev/null || true
  echo
  if [ -s "$audio_take" ] && [ ! -e "$audio_out" ] && to_wav16k "$audio_take" "$audio_out"; then
    echo "audio saved to $audio_out ($(audio_seconds "$audio_out")s): offline transcript with \`just transcribe live-$stamp\`"
    echo "full quality: $(flac_original "$audio_take")"
  fi
  if [ -s "$text_out" ]; then echo "text saved to $text_out"; else rm -f "$text_out"; fi
  return 0
}
trap cleanup EXIT

echo "live transcription from $mic_name; Ctrl+C to stop"
"$whisper_stream" --model "$model_file" --language "$WHISPER_LANG" --threads "$WHISPER_THREADS" \
  --step 0 --length 30000 --vad-thold 0.6 --capture "$capture_id" --file "$text_out" "$@" || true
