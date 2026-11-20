# Project commands for local speech-to-text with whisper.cpp. Run `just` to list them.
# Requires just 1.27 or later (recipe groups and doc attributes).
#
# The justfile is a launcher: every recipe with logic calls the script of the same name in
# scripts/ (rebuild, transcribe-verbatim, setup and upgrade reuse other recipes or scripts), and the
# scripts run on their own too (scripts/transcribe.sh take1). The few inline recipes are one-liners.
# Settings are environment variables with their defaults in scripts/lib/common.sh; README.md lists them.
# Example: WHISPER_LANG=it just transcribe x
# whisper.cpp is the submodule vendor/whisper.cpp; its recorded commit is the pinned version.
# The full walkthrough is in GUIDE.md.

set shell := ["bash", "-euo", "pipefail", "-c"]
# Recipe arguments reach the scripts as "$@", so a flag with spaces (--prompt "a b") survives intact.
set positional-arguments

[private]
default:
    @just --list --unsorted

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

[doc('Full setup: install missing tools and Python, whisper.cpp submodule, build, models, check')]
[group('setup')]
setup: (deps "install") python clone build models check

[doc('Check the dependencies (Homebrew is required) and offer to install the missing ones: just deps [check|install]')]
[group('setup')]
deps mode="":
    scripts/deps.sh "$@"

[doc('Install the Python pinned in .python-version with uv and create the project environment (.venv)')]
[group('setup')]
python:
    uv python install
    uv sync
    uv run python -VV

[doc('Fetch the whisper.cpp submodule (vendor/whisper.cpp) at the recorded commit, if not there yet')]
[group('setup')]
clone:
    scripts/clone.sh

[doc('List the whisper.cpp release tags (newest first), the commit checked out and how far master is ahead')]
[group('setup')]
versions:
    scripts/versions.sh

[doc('Where whisper.cpp stands: checkout, recorded commit, newest release upstream, build and smoke test state, models')]
[group('setup')]
status:
    scripts/status.sh

[doc('Check out a whisper.cpp release tag (or branch, or commit): just checkout [ref]; no ref goes back to the recorded commit')]
[group('setup')]
checkout ref="":
    scripts/checkout.sh "$@"

[doc('Switch whisper.cpp to a release, rebuild and run the smoke test: just upgrade [ref]; then `just pin` to record it')]
[group('setup')]
upgrade ref="": (checkout ref) build test

[doc('Record the whisper.cpp commit checked out as the pin, in a commit of this repository (after `just test`)')]
[group('setup')]
pin:
    scripts/pin.sh

[doc('Build whisper.cpp (checked-out version) in Release mode with Metal, and SDL2 for whisper-stream')]
[group('setup')]
build:
    scripts/build.sh

[doc('Delete the whisper.cpp build directory and build again from scratch')]
[group('setup')]
rebuild:
    scripts/build.sh --clean

[doc('Download the ggml speech model (large-v3-turbo) and the Silero VAD model into models/')]
[group('setup')]
models:
    scripts/models.sh

[doc('Check tools, Python, whisper.cpp version, binaries, models and the microphones')]
[group('setup')]
check:
    scripts/check.sh

[doc('Create your vocabulary prompt for WHISPER_LANG from the example (config/lang/<lang>/prompt.txt, git-ignored) and show it')]
[group('setup')]
prompt:
    scripts/prompt.sh

# ---------------------------------------------------------------------------
# Record
# ---------------------------------------------------------------------------

[doc('List the audio input devices, the macOS default one marked; MIC_DEVICE picks another by index or name')]
[group('record')]
devices:
    scripts/devices.sh

[doc('Record the microphone at full quality to recordings/originals/<name>.flac, plus recordings/<name>.wav at 16 kHz mono; p pauses, q stops, or give a duration: just record [name] [seconds]')]
[group('record')]
record name="" seconds="":
    scripts/record.sh "$@"

[doc('Convert any audio or video file (m4a, mp3, mp4, mov, ...) to recordings/<name>.wav at 16 kHz mono, never overwriting one: just convert path [name]')]
[group('record')]
convert src name="":
    scripts/convert.sh "$@"

[doc('Play back a recording from the terminal, the full-quality original when there is one: just play name')]
[group('record')]
play name:
    scripts/play.sh "$@"

# ---------------------------------------------------------------------------
# Transcribe
# ---------------------------------------------------------------------------

[doc('Transcribe recordings/<name>.wav to transcripts/<name>.{txt,srt,json}; extra whisper-cli flags pass through: just transcribe name [flags]')]
[group('transcribe')]
transcribe name *flags:
    scripts/transcribe.sh "$@"

[doc('Same as transcribe, with the fillers of the language added to the prompt so whisper keeps them: for counting hesitations')]
[group('transcribe')]
transcribe-verbatim name *flags:
    WHISPER_VERBATIM=1 scripts/transcribe.sh "$@"

[doc('Any audio or video file to text in one go: convert, transcribe, export; just transcribe-file path [name] [flags]')]
[group('transcribe')]
transcribe-file src name="" *flags:
    scripts/transcribe-file.sh "$@"

[doc('Transcribe every recording in recordings/ that has no transcript yet')]
[group('transcribe')]
transcribe-all:
    scripts/transcribe-all.sh

[doc('Live transcription from the microphone with whisper-stream; Ctrl+C stops and keeps text and audio as live-<date>')]
[group('transcribe')]
live *flags:
    scripts/live.sh "$@"

[doc('Measure model speed on this machine (encoder, decoder, batched) with whisper-bench; extra flags pass through')]
[group('transcribe')]
bench *flags:
    scripts/bench.sh "$@"

# ---------------------------------------------------------------------------
# Analyze and export
# ---------------------------------------------------------------------------

[doc('Duration, speaking time, words, pace, pauses, filler words and low-confidence segments of a transcript: just stats name')]
[group('analyze')]
stats name:
    scripts/stats.sh "$@"

[doc('Write transcripts/<name>.md: settings used, statistics and the text as [mm:ss] lines, ready to paste anywhere: just export name')]
[group('analyze')]
export name:
    scripts/export.sh "$@"

[doc('Export every transcript and write transcripts/INDEX.md: one row per transcript with date, duration, words, language, version')]
[group('analyze')]
export-all:
    scripts/export-all.sh

[doc('Second opinion on the low-confidence segments with the full large-v3 model: transcripts/<name>.recheck.md; just recheck name')]
[group('analyze')]
recheck name:
    scripts/recheck.sh "$@"

# ---------------------------------------------------------------------------
# Optional: Core ML encoder on the Neural Engine (needs the full Xcode app)
# ---------------------------------------------------------------------------

[doc('Generate the Core ML encoder for the model (needs Xcode.app; takes a while) and rebuild with WHISPER_COREML=1')]
[group('optional')]
coreml:
    scripts/coreml.sh

# ---------------------------------------------------------------------------
# Quality and housekeeping
# ---------------------------------------------------------------------------

[doc('Smoke test: a synthesized sentence in WHISPER_LANG through convert, transcribe, stats and export, in a temporary directory')]
[group('quality')]
test:
    scripts/test.sh

[doc('Lint the shell scripts with shellcheck and parse them with the macOS /bin/bash 3.2 for compatibility')]
[group('quality')]
lint:
    shellcheck --shell=bash --external-sources --source-path=SCRIPTDIR scripts/*.sh scripts/lib/*.sh
    for f in scripts/*.sh scripts/lib/*.sh; do /bin/bash -n "$f" || exit 1; done
    @echo "lint ok"

[doc('Format the Markdown files with Prettier')]
[group('quality')]
format-docs:
    npx --yes prettier@3 --write "README.md" "GUIDE.md" "CLAUDE.md" "CHANGELOG.md" "config/lang/README.md"

[doc('Fail if the Markdown files are not Prettier-formatted')]
[group('quality')]
check-docs:
    npx --yes prettier@3 --check "README.md" "GUIDE.md" "CLAUDE.md" "CHANGELOG.md" "config/lang/README.md"

[confirm('Remove every file in transcripts/ (recordings are kept)?')]
[doc('Remove generated transcripts; recordings stay')]
[group('housekeeping')]
clean:
    find transcripts -type f ! -name .gitkeep -delete
