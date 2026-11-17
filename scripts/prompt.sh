#!/usr/bin/env bash
# Create the personal vocabulary prompt for WHISPER_LANG from the tracked example, if it does not exist, and show it.
# The file is config/lang/<lang>/prompt.txt, git-ignored: list there the names and terms you want spelled right.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

example="$lang_dir/prompt.example.txt"
personal="$lang_dir/prompt.txt"
[ -d "$lang_dir" ] || die "no language directory for WHISPER_LANG=$WHISPER_LANG ($lang_dir): see config/lang/README.md"
if [ -f "$personal" ]; then
  echo "$personal exists:"
else
  [ -s "$example" ] || die "$example missing: see config/lang/README.md"
  cp "$example" "$personal"
  echo "created $personal from $example; edit it with the names and terms of your recordings:"
fi
sed 's/^/  /' "$personal"
echo "used by every transcription in '$WHISPER_LANG' (WHISPER_PROMPT=<file> picks another file, WHISPER_PROMPT=/dev/null none)"
