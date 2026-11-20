#!/usr/bin/env bash
# Record the microphone: scripts/record.sh [name] [seconds]
# The take is recorded at full quality (the sample rate and channels of the device, 24-bit) and kept as
# recordings/originals/<name>.flac, lossless; recordings/<name>.wav at 16 kHz mono is derived from it for whisper.
# The input is the macOS default one, or MIC_DEVICE: an index or a name from `just devices`.
# Without a duration, press q in the terminal to stop; p or space pauses and resumes. With a duration, the
# seconds count recorded audio, so a pause does not shorten the take. The name defaults to the date and time.
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
take="$originals_dir/$name.wav"          # written by the recorder, then replaced by the FLAC
original="$originals_dir/$name.flac"
for existing in "$out" "$take" "$original"; do
  [ ! -e "$existing" ] || die "$existing already exists, pick another name"
done
need_mic_capture
mic="$(mic_device)"
mic_name="$("$mic_capture_bin" resolve "$mic")" || die "no microphone to record from (MIC_DEVICE='$MIC_DEVICE', see \`just devices\`)"
mkdir -p "$originals_dir"

duration_args=()
if [ -n "$seconds" ]; then
  duration_args=("$seconds")
  echo "recording $seconds s from $mic_name (p or space pauses and resumes)"
else
  echo "recording from $mic_name (p or space pauses and resumes, q stops; Ctrl+C also keeps the take)"
fi
# The recorder closes the WAV on q, Ctrl+C and at the end of the duration; after an error keep what it wrote.
"$mic_capture_bin" record "$mic" "$take" ${duration_args[@]+"${duration_args[@]}"} || true
[ -s "$take" ] || die "nothing recorded: $take is missing or empty (input: $mic_name, see \`just devices\`)"
to_wav16k "$take" "$out"
echo "saved $out ($(audio_seconds "$out")s, 16 kHz mono for whisper)"
kept="$(flac_original "$take")"
echo "full quality: $kept ($(audio_format "$kept"), $(file_size "$kept"))"
audio_level_report "$out"
