#!/usr/bin/env bash
# List the whisper.cpp release tags (newest first), the current checkout and how far master is ahead.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need_checkout
git -C "$WHISPER_DIR" fetch --quiet --tags origin
pinned="$(whisper_pinned_commit)"
if [ -n "$pinned" ]; then pinned="$(whisper_name_of "$pinned")"; else pinned=none; fi
echo "checked out: $(whisper_version) ($(git -C "$WHISPER_DIR" rev-parse --short HEAD)), recorded for the submodule: $pinned"
echo "releases:"
latest=""
for tag in $(git -C "$WHISPER_DIR" tag --sort=-creatordate | grep -E '^v[0-9]' | head -10); do
  [ -n "$latest" ] || latest="$tag"
  printf '  %-10s %s\n' "$tag" "$(git -C "$WHISPER_DIR" log -1 --format=%ad --date=short "$tag")"
done
ahead="$(git -C "$WHISPER_DIR" rev-list "$latest..origin/master" --count)"
echo "master:      $(git -C "$WHISPER_DIR" log -1 --format='%ad %h' --date=short origin/master), $ahead commits after $latest"
