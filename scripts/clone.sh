#!/usr/bin/env bash
# Get the whisper.cpp source: initialize the submodule vendor/whisper.cpp at the recorded commit.
# With WHISPER_DIR pointing elsewhere, clone there and check out WHISPER_REF instead.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

if whisper_checkout_present; then
  echo "whisper.cpp already present at $WHISPER_DIR ($(whisper_version))"
  exit 0
fi
if whisper_is_submodule; then
  echo "fetching the submodule $whisper_submodule (about 50 MB of history)"
  git submodule update --init "$whisper_submodule"
else
  [ -n "$WHISPER_REF" ] || die "WHISPER_DIR=$WHISPER_DIR is not the submodule: set WHISPER_REF to the release to check out"
  git clone "$WHISPER_REPO" "$WHISPER_DIR"
  scripts/checkout.sh "$WHISPER_REF"
fi
echo "whisper.cpp at $WHISPER_DIR: $(whisper_version) ($(git -C "$WHISPER_DIR" rev-parse --short HEAD))"
