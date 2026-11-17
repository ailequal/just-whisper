#!/usr/bin/env bash
# Download the ggml speech model (WHISPER_MODEL) and the VAD model (WHISPER_VAD) into WHISPER_MODELS_DIR
# with the upstream scripts, then verify the speech model against the SHA-1 published by whisper.cpp.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need_checkout
mkdir -p "$WHISPER_MODELS_DIR"
sh "$WHISPER_DIR/models/download-ggml-model.sh" "$WHISPER_MODEL" "$WHISPER_MODELS_DIR"
sh "$WHISPER_DIR/models/download-vad-model.sh" "$WHISPER_VAD" "$WHISPER_MODELS_DIR"
ls -lh "$model_file" "$vad_file"

# The download script does not verify anything. Compare with the SHA-1 table in models/README.md
# (rows look like: | large-v3-turbo | 1.5 GiB | `4af2b29d...` |).
expected="$(awk -F'|' -v m="$WHISPER_MODEL" '
  { gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 == m) { gsub(/[` \t]/, "", $4); print $4; exit } }
' "$WHISPER_DIR/models/README.md")"
if [ -z "$expected" ]; then
  echo "checksum: no published SHA-1 for $WHISPER_MODEL in $WHISPER_DIR/models/README.md, skipped"
else
  actual="$(sha1_of "$model_file")"
  if [ "$actual" = "$expected" ]; then
    echo "checksum: $model_file matches models/README.md ($expected)"
  else
    die "checksum mismatch for $model_file: got $actual, expected $expected. Delete the file and run \`just models\` again"
  fi
fi
