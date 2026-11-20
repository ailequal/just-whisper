#!/usr/bin/env bash
# List the audio input devices the recorder sees, one "[index] name" per line.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need_macos devices.sh
need_mic_capture
"$mic_capture_bin" devices
