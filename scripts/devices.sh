#!/usr/bin/env bash
# List the audio input devices ffmpeg can record from, one "[index] name" per line.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need_macos devices.sh
need_tool ffmpeg
# ffmpeg exits non-zero after listing because "" is not an input: the list is what we want.
ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
  | sed -n '/AVFoundation audio devices/,$p' \
  | grep -E '^\[AVFoundation.*\] \[[0-9]+\]' \
  | sed -E 's/.*(\[[0-9]+\].*)/\1/' || true
