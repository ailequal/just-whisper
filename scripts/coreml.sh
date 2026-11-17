#!/usr/bin/env bash
# Generate the Core ML encoder for WHISPER_MODEL and rebuild whisper.cpp with WHISPER_COREML=1.
# Needs the full Xcode app (coremlc). uv runs the converter with COREML_PYTHON in a throwaway environment.
# The upstream script writes into the source tree; the result is moved next to our ggml model, where
# whisper looks for it (<model>-encoder.mlmodelc beside <model>.bin).
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need_checkout
need_model
xcrun -f coremlc >/dev/null 2>&1 || die "coremlc not found: install Xcode from the App Store and run \`sudo xcode-select -s /Applications/Xcode.app\`"
need_tool uv
need_tool cmake

(
  cd "$WHISPER_DIR" || exit 1
  uv run --no-project --python "$COREML_PYTHON" \
    --with-requirements models/requirements-coreml.txt \
    sh ./models/generate-coreml-model.sh "$WHISPER_MODEL"
)
generated="$WHISPER_DIR/models/ggml-$WHISPER_MODEL-encoder.mlmodelc"
target="$WHISPER_MODELS_DIR/ggml-$WHISPER_MODEL-encoder.mlmodelc"
[ -d "$generated" ] || die "expected $generated after the conversion, not found"
rm -rf "$target"
mv "$generated" "$target"
rm -rf "$WHISPER_DIR/models/coreml-encoder-$WHISPER_MODEL.mlpackage"
echo "Core ML encoder at $target"
cmake -S "$WHISPER_DIR" -B "$whisper_build" -DCMAKE_BUILD_TYPE=Release -DWHISPER_COREML=1
cmake --build "$whisper_build" -j --config Release
echo "done: the first transcription compiles the Core ML model for this device and is slow, the next ones are fast"
