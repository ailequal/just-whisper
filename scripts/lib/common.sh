#!/usr/bin/env bash
# Shared configuration and helpers for the scripts in scripts/.
# Sourced by every script, never executed directly. Compatible with bash 3.2 (macOS /bin/bash).
#
# Every setting is an environment variable with a default; override it in the shell:
#   WHISPER_DIR=../whisper.cpp scripts/build.sh
#   MIC_DEVICE="USB Microphone" scripts/record.sh take1
# The justfile passes nothing extra: `just transcribe x` and `scripts/transcribe.sh x` are the same.
#
# whisper.cpp is the git submodule vendor/whisper.cpp. The commit recorded for the submodule is the pin:
# `just checkout` returns to it, `just check` compares HEAD with it, `just pin` records a new one.

# shellcheck disable=SC2034  # a library: its variables are used by the scripts that source it

# The scripts are bash. Started by just or by their shebang they always are; `zsh scripts/x.sh` or
# `sh scripts/x.sh` would fail later with a confusing error, so stop here with a clear one.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "scripts/*.sh are bash scripts: run them as scripts/<name>.sh or with bash, not with zsh or sh" >&2
  exit 1
fi

set -euo pipefail

# All scripts run from the repository root, so relative paths below are stable.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

# --- settings ---------------------------------------------------------------
whisper_submodule="vendor/whisper.cpp"           # where the submodule is recorded (fixed, see .gitmodules)
: "${WHISPER_DIR:=$whisper_submodule}"          # whisper.cpp source checkout; another path for experiments
: "${WHISPER_REPO:=https://github.com/ggml-org/whisper.cpp.git}"
: "${WHISPER_REF:=}"                            # ref for checkout/upgrade; empty means the recorded submodule commit
: "${WHISPER_MODELS_DIR:=models}"               # where the ggml models live (outside the source tree)
: "${WHISPER_RECORDINGS_DIR:=recordings}"       # where the 16 kHz WAV recordings live (full-quality originals in originals/)
: "${WHISPER_TRANSCRIPTS_DIR:=transcripts}"     # where the transcripts and exports are written
: "${WHISPER_MODEL:=large-v3-turbo}"            # ggml model name
: "${WHISPER_VAD:=silero-v6.2.0}"               # VAD model name
: "${WHISPER_LANG:=en}"                         # spoken language code (en, it, fr, de, ...), or auto
: "${WHISPER_THREADS:=8}"                       # CPU threads for whisper
: "${WHISPER_PROMPT:=}"                         # vocabulary prompt file; empty: the language's prompt.txt or prompt.example.txt, /dev/null disables
: "${WHISPER_VERBATIM:=0}"                      # 1: surround the prompt with the language's fillers so whisper keeps them
: "${LOW_CONFIDENCE:=0.6}"                      # segments with a mean token probability below this are marked in stats and export
: "${RECHECK_MODEL:=large-v3}"                  # full model used by `just recheck` on the low-confidence segments
: "${MIC_DEVICE:=}"                             # audio input: empty follows the macOS default input; or an index or a name from `just devices`
: "${COREML_PYTHON:=3.13}"                      # newest Python supported by coremltools
: "${STATS_TARGET_WPM:=}"                       # optional target pace in words per minute for `just stats`; empty: no comparison

# --- derived paths ------------------------------------------------------------
recordings_dir="$WHISPER_RECORDINGS_DIR"
originals_dir="$recordings_dir/originals"        # full-quality microphone takes (FLAC) and the sources of `just convert`
transcripts_dir="$WHISPER_TRANSCRIPTS_DIR"
stats_script="scripts/transcript-stats.py"
mic_capture_src="scripts/mic-capture.swift"      # the microphone recorder, compiled on first use
mic_capture_bin=".build/mic-capture"
lang_root="config/lang"                          # one directory per language code, see config/lang/README.md
lang_dir="$lang_root/$WHISPER_LANG"
fillers_file="$lang_dir/fillers.txt"
smoke_file="$lang_dir/smoke-test.txt"
whisper_build="$WHISPER_DIR/build"
whisper_cli="$whisper_build/bin/whisper-cli"
whisper_stream="$whisper_build/bin/whisper-stream"
whisper_bench="$whisper_build/bin/whisper-bench"
model_file="$WHISPER_MODELS_DIR/ggml-$WHISPER_MODEL.bin"
vad_file="$WHISPER_MODELS_DIR/ggml-$WHISPER_VAD.bin"
smoke_marker="$whisper_build/.smoke-tested"      # written by test.sh with the commit it tested

# --- helpers ------------------------------------------------------------------
die() { printf '%s\n' "$*" >&2; exit 1; }
# Absolute form of a path that may be relative to the repository root.
abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$repo_root" "$1" ;; esac; }
row() { printf '%-14s %s\n' "$1" "$2"; }

need_tool() { command -v "$1" >/dev/null 2>&1 || die "$1 is missing: run \`just deps\`"; }
need_cli() { [ -x "$whisper_cli" ] || die "whisper-cli missing at $whisper_cli: run \`just build\`"; }
need_model() { [ -f "$model_file" ] || die "model missing at $model_file: run \`just models\`"; }
# True when WHISPER_DIR is the top of its own git checkout. A submodule has a .git file, not a directory,
# and an uninitialized one is an empty directory inside this repository, where git would answer for the
# parent: so compare the toplevel git reports with the directory itself.
whisper_checkout_present() {
  local dir top
  dir="$(cd "$WHISPER_DIR" 2>/dev/null && pwd -P)" || return 1
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ "$top" = "$dir" ]
}
need_checkout() { whisper_checkout_present || die "whisper.cpp checkout missing at $WHISPER_DIR: run \`just clone\`"; }

# Build the microphone recorder when it is missing or older than its source. The Swift compiler
# comes with the Xcode Command Line Tools.
need_mic_capture() {
  [ "$mic_capture_bin" -nt "$mic_capture_src" ] && return 0
  command -v swiftc >/dev/null 2>&1 || die "swiftc is missing: install the Xcode Command Line Tools with \`xcode-select --install\`"
  echo "building the microphone recorder $mic_capture_bin (once)" >&2
  mkdir -p "$(dirname "$mic_capture_bin")"
  swiftc -O -o "$mic_capture_bin" "$mic_capture_src" || die "cannot build $mic_capture_src: check the Xcode Command Line Tools with \`just deps check\`"
}

# What the recorder is asked to record from: MIC_DEVICE, or the macOS default input when it is empty.
mic_device() { printf '%s\n' "${MIC_DEVICE:-default}"; }

# The recording, playback and text-to-speech steps use macOS frameworks and tools.
need_macos() { [ "$(uname -s)" = Darwin ] || die "$1 needs macOS (avfoundation, say): this project targets Apple Silicon Macs"; }
# True when the process runs natively on Apple Silicon (not Intel, not under Rosetta).
on_apple_silicon() { [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]; }
# True when the shell runs translated by Rosetta on an Apple Silicon Mac.
under_rosetta() { [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; }

# Version of the whisper.cpp checkout, as git describes it (v1.9.5, v1.9.5-135-g21ba6d26, or a hash).
whisper_version() { git -C "$WHISPER_DIR" describe --tags --always 2>/dev/null; }
# True when HEAD is exactly on a tag.
whisper_on_tag() { git -C "$WHISPER_DIR" describe --tags --exact-match >/dev/null 2>&1; }
# True when WHISPER_DIR is the submodule of this repository (the default) and not another checkout.
whisper_is_submodule() { [ "$(abspath "$WHISPER_DIR")" = "$repo_root/$whisper_submodule" ]; }
# The commit recorded for the submodule in the index (what is, or is about to be, committed). Empty if none.
whisper_pinned_commit() { git ls-files -s "$whisper_submodule" 2>/dev/null | awk '$1 == "160000" { print $2 }'; }
# Name of a commit: its exact tag when it has one, else the short hash.
whisper_name_of() { git -C "$WHISPER_DIR" describe --tags --exact-match "$1" 2>/dev/null || git -C "$WHISPER_DIR" rev-parse --short "$1" 2>/dev/null || echo "$1"; }
# True when the checkout is at the recorded commit.
whisper_pin_matches() { [ "$(git -C "$WHISPER_DIR" rev-parse HEAD 2>/dev/null)" = "$(whisper_pinned_commit)" ]; }

# Duration of an audio file in whole seconds.
audio_seconds() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" | awk '{ printf "%d", $1 + 0.5 }'; }

# Sample rate and channel count of an audio file, for example "48000 Hz, 1 ch".
audio_format() { ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate,channels -of csv=p=0 "$1" | awk -F, '{ printf "%s Hz, %s ch", $1, $2 }'; }

# MD5 of the decoded samples of an audio file: two files with the same value hold the same audio.
audio_md5() { ffmpeg -hide_banner -loglevel error -i "$1" -map 0:a:0 -c:a pcm_s32le -f md5 - 2>/dev/null; }

# Replace the full-quality WAV take "$1" with a FLAC next to it and print the path of the file that is kept.
# FLAC is lossless and about half the size. The WAV is removed only after the FLAC decodes to exactly the
# same samples; on any failure the WAV stays and is the file kept.
flac_original() {
  local wav="$1" flac="${1%.wav}.flac" part="${1%.wav}.part.flac" want got
  if [ ! -e "$flac" ] \
    && ffmpeg -hide_banner -loglevel error -y -i "$wav" -map 0:a:0 -c:a flac -compression_level 8 "$part" 2>/dev/null \
    && want="$(audio_md5 "$wav")" && got="$(audio_md5 "$part")" \
    && [ -n "$want" ] && [ "$want" = "$got" ] \
    && mv "$part" "$flac" && rm -f "$wav"; then
    printf '%s\n' "$flac"
  else
    [ ! -f "$part" ] || rm -f "$part"
    echo "warning: $wav was not compressed to FLAC, the WAV is kept" >&2
    printf '%s\n' "$wav"
  fi
}

# Size of a file for a person, for example 4.8M.
file_size() { du -h "$1" | cut -f1 | tr -d ' '; }

# Convert any audio or video file to the 16 kHz mono 16-bit WAV that whisper-cli reads.
to_wav16k() { ffmpeg -hide_banner -loglevel error -y -i "$1" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$2"; }

# Mean loudness of a file in dBFS, as measured by ffmpeg's volumedetect (for example -28.3).
audio_mean_db() { ffmpeg -hide_banner -nostats -i "$1" -af volumedetect -f null - 2>&1 | sed -n 's/.*mean_volume: \([-0-9.]*\) dB.*/\1/p'; }

# Print the level of a recording and warn when it is close to silence: a denied microphone
# permission or a muted input records silence without any error.
audio_level_report() {
  local mean
  mean="$(audio_mean_db "$1")"
  [ -n "$mean" ] || { echo "level: could not measure"; return 0; }
  if awk -v m="$mean" 'BEGIN { exit !(m < -50) }'; then
    echo "level: ${mean} dB mean, almost silent. Check the input volume in System Settings, Sound, and the" >&2
    echo "       microphone permission of your terminal app in System Settings, Privacy & Security, Microphone." >&2
  else
    echo "level: ${mean} dB mean (speech is usually between -35 and -20 dB)"
  fi
}

# SHA-1 of a file, as published in whisper.cpp's models/README.md.
sha1_of() { shasum "$1" | cut -d' ' -f1; }

# The vocabulary prompt file to use: WHISPER_PROMPT when set, else the personal prompt.txt of the
# language, else its tracked prompt.example.txt, else /dev/null (no prompt).
prompt_file() {
  if [ -n "$WHISPER_PROMPT" ]; then printf '%s\n' "$WHISPER_PROMPT"
  elif [ -s "$lang_dir/prompt.txt" ]; then printf '%s\n' "$lang_dir/prompt.txt"
  elif [ -s "$lang_dir/prompt.example.txt" ]; then printf '%s\n' "$lang_dir/prompt.example.txt"
  else printf '%s\n' /dev/null
  fi
}

# A safe recording name: lowercase ASCII letters, digits, dot, underscore and dash; everything else becomes a dash.
# Names end up in file paths, in whisper-cli arguments and in commands printed for copy and paste.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/-+/-/g; s/^[-.]+//; s/[-.]+$//'
}

# Newest release tag upstream (needs network); empty when it cannot be read.
whisper_latest_release() {
  GIT_TERMINAL_PROMPT=0 git -C "$WHISPER_DIR" ls-remote --tags --refs origin 'v[0-9]*' 2>/dev/null | sed 's#.*/##' | sort -V | tail -1
}
