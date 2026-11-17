#!/usr/bin/env bash
# Measure the model speed on this machine with whisper-bench.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

[ -x "$whisper_bench" ] || die "whisper-bench missing: run \`just build\`"
need_model
"$whisper_bench" --model "$model_file" --threads "$WHISPER_THREADS" "$@"
