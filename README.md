# just-whisper

An easy-to-use wrapper around [whisper.cpp](https://github.com/ggml-org/whisper.cpp) for a Mac with Apple Silicon. One command builds whisper.cpp and downloads the model, and one command turns an audio or video file into text. Nothing leaves the machine: audio, model and transcripts stay local.

The name says how it works: every command is a [`just`](https://github.com/casey/just) recipe.

The wrapper handles the steps whisper.cpp leaves to you:

- **A pinned release.** whisper.cpp is a git submodule at a tested release tag, built with Metal for the GPU.
- **The model.** OpenAI's `large-v3-turbo`, downloaded once and checked against its published SHA-1.
- **Any input file.** ffmpeg converts m4a, mp3, mp4, mov and anything else it can decode. Recording from the microphone is included and optional: any recorder works.
- **Accuracy settings.** Voice activity detection skips the silences, and a vocabulary prompt steers the spelling of your names and terms.
- **Output.** Plain text, subtitles, JSON with timestamps, and a Markdown export with a `[mm:ss]` position on every line.

What you do with the transcript afterwards (notes, meeting minutes, subtitles, an LLM prompt) is outside this tool.

Version 1.2.0 ([CHANGELOG.md](CHANGELOG.md)). Developed, measured and tested on a MacBook Pro M4 Pro with 24 GB of RAM running macOS 26. [GUIDE.md](GUIDE.md) explains every step, the settings, the common problems and their fixes.

> **AI usage disclosure**: This codebase was written with LLM-based tools. It is reviewed and tested, but bugs and odd patterns are possible. Review before relying on it in production.

## Quick start

With Homebrew installed (the one thing to do by hand, https://brew.sh), from a terminal:

```bash
git clone --recurse-submodules https://github.com/ailequal/just-whisper.git
cd just-whisper
scripts/deps.sh install       # checks everything, installs the missing tools (just, uv, cmake, ffmpeg, ...) and Python 3.15 via uv
just setup                    # whisper.cpp build (2 to 3 minutes), the 1.5 GiB model download, a final check
just test                     # a synthesized sentence through convert, transcribe, stats and export: prints "ok" when the setup works
```

Setup is needed once and takes about five minutes plus the download. Then one command turns any audio or video file into text:

```bash
just transcribe-file ~/Downloads/memo.m4a   # transcripts/memo.txt, plus .srt, .json, .log, .md and .timestamps.txt
```

To record from the microphone instead:

```bash
just record take1             # speak, p pauses, q stops: recordings/take1.wav (macOS asks for the microphone permission the first time)
just transcribe take1         # transcripts/take1.{txt,srt,json,log}
just export take1             # transcripts/take1.md: settings, statistics, text with [mm:ss] timestamps
```

The default language is English. `WHISPER_LANG=it just transcribe take1` transcribes Italian, and `export WHISPER_LANG=it` in your shell profile makes it the default. Any language Whisper supports works the same way, with its code (`fr`, `de`, `es`, `ja`, ...). English and Italian ship with their fillers, smoke test and example prompt; other languages transcribe without them.

Names and terms whisper gets wrong go in your vocabulary prompt: `just prompt` creates `config/lang/en/prompt.txt` (git-ignored) from the example. Edit it, then transcribe again.

`just check` reports every tool, binary, model and setting, and names the recipe that fixes each gap.

Every recipe with logic calls a script of the same name in `scripts/` (`just test` runs `scripts/test.sh`, `just rebuild` runs `scripts/build.sh --clean`), so the same steps run without just: `scripts/transcribe.sh take1 --max-len 80`.

## Limits

- **Speakers are not separated.** Several voices come out as one stream of text. whisper.cpp separates only the two channels of a stereo file (`--diarize`) or needs an English-only model (`--tinydiarize`).
- **Timestamps are per segment.** Segments follow the pauses in the speech, so there is no fixed interval. GUIDE.md, section 11, has the flags for shorter segments and for per-token times.
- **macOS on Apple Silicon only.** Intel Macs and Linux are not supported.

## Requirements

Required:

- **A Mac with Apple Silicon** (M1 or later) on macOS 26. Tested only on a MacBook Pro M4 Pro, 24 GB, macOS 26.7; older macOS versions are untested and `just deps` says so.
- **Disk and memory.** About 2.3 GB for the model plus the whisper.cpp build, and 2.9 GB more for the optional `large-v3` used by `just recheck`. About 2 GB of RAM while transcribing.
- **Internet during setup only**, for Homebrew, the whisper.cpp submodule and the 1.5 GiB model. Recording, transcription and export are offline.
- **A native arm64 terminal** with `zsh` or `bash`, not one running under Rosetta. GUIDE.md, section 3, covers the shell, the PATH and Rosetta.
- **Xcode Command Line Tools**: the C++ compiler for whisper.cpp, the Swift compiler for the microphone recorder, `git`, Metal. Install with `xcode-select --install`.
- **Homebrew** at `/opt/homebrew`: https://brew.sh. Nothing here installs it, and `just deps` stops without it.
- **just** 1.27 or later, **uv**, **cmake** and **ffmpeg**. `scripts/deps.sh install` installs the missing ones with Homebrew.
- **Python 3.15**, pinned in `.python-version` and installed by uv (`just python`). Every Python command goes through `uv run`; never call `python3` directly. The scripts use the standard library only.

`just setup` then fetches the whisper.cpp submodule at the release tag **`v1.9.6`**, builds it, and downloads `ggml-large-v3-turbo.bin` (1.5 GiB) and the Silero VAD model into `models/`. The Homebrew formula of whisper.cpp is not a replacement: it lacks the model scripts and Core ML (GUIDE.md, section 12).

Optional:

- **Microphone permission** for your terminal app (System Settings, Privacy & Security, Microphone): only for `just record` and `just live`, asked on the first recording.
- **The `large-v3` model** (2.9 GiB): only for `just recheck`. Download it once with `WHISPER_MODEL=large-v3 just models`.
- **A macOS voice for the language**: only for `just test`, which synthesizes its sentence with a system voice of `WHISPER_LANG`. When none is installed, the test says where to add one (System Settings, Accessibility, Spoken Content).
- **sdl2**: builds `whisper-stream` for `just live`. `brew install sdl2` (also done by `just deps`).
- **Node.js** 26 (the current LTS line, `.nvmrc`): only for `just format-docs` and `just check-docs` (Prettier via `npx`). `just deps` reports the version and does not install it; 24 still works.
- **shellcheck**: only for `just lint`. `brew install shellcheck` (also done by `just deps`).
- **Xcode.app** from the App Store: only for `just coreml`, the Core ML encoder on the Neural Engine.

## Commands

Commands live in the `justfile`, which only launches the scripts in `scripts/`; `just` alone lists them.

```bash
just setup              # deps install + python + clone + build + models + check
just deps [check|install] # check macOS, Homebrew, tools, Python; offer to install what is missing (check: report only, install: no question)
just python             # uv python install + uv sync: Python 3.15 and the project .venv
just clone              # fetch the submodule vendor/whisper.cpp at the recorded commit, if absent
just status             # checkout vs recorded commit, build and smoke test state, models
just versions           # release tags with dates, what is checked out, how far master is ahead
just checkout [ref]     # switch vendor/whisper.cpp to a tag, branch or commit; no ref: back to the recorded commit
just upgrade [ref]      # checkout + build + test in one go
just pin                # record the checked-out whisper.cpp commit as the pin, in a commit (needs `just test` first)
just build              # cmake Release build with Metal, plus whisper-stream when sdl2 is present
just rebuild            # same, after deleting the build directory
just models             # download ggml-large-v3-turbo.bin and the Silero VAD model into models/, verify the SHA-1
just check              # versions (uv, Python, cmake, ffmpeg, swiftc, node), binaries, models, language, prompt, microphones
just prompt             # create config/lang/<lang>/prompt.txt, your vocabulary prompt, from the example

just devices            # audio inputs, the macOS default one marked; MIC_DEVICE picks another by index or name
just record [name] [s]  # record the mic at full quality to recordings/originals/<name>.flac, plus recordings/<name>.wav at 16 kHz mono; p pauses, q stops, or after s seconds
just convert file [name]# any audio/video file to recordings/<name>.wav; stops if that recording exists
just play name          # play a recording, the full-quality original when there is one

just transcribe name [flags]  # whisper-cli with the language, VAD and vocabulary prompt; extra flags pass through
just transcribe-verbatim name # same, with the language's fillers in the prompt so hesitations (um, uh) are kept
just transcribe-file path [name] [flags]  # any audio or video file: convert + transcribe + export in one go
just transcribe-all     # every recording without a transcript
just live               # whisper-stream from the microphone; Ctrl+C keeps text and audio as live-<date>
just bench              # whisper-bench on this machine

just stats name         # duration, speaking time, words/min, pauses, fillers, low-confidence segments
just export name        # transcripts/<name>.md (settings, statistics, [mm:ss] text with [?] marks) and <name>.timestamps.txt
just export-all         # export every transcript and write transcripts/INDEX.md
just recheck name       # low-confidence segments read again by the full large-v3 model: transcripts/<name>.recheck.md

just coreml             # optional: Core ML encoder on the Neural Engine (needs Xcode.app)
just test               # smoke test: a synthesized sentence through convert, transcribe, stats and export, in a temporary directory
just lint               # shellcheck on scripts/, plus a parse with the macOS /bin/bash 3.2
just format-docs        # Prettier on the Markdown files; check-docs verifies
just clean              # remove transcripts (recordings are kept, asks first)
```

## Settings

Settings are environment variables with their defaults in `scripts/lib/common.sh`. They apply to `just` and to the scripts alike: `WHISPER_LANG=it just transcribe meeting`.

| Setting                   | Default              | Meaning                                                                                       |
| ------------------------- | -------------------- | --------------------------------------------------------------------------------------------- |
| `WHISPER_LANG`            | `en`                 | Spoken language code, or `auto` to detect it                                                  |
| `WHISPER_MODEL`           | `large-v3-turbo`     | ggml speech model                                                                             |
| `WHISPER_VAD`             | `silero-v6.2.0`      | Voice activity detection model                                                                |
| `WHISPER_THREADS`         | `8`                  | CPU threads for whisper                                                                       |
| `WHISPER_PROMPT`          | empty                | Vocabulary prompt file; empty uses the language's `prompt.txt`, `/dev/null` disables          |
| `WHISPER_VERBATIM`        | `0`                  | `1` adds the language's fillers to the prompt (what `just transcribe-verbatim` sets)          |
| `LOW_CONFIDENCE`          | `0.6`                | Segments with a mean token probability below this are marked                                  |
| `RECHECK_MODEL`           | `large-v3`           | Model used by `just recheck`                                                                  |
| `STATS_TARGET_WPM`        | empty                | Optional target pace in words per minute; `just stats` then compares the pace with it         |
| `MIC_DEVICE`              | empty                | Audio input: empty follows the macOS default input; or an index or a name from `just devices` |
| `WHISPER_RECORDINGS_DIR`  | `recordings`         | Where the WAV recordings live                                                                 |
| `WHISPER_TRANSCRIPTS_DIR` | `transcripts`        | Where the transcripts and exports are written                                                 |
| `WHISPER_MODELS_DIR`      | `models`             | Where the ggml models live                                                                    |
| `WHISPER_DIR`             | `vendor/whisper.cpp` | whisper.cpp checkout; another path for experiments                                            |
| `WHISPER_REF`             | empty                | Ref for `just checkout` and `just upgrade`; empty means the recorded submodule commit         |
| `WHISPER_REPO`            | upstream URL         | Repository `just clone` uses when `WHISPER_DIR` is not the submodule                          |
| `COREML_PYTHON`           | `3.13`               | Python version for the Core ML conversion                                                     |

## whisper.cpp version

whisper.cpp is the git submodule `vendor/whisper.cpp`, and the commit recorded for it in this repository is the pin: the release tag `v1.9.6`, not `master`. Upstream cuts a release about once a month as a tag on `master`; there are no maintenance branches, and between releases `master` receives daily backend syncs from llama.cpp (Metal included) that no whisper.cpp release has validated. Pinning gives the same binary for every transcript, a version to write next to it, and a git history of every upgrade. Details and the comparison with `master` are in GUIDE.md, section 4.

```bash
just versions            # what exists, what is checked out, what is recorded
just status              # checkout vs recorded commit, build and smoke test state
just upgrade v1.9.7      # try a newer release: checkout, build, smoke test
just pin                 # keep it: commit the new submodule commit
just upgrade             # back to the recorded version
WHISPER_REF=master just upgrade   # follow master on purpose
```

`just pin` refuses until the smoke test has run on the build of that commit. After pinning, update the version named in this README and in GUIDE.md.

## Layout

- `GUIDE.md`: the full guide: setup, recording methods, transcription settings, analysis and export, scenarios, FAQ, cheat sheet.
- `justfile`: the commands above; each one calls a script.
- `scripts/`: one bash script per command (`transcribe.sh`, `checkout.sh`, `check.sh`, ...) and `scripts/lib/common.sh` with the settings, derived paths and helpers they share. Written for bash 3.2 as well, so they run with the macOS `/bin/bash`; `just lint` checks them.
- `config/lang/<code>/`: one directory per language (`en`, `it` shipped): `fillers.txt` (counted by `just stats`, injected by `just transcribe-verbatim`), `smoke-test.txt` (sentence and expected word for `just test`), `prompt.example.txt` (generic vocabulary prompt, tracked) and your `prompt.txt` (git-ignored, created by `just prompt`). See `config/lang/README.md`.
- `scripts/mic-capture.swift`: the microphone recorder behind `just record`, `just live` and `just devices`. It records what the device delivers (its sample rate and channels, 24-bit), pauses and resumes, and reports clipped input and lost audio. Compiled on first use into `.build/`, git-ignored.
- `scripts/transcript-stats.py`: duration, speaking time, pace, pauses, filler words and low-confidence segments from the JSON transcript. `scripts/stats.sh` runs it with `uv run python -I`.
- `scripts/transcript-timestamps.py`: the JSON transcript as `[mm:ss] text` lines, with `[?]` on low-confidence segments; `scripts/export.sh` embeds that in the Markdown export.
- `scripts/transcript-index.py`: the table in `transcripts/INDEX.md`, written by `just export-all`.
- `scripts/recheck.sh`: the second reading of low-confidence segments with `large-v3`.
- `CLAUDE.md`: conventions for Claude Code when it works in this repository.
- `pyproject.toml`, `.python-version`, `uv.lock`: the uv project. Python 3.15, no dependencies. `uv sync` creates `.venv/`, git-ignored.
- `.nvmrc`: Node.js 26, for the Prettier recipes only.
- `recordings/`: WAV files at 16 kHz mono, git-ignored. `recordings/originals/` holds the full-quality takes of `just record` and `just live` as FLAC, and the source files copied by `just convert`.
- `transcripts/`: `.txt`, `.srt`, `.json` (full, with token probabilities), `.log`, `.md`, `.timestamps.txt` and, after `just recheck`, `.recheck.md` per recording, plus `INDEX.md`, git-ignored. The log starts with the whisper.cpp version, model, prompt and flags that produced the transcript.
- `CHANGELOG.md`: what changed in each version, Keep a Changelog format.
- `LICENSE`: MIT. whisper.cpp, vendored as a submodule, is MIT as well.
- `vendor/whisper.cpp`: the upstream source as a git submodule at the pinned release; its `build/` directory is ignored by whisper.cpp itself.
- `models/`: the ggml models downloaded by `just models`, git-ignored (1.5 GiB).

## Measured on this machine

MacBook Pro M4 Pro, 24 GB, whisper.cpp release `v1.9.6` (commit 96ec4d98), Metal, `ggml-large-v3-turbo.bin`:

| What                               | Value                |
| ---------------------------------- | -------------------- |
| Model on disk                      | 1.5 GiB              |
| Peak memory of `whisper-cli`       | about 2.0 GB         |
| 63 s of Italian speech             | 3.1 s total          |
| Encoder (one 30 s window)          | about 0.5 s          |
| Decoder                            | about 2 ms per token |
| Expected for a 40 minute recording | about 2 minutes      |

The 40 minute figure is extrapolated from the shorter runs, not measured.

## License

MIT, see [LICENSE](LICENSE). whisper.cpp and the ggml library it bundles are MIT licensed by their authors; the Whisper models are released by OpenAI under the MIT license as well.
