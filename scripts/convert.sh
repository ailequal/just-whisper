#!/usr/bin/env bash
# Convert any audio or video file to recordings/<name>.wav at 16 kHz mono: scripts/convert.sh <file> [name]
# The name defaults to the source file name without extension; names are made safe (lowercase, dashes). The source file is copied to
# recordings/originals/ (git-ignored) so the better-quality original survives when the app's copy is deleted.
# An existing recordings/<name>.wav is never overwritten: the script stops and asks for another name.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

src="${1:-}"
[ -n "$src" ] || die "usage: scripts/convert.sh <file> [name]"
[ -f "$src" ] || die "$src not found"
given="${2:-$(basename "$src" | sed -E 's/\.[^.]+$//')}"
name="$(slugify "$given")"
[ -n "$name" ] || die "cannot make a name out of '$given': give one as second argument"
[ "$name" = "$given" ] || echo "name: $name (from '$given')"
need_tool ffmpeg
mkdir -p "$recordings_dir"
out="$recordings_dir/$name.wav"
[ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" != "$(abspath "$out")" ] || die "$src is already $out: give another name"
# a recording is never overwritten: it may be a microphone take that exists nowhere else
[ ! -e "$out" ] || die "$out already exists: give another name as second argument, or transcribe it as it is with \`just transcribe $name\`"
to_wav16k "$src" "$out"
echo "saved $out ($(audio_seconds "$out")s)"
audio_level_report "$out"

originals_dir="$recordings_dir/originals"
case "$(cd "$(dirname "$src")" && pwd)" in
  "$(abspath "$recordings_dir")"|"$(abspath "$originals_dir")") ;;   # already ours, nothing to keep
  *)
    mkdir -p "$originals_dir"
    ext="$(basename "$src")"; case "$ext" in *.*) ext=".${ext##*.}" ;; *) ext="" ;; esac
    keep="$originals_dir/$name$ext"
    if [ -e "$keep" ]; then
      echo "original already kept at $keep"
    else
      cp "$src" "$keep"
      echo "original kept at $keep"
    fi
    ;;
esac
