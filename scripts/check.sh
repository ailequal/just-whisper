#!/usr/bin/env bash
# Report tools, Python, whisper.cpp version, binaries, models, prompt and microphones.
# Exit status 1 when something required is missing.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

status=0
if on_apple_silicon; then
  chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple Silicon')"
  if under_rosetta; then
    row macos "$(sw_vers -productVersion) on $chip, but this terminal runs under Rosetta (x86_64): open a native terminal"; status=1
  else
    row macos "$(sw_vers -productVersion) on $chip (arm64)"
  fi
  case "$(command -v brew 2>/dev/null)" in
    /opt/homebrew/*|"") ;;
    *) row homebrew "$(command -v brew) is the Intel Homebrew; expected /opt/homebrew/bin/brew on Apple Silicon"; status=1 ;;
  esac
else
  row platform "$(uname -s) $(uname -m): this project targets macOS on Apple Silicon, recording and the smoke test need macOS"
fi
row shell "${SHELL:-unknown} (login shell; the scripts run in bash through just, any login shell works)"
if command -v just >/dev/null; then row just "$(just --version | cut -d' ' -f2)"; else row just "missing: brew install just"; fi
for tool in uv cmake ffmpeg; do
  if command -v "$tool" >/dev/null; then
    row "$tool" "$("$tool" --version 2>&1 | head -1)"
  else
    row "$tool" "missing: run \`just deps\`"; status=1
  fi
done
if command -v swiftc >/dev/null && swift_version="$(swiftc --version 2>/dev/null | head -1)" && [ -n "$swift_version" ]; then
  row swiftc "$swift_version (builds the microphone recorder)"
else
  row swiftc "missing (only for \`just record\`, \`just live\` and \`just devices\`): xcode-select --install"
fi
if command -v uv >/dev/null; then
  if py="$(uv run --no-sync python -VV 2>/dev/null)"; then
    row python "$py (pinned $(cat .python-version), via uv)"
  else
    row python "not installed: run \`just python\`"; status=1
  fi
fi
if command -v node >/dev/null; then row node "$(node -v) (optional, Markdown formatting)"; else row node "missing (optional, only for \`just format-docs\`)"; fi
if command -v shellcheck >/dev/null; then row shellcheck "$(shellcheck --version | sed -n 's/^version: //p') (optional, \`just lint\`)"; else row shellcheck "missing (optional, only for \`just lint\`)"; fi

if whisper_checkout_present; then
  ref="$(whisper_version)"
  if ! whisper_is_submodule; then
    row whisper.cpp "$ref at $WHISPER_DIR (not the submodule, WHISPER_DIR is set)"
  elif whisper_pin_matches; then
    row whisper.cpp "$ref at $WHISPER_DIR (the recorded submodule commit)"
  else
    row whisper.cpp "$ref at $WHISPER_DIR: differs from the recorded $(whisper_name_of "$(whisper_pinned_commit)"), see \`just status\`"
  fi
else
  row whisper.cpp "missing: run \`just clone\`"; status=1
fi
if [ -x "$whisper_cli" ]; then
  row whisper-cli "$("$whisper_cli" --version 2>&1 | head -1 | sed 's/whisper.cpp version: //') ($whisper_cli)"
else
  row whisper-cli "missing: run \`just build\`"; status=1
fi
if [ -x "$whisper_stream" ]; then row whisper-stream "$whisper_stream"; else row whisper-stream "missing (optional, needs sdl2): run \`just deps\`, then \`just build\`"; fi
if [ -f "$model_file" ]; then row model "$model_file ($(du -h "$model_file" | cut -f1))"; else row model "missing: run \`just models\`"; status=1; fi
if [ -f "$vad_file" ]; then row vad-model "$vad_file"; else row vad-model "missing: run \`just models\`"; status=1; fi
row language "$WHISPER_LANG$([ -d "$lang_dir" ] || echo " (no config/lang/$WHISPER_LANG: no prompt, no fillers, no smoke test)")"
prompt_src="$(prompt_file)"
case "$prompt_src" in
  /dev/null) row prompt "none" ;;
  "$lang_dir/prompt.example.txt") row prompt "$prompt_src (generic example; \`just prompt\` creates your own)" ;;
  *) row prompt "$prompt_src" ;;
esac

echo "microphones (the default one is recorded; MIC_DEVICE picks another by index or name):"
scripts/devices.sh | sed 's/^/  /' || echo "  not listed: the microphone recorder could not be built"
exit "$status"
