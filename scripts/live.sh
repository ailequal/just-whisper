#!/usr/bin/env bash
# Live transcription from the microphone with whisper-stream; Ctrl+C stops it.
# --step 0 waits for a pause and transcribes the last utterance (up to --length ms) instead of a sliding window.
# The session is kept: the printed text in transcripts/live-<date>.txt and the audio in recordings/live-<date>.wav
# (16 kHz mono, from the full-quality recordings/originals/live-<date>.wav), recorded in parallel by the recorder
# of `just record` (whisper-stream's own --save-audio duplicates audio in this mode), so the take can be
# transcribed again offline with `just transcribe live-<date>`.
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
audio_original="$originals_dir/live-$stamp.wav"

# The recorder reads the same input in the background; macOS lets two programs read the microphone.
"$mic_capture_bin" record "$MIC_DEVICE" "$audio_original" < /dev/null &
rec_pid=$!

cleanup() {
  # Ctrl+C already reached the recorder (same process group); this covers every other exit path.
  kill -INT "$rec_pid" 2>/dev/null || true
  wait "$rec_pid" 2>/dev/null || true
  echo
  if [ -s "$audio_original" ] && [ ! -e "$audio_out" ] && to_wav16k "$audio_original" "$audio_out"; then
    echo "audio saved to $audio_out ($(audio_seconds "$audio_out")s): offline transcript with \`just transcribe live-$stamp\`"
    echo "full quality: $audio_original"
  fi
  if [ -s "$text_out" ]; then echo "text saved to $text_out"; else rm -f "$text_out"; fi
  return 0
}
trap cleanup EXIT

echo "live transcription from device $MIC_DEVICE; Ctrl+C to stop"
"$whisper_stream" --model "$model_file" --language "$WHISPER_LANG" --threads "$WHISPER_THREADS" \
  --step 0 --length 30000 --vad-thold 0.6 --capture "$MIC_DEVICE" --file "$text_out" "$@" || true
