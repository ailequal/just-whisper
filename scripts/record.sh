#!/usr/bin/env bash
# Record the microphone: scripts/record.sh [name] [seconds]
# The take is written at full quality (the sample rate and channels of the device, 24-bit) to
# recordings/originals/<name>.wav, then converted to recordings/<name>.wav at 16 kHz mono for whisper.
# Without a duration, press q in the terminal to stop. The name defaults to the date and time.
# The recorder is scripts/mic-capture.swift: ffmpeg's avfoundation input loses audio while recording.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

given="${1:-$(date +%Y-%m-%d-%H%M)}"
name="$(slugify "$given")"
[ -n "$name" ] || die "cannot make a name out of '$given'"
[ "$name" = "$given" ] || echo "name: $name (from '$given')"
seconds="${2:-}"
need_macos record.sh
need_tool ffmpeg
mkdir -p "$recordings_dir"
out="$recordings_dir/$name.wav"
original="$originals_dir/$name.wav"
[ ! -e "$out" ] || die "$out already exists, pick another name"
[ ! -e "$original" ] || die "$original already exists, pick another name"
need_mic_capture
mkdir -p "$originals_dir"

duration_args=()
if [ -n "$seconds" ]; then
  duration_args=("$seconds")
  echo "recording $seconds s from device $MIC_DEVICE to $original"
else
  echo "recording from device $MIC_DEVICE to $original (press q to stop; Ctrl+C also keeps the file)"
fi
# The recorder closes the WAV on q, Ctrl+C and at the end of the duration; after an error keep what it wrote.
"$mic_capture_bin" record "$MIC_DEVICE" "$original" ${duration_args[@]+"${duration_args[@]}"} || true
[ -s "$original" ] || die "nothing recorded: $original is missing or empty (device $MIC_DEVICE, see \`just devices\`)"
to_wav16k "$original" "$out"
echo "saved $out ($(audio_seconds "$out")s, 16 kHz mono for whisper)"
echo "full quality: $original ($(audio_format "$original"))"
audio_level_report "$out"
