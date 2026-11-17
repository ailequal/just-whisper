#!/usr/bin/env bash
# Record the whisper.cpp commit checked out in the submodule as the project's pin, in a commit of this
# repository. Refuses when the smoke test has not run on the current build of that commit.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

whisper_is_submodule || die "WHISPER_DIR=$WHISPER_DIR is not the submodule $whisper_submodule: nothing to pin"
need_checkout
head="$(git -C "$WHISPER_DIR" rev-parse HEAD)"
name="$(whisper_name_of "$head")"
recorded="$(whisper_pinned_commit)"
if [ "$head" = "$recorded" ] && git diff --quiet HEAD -- "$whisper_submodule" 2>/dev/null; then
  echo "already pinned to $name ($(git -C "$WHISPER_DIR" rev-parse --short HEAD))"
  exit 0
fi
[ -z "$(git -C "$WHISPER_DIR" status --porcelain)" ] || die "$WHISPER_DIR has local changes: the pin must be a clean upstream commit"
if [ ! -f "$smoke_marker" ] || [ "$(cat "$smoke_marker")" != "$head" ]; then
  die "the smoke test has not run on this build of $name: run \`just build\` and \`just test\` first (\`just upgrade $name\` does all three)"
fi
old="$(whisper_name_of "${recorded:-HEAD}")"
git add "$whisper_submodule"
git commit -m "chore(whisper): pin whisper.cpp to $name" \
  -m "Move the vendor/whisper.cpp submodule from $old to $name. Built in Release mode with Metal and checked with the smoke test (WHISPER_LANG=$WHISPER_LANG) on this machine."
echo "pinned $name; update the version named in README.md and GUIDE.md if it changed"
