#!/usr/bin/env bash
# Check out a whisper.cpp ref in WHISPER_DIR: scripts/checkout.sh [ref]
# Default: WHISPER_REF when set, else the commit recorded for the submodule (back to the pin).
# A branch is switched to and fast-forwarded; a tag or commit is checked out detached.
# Moving the submodule changes nothing in this repository until `just pin` records the new commit.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ref="${1:-$WHISPER_REF}"
need_checkout
if [ -z "$ref" ]; then
  whisper_is_submodule || die "no ref given and $WHISPER_DIR is not the submodule: scripts/checkout.sh <ref>"
  ref="$(whisper_pinned_commit)"
  [ -n "$ref" ] || die "no commit recorded for $whisper_submodule: scripts/checkout.sh <ref>"
  echo "returning to the recorded commit $(whisper_name_of "$ref")"
fi
cd "$WHISPER_DIR" || die "cannot enter $WHISPER_DIR"

if [ -n "$(git status --porcelain)" ]; then
  git status --short >&2
  die "$WHISPER_DIR has local changes (above): commit or stash them before switching"
fi
git fetch --quiet --tags origin

if git show-ref --verify --quiet "refs/heads/$ref" || git show-ref --verify --quiet "refs/remotes/origin/$ref"; then
  # a branch (master): follow it and fast-forward to origin
  git switch "$ref"
  git pull --quiet --ff-only origin "$ref"
elif git show-ref --verify --quiet "refs/tags/$ref" || git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
  # a release tag or a commit: detached checkout, nothing moves under you
  git -c advice.detachedHead=false switch --detach "$ref"
else
  die "unknown ref '$ref': see \`just versions\`"
fi
cd "$repo_root" || exit 1
echo "whisper.cpp is now at $(whisper_version) ($(git -C "$WHISPER_DIR" rev-parse --short HEAD)); run \`just build\` (or \`just upgrade $(whisper_name_of "$ref")\` does both)"
if whisper_is_submodule && ! whisper_pin_matches; then
  echo "the recorded commit is still $(whisper_name_of "$(whisper_pinned_commit)"): after \`just test\`, record this one with \`just pin\`"
fi
