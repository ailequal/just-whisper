#!/usr/bin/env bash
# Any audio or video file to text in one go: scripts/transcribe-file.sh <file> [name] [whisper-cli flags...]
# Runs convert, transcribe and export, and prints the paths. The name defaults to the file name, made safe.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

src="${1:-}"
[ -n "$src" ] || die "usage: scripts/transcribe-file.sh <file> [name] [whisper-cli flags...]"
[ -f "$src" ] || die "$src not found"
given="${2:-$(basename "$src" | sed -E 's/\.[^.]+$//')}"
name="$(slugify "$given")"
[ -n "$name" ] || die "cannot make a name out of '$given': give one as second argument"
[ "$name" = "$given" ] || echo "name: $name (from '$given')"
# drop <file> and [name] (the justfile always passes both, name possibly empty)
if [ $# -ge 2 ]; then shift 2; else shift $#; fi

scripts/convert.sh "$src" "$name"
scripts/transcribe.sh "$name" "$@"
scripts/export.sh "$name"
echo
echo "text:   $transcripts_dir/$name.txt"
echo "export: $transcripts_dir/$name.md"
