#!/usr/bin/env bash
# Smoke test of the whole chain: synthesize the sentence of config/lang/$WHISPER_LANG/smoke-test.txt with a
# macOS voice of that language, then run it through convert, transcribe, stats, export and export-all, and
# check that the expected word is in the text and that every output file is there.
# The chain runs in a temporary directory (WHISPER_RECORDINGS_DIR, WHISPER_TRANSCRIPTS_DIR): nothing is
# written to recordings/ or transcripts/.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need_cli
need_model
need_tool ffmpeg
need_tool uv
need_macos test.sh
need_tool say
[ -f "$vad_file" ] || die "VAD model missing at $vad_file: run \`just models\`"
[ -s "$smoke_file" ] || die "no smoke test for WHISPER_LANG=$WHISPER_LANG ($smoke_file missing): run it as WHISPER_LANG=en just test, or add the language (config/lang/README.md)"
sentence="$(sed -n 1p "$smoke_file")"
expected="$(sed -n 2p "$smoke_file")"
[ -n "$sentence" ] && [ -n "$expected" ] || die "$smoke_file needs two lines: the sentence, then the expected word"
# first installed voice of the language (it_IT, en_US, en_GB, ...); the voice list is "Name  lang  # sample"
voice="$(say -v '?' | awk -v l="${WHISPER_LANG}_" 'index($2, l) == 1 { print $1; exit }')"
[ -n "$voice" ] || die "no macOS voice for '$WHISPER_LANG': System Settings, Accessibility, Spoken Content, System Voice, Manage Voices"
tmp="$(mktemp -d -t whisper-test)"
trap 'rm -rf "$tmp"' EXIT

# The scripts below read these two settings, so the whole chain stays inside the temporary directory.
export WHISPER_RECORDINGS_DIR="$tmp/recordings" WHISPER_TRANSCRIPTS_DIR="$tmp/transcripts"
name=smoke
out="$WHISPER_TRANSCRIPTS_DIR/$name"
chain_log="$tmp/chain.log"
# Run one step of the chain quietly; on failure show what it printed and stop.
step() {
  "$@" >> "$chain_log" 2>&1 || { cat "$chain_log" >&2; die "smoke test failed at: $*"; }
}

say -v "$voice" -o "$tmp/$name.aiff" "$sentence"
step scripts/convert.sh "$tmp/$name.aiff" "$name"
step scripts/transcribe.sh "$name"
step scripts/stats.sh "$name"
step scripts/export-all.sh

cat "$out.timestamps.txt"
grep -qi -- "$expected" "$out.txt" || die "smoke test failed: expected the word '$expected' in the transcript"
for ext in txt srt json log md timestamps.txt; do
  [ -s "$out.$ext" ] || die "smoke test failed: $name.$ext was not written"
done
[ -s "$WHISPER_TRANSCRIPTS_DIR/INDEX.md" ] || die "smoke test failed: INDEX.md was not written"
echo "ok: whisper-cli $("$whisper_cli" --version 2>&1 | sed 's/whisper.cpp version: //') transcribes '$WHISPER_LANG' (voice $voice); convert, transcribe, stats and export passed"
# remembered by `just pin` and `just status`: this build of this commit passed
git -C "$WHISPER_DIR" rev-parse HEAD > "$smoke_marker" 2>/dev/null || true
