#!/usr/bin/env bash
# Record the microphone to recordings/<name>.wav at 16 kHz mono: scripts/record.sh [name] [seconds]
# Without a duration, press q in the terminal to stop. The name defaults to the date and time.
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
[ ! -e "$out" ] || die "$out already exists, pick another name"

duration_args=()
if [ -n "$seconds" ]; then
  duration_args=(-t "$seconds")
  echo "recording $seconds s from device $MIC_DEVICE to $out"
else
  echo "recording from device $MIC_DEVICE to $out (press q to stop; Ctrl+C also keeps the file)"
fi
# ffmpeg exits with 255 when stopped by Ctrl+C and still finalizes the WAV: keep going and inspect the file.
ffmpeg -hide_banner -loglevel warning -stats -f avfoundation -i ":$MIC_DEVICE" \
  ${duration_args[@]+"${duration_args[@]}"} -ar 16000 -ac 1 -c:a pcm_s16le "$out" || true
[ -s "$out" ] || die "nothing recorded: $out is missing or empty (device $MIC_DEVICE, see \`just devices\`)"
echo "saved $out ($(audio_seconds "$out")s)"
audio_level_report "$out"
