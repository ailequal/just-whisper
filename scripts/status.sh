#!/usr/bin/env bash
# Where whisper.cpp stands: checkout, recorded commit, newest release upstream, build and smoke test state, models.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need_checkout
head="$(git -C "$WHISPER_DIR" rev-parse HEAD)"
row checkout "$(whisper_version) ($(git -C "$WHISPER_DIR" rev-parse --short HEAD)) at $WHISPER_DIR"
if whisper_is_submodule; then
  recorded="$(whisper_pinned_commit)"
  if [ -z "$recorded" ]; then
    row recorded "nothing: run \`just pin\`"
  elif [ "$head" = "$recorded" ]; then
    row recorded "$(whisper_name_of "$recorded"), same as the checkout"
  else
    row recorded "$(whisper_name_of "$recorded") (${recorded:0:8}): the checkout differs, \`just pin\` records it, \`just checkout\` goes back"
  fi
  if git -C "$WHISPER_DIR" log -1 --format=%ad --date=short "$head" >/dev/null 2>&1; then
    row date "$(git -C "$WHISPER_DIR" log -1 --format=%ad --date=short "$head") (commit date)"
  fi
  latest="$(whisper_latest_release)"
  pinned_name="$(whisper_name_of "${recorded:-$head}")"
  if [ -z "$latest" ]; then
    row latest "could not read the upstream tags (offline?)"
  elif [ "$latest" = "$pinned_name" ]; then
    row latest "$latest, the recorded commit is the newest release"
  else
    row latest "$latest is newer than the recorded $pinned_name: \`just upgrade $latest\`, then \`just pin\`"
  fi
else
  row recorded "not the submodule: WHISPER_DIR=$WHISPER_DIR"
fi
if [ -z "$(git -C "$WHISPER_DIR" status --porcelain)" ]; then row tree clean; else row tree "local changes in $WHISPER_DIR"; fi
if [ -x "$whisper_cli" ]; then
  built="$("$whisper_cli" --version 2>&1 | head -1 | sed 's/whisper.cpp version: //')"
  if [ -f "$smoke_marker" ] && [ "$(cat "$smoke_marker")" = "$head" ]; then
    row build "whisper-cli $built, smoke test passed on this commit"
  else
    row build "whisper-cli $built, smoke test not run on this commit: \`just test\`"
  fi
else
  row build "missing: \`just build\`"
fi
for f in "$model_file" "$vad_file"; do
  if [ -f "$f" ]; then row model "$f ($(du -h "$f" | cut -f1))"; else row model "missing $f: \`just models\`"; fi
done
coreml="$WHISPER_MODELS_DIR/ggml-$WHISPER_MODEL-encoder.mlmodelc"
if [ -d "$coreml" ]; then row coreml "$coreml"; fi
