# Local speech-to-text with whisper.cpp on a Mac

This guide sets up a fully local transcription pipeline on a Mac with Apple Silicon. The repository is a wrapper around [whisper.cpp](https://github.com/ggml-org/whisper.cpp): it builds a pinned release, downloads OpenAI's `large-v3-turbo` model, converts any audio or video file (or records from the microphone), transcribes it, and writes plain text, subtitles, JSON with timestamps and a Markdown export. What you do with the text afterwards is yours: notes, meeting minutes, subtitles, an LLM prompt.

It was written and tested on a MacBook Pro M4 Pro with 24 GB of RAM running macOS 26, with the default `zsh` shell, mostly on recordings in Italian. The default language is English; any other language Whisper supports is one setting, `WHISPER_LANG`. Older macOS versions are untested. The target is macOS on Apple Silicon only: recording, playback and the smoke test use macOS frameworks and tools, and the build relies on Metal. Every command below was run on that machine with whisper.cpp at the release tag `v1.9.5` (commit `d1be6fde`). The commands are wrapped in the `justfile` of this repository, which launches one bash script per command from `scripts/`; each step shows the `just` recipe and what the script runs, so you can do it by hand. Settings are environment variables with defaults in `scripts/lib/common.sh`; the README lists them in a table.

In a hurry: the README quick start is the short version. This guide explains what each step does, why, and what to do when something is off.

Contents:

1. [How the pipeline works](#1-how-the-pipeline-works)
2. [What to expect from the hardware](#2-what-to-expect-from-the-hardware)
3. [Prerequisites](#3-prerequisites)
4. [Get whisper.cpp, at a release](#4-get-whispercpp-at-a-release)
5. [Build it](#5-build-it)
6. [Download the models](#6-download-the-models)
7. [Microphone and permissions](#7-microphone-and-permissions)
8. [Get the audio in](#8-get-the-audio-in)
9. [Transcribe](#9-transcribe)
10. [Analyze and export](#10-analyze-and-export)
11. [Tuning](#11-tuning)
12. [Optional: Core ML, server, alternatives](#12-optional-core-ml-server-alternatives)
13. [Scenarios](#13-scenarios)
14. [FAQ](#14-faq)
15. [Cheat sheet](#15-cheat-sheet)
16. [Sources](#16-sources)

## 1. How the pipeline works

```
microphone / QuickTime / Voice Memos / Meet, Zoom, Teams recording / any audio or video file
        │  (any format)
        ▼
ffmpeg ──► recordings/<name>.wav      16 kHz, mono, 16-bit PCM: one format for every source
           recordings/originals/      the source file, or the full-quality microphone take
        │
        ▼
whisper-cli (Metal GPU) ──► transcripts/<name>.txt   plain text, one line per segment
   large-v3-turbo           transcripts/<name>.srt   subtitles with timestamps
   + Silero VAD             transcripts/<name>.json  segments with offsets, used by the stats
   + vocabulary prompt      transcripts/<name>.log   settings used, then what whisper printed
        │
        ▼
just stats  ──► speaking time, words per minute, pauses, fillers, low-confidence segments
just export ──► transcripts/<name>.md: settings, stats, text as [mm:ss] lines ([?] where to listen again)
                transcripts/<name>.timestamps.txt: the [mm:ss] lines alone
just export-all ──► every transcript, plus transcripts/INDEX.md
just recheck ──► transcripts/<name>.recheck.md: the [?] segments read again by the full large-v3

just transcribe-file <file> does convert, transcribe and export in one go.
```

Three things make this reliable:

- **Audio format.** Every source becomes a 16-bit WAV at 16 kHz mono, the sample rate Whisper was trained on. whisper-cli also reads flac, mp3 and ogg by itself, but not m4a, mp4 or mov, which is what phones, QuickTime and meeting apps produce. ffmpeg converts all of them, so every later step finds the same format. `just record` keeps the microphone take at full quality and derives this file from it.
- **Model and backend.** `large-v3-turbo` is large-v3 with the decoder cut from 32 layers to 4 (about 809 M parameters instead of 1.55 B). It keeps nearly all the accuracy and decodes several times faster. On Apple Silicon, whisper.cpp runs it on the GPU through Metal by default, so no extra configuration is needed.
- **Vocabulary prompt.** Whisper accepts an initial prompt that biases spelling. Without it, a company name came out as two common words in the first test; with the name in the prompt it came out right. Your prompt lives in `config/lang/<language>/prompt.txt` (`just prompt`).

## 2. What to expect from the hardware

Measured on the M4 Pro with 24 GB:

| What                               | Value                                        |
| ---------------------------------- | -------------------------------------------- |
| Model on disk                      | 1.5 GiB (`ggml-large-v3-turbo.bin`)          |
| Peak memory of whisper-cli         | about 2.0 GB                                 |
| Encoder, one 30 s window           | about 0.5 s (`whisper-bench`: 514 ms)        |
| Decoder                            | about 2 ms per token                         |
| 63 s of Italian speech, end to end | 3.2 s                                        |
| Estimate for a 40 minute recording | about 2 minutes (extrapolated, not measured) |

24 GB is far more than needed. The full `large-v3` (2.9 GiB, 32 decoder layers) also fits and runs, but it is slower and not more accurate on clean Italian speech. The quantized `large-v3-turbo-q5_0` (547 MiB) is an option for a laptop on battery, with a small accuracy cost.

The Core ML path (encoder on the Neural Engine) is an optional speed-up for the encoder. It needs the full Xcode app, which was not installed on this machine, so the guide treats it as optional (section 12). Metal alone is already far faster than real time.

## 3. Prerequisites

| Tool                     | Why                                                       | Install                                                        |
| ------------------------ | --------------------------------------------------------- | -------------------------------------------------------------- |
| Xcode Command Line Tools | C++ and Swift compilers, `git`, Metal headers             | `xcode-select --install`                                       |
| Homebrew                 | package manager, hard requirement                         | https://brew.sh                                                |
| `just` 1.27+             | runs the recipes in `justfile`                            | `brew install just` (also done by `scripts/deps.sh install`)   |
| `uv`                     | installs Python and runs every Python command             | `brew install uv` (also done by `just deps`)                   |
| Python 3.15              | the stats and export scripts; pinned in `.python-version` | `just python` (uv downloads and manages it)                    |
| `cmake`                  | builds whisper.cpp                                        | `brew install cmake` (also done by `just deps`)                |
| `ffmpeg`                 | converts and plays audio                                  | `brew install ffmpeg` (also done by `just deps`)               |
| `sdl2`                   | optional, only for live `whisper-stream`                  | `brew install sdl2` (also done by `just deps`)                 |
| Node.js 26 LTS           | optional, only for Prettier in `just format-docs`         | `nvm install` (reads `.nvmrc`) or `brew install node`          |
| `shellcheck`             | optional, only for `just lint` on the scripts             | `brew install shellcheck` (also done by `just deps`)           |
| Xcode.app                | optional, only for the Core ML conversion                 | App Store, then `sudo xcode-select -s /Applications/Xcode.app` |

One command checks all of this and installs what is missing:

```bash
just deps            # report, then ask before installing (Homebrew formulas and Python through uv)
just deps check      # report only; exit status 1 when something required is missing
just deps install    # install without asking; what `just setup` runs first
scripts/deps.sh install   # the same before just is installed
```

The script stops at once if Homebrew is missing or is the Intel one in `/usr/local`, since nothing else can be installed without it; it also stops in a Rosetta terminal. With Homebrew it checks the Command Line Tools, `just` (and its version), `uv`, `cmake`, `ffmpeg`, the optional `sdl2` and `shellcheck`, Node.js (reported, not installed), the pinned Python and `.venv`, and reports the state of the whisper.cpp checkout, binaries and models, which `just clone`, `just build` and `just models` handle. When Homebrew is installed but not on the PATH, it uses `/opt/homebrew/bin` for that run and prints the `shellenv` line to add to `~/.zprofile` or `~/.bash_profile`, depending on your login shell.

Python policy for this project: **never call `python3` directly**. uv installs the interpreter pinned in `.python-version` (3.15, the newest stable release) and `uv run python ...` executes scripts with it inside the project environment `.venv/`, created by `uv sync`. `pyproject.toml` declares no dependencies, so the environment is tiny; `uv.lock` records that. The only Python task that needs a different version is the optional Core ML conversion, and uv handles that too (section 12).

```bash
just python
# runs: uv python install   (3.15 from .python-version)
#       uv sync             (creates .venv)
#       uv run python -VV   (prints the interpreter in use)
```

Shell and PATH on a fresh Mac:

- The default login shell is `zsh` and nothing here needs another one; `bash` as login shell works the same. The scripts in `scripts/` are bash, started by `just` or by their own shebang (`#!/usr/bin/env bash`), and they are written for the system `/bin/bash` 3.2 as well as the Homebrew bash 5 (`just lint` parses them with `/bin/bash`). Run them as `scripts/<name>.sh`; `zsh scripts/<name>.sh` or `sh scripts/<name>.sh` is refused with a message instead of failing halfway.
- Homebrew on Apple Silicon lives in `/opt/homebrew`. Its installer prints a line to add to `~/.zprofile` (zsh) or `~/.bash_profile` (bash), `eval "$(/opt/homebrew/bin/brew shellenv)"`; without it `brew`, `just`, `uv`, `cmake` and `ffmpeg` are not on the PATH in new terminals. `just deps` detects this case and prints the line for your shell.
- Use a native arm64 terminal. A terminal running under Rosetta (`arch` prints `i386`) would build an Intel binary without Metal; `scripts/build.sh` refuses to build there and `just check` reports it.
- `uv` downloads an arm64 Python; the Core ML conversion also runs natively.

Check what is there:

```bash
just check
```

It prints the macOS version and chip, the login shell, tool versions, the whisper.cpp version and binaries, the models, the prompt file, and the microphones. Each missing item names the recipe that fixes it, and a Rosetta terminal or an Intel Homebrew in `/usr/local` is flagged.

## 4. Get whisper.cpp, at a release

whisper.cpp is a git submodule of this repository at `vendor/whisper.cpp` (`.gitmodules`, cloned over HTTPS from GitHub). A submodule records one upstream commit in this repository's history, so the pinned version is enforced by git and every upgrade is a commit here. Upstream history is about 50 MB; the build directory inside the submodule is ignored by whisper.cpp's own `.gitignore`, and the 1.5 GiB models live outside it, in `models/` (section 6).

```bash
git clone --recurse-submodules <this repo>     # brings vendor/whisper.cpp at the recorded commit
just clone                                     # after a plain clone: git submodule update --init vendor/whisper.cpp
just status                                    # checkout, recorded commit, newest release upstream, build and smoke test state, models
```

To experiment with another checkout, export `WHISPER_DIR=/path/to/whisper.cpp` before any `just` command: the recipes then build and run from there, and `just pin` refuses, since only the submodule can be recorded. When nothing is at that path yet, `WHISPER_REF=v1.9.5 just clone` clones `WHISPER_REPO` (the upstream URL by default) there at that ref.

### Why a release tag and not master

How upstream releases work (ggml-org policy, [discussion #1579](https://github.com/ggml-org/ggml/discussions/1579)):

- A release is a tag on `master`, roughly monthly (v1.9.2 on 2026-08-04, v1.9.3 on 08-20, v1.9.4 on 09-11, v1.9.5 on 10-06). There are no release or maintenance branches and no backports.
- A `vX.Y.Z` tag marks the commit where the bundled ggml matches a released ggml and the release CI ran; it is built with `WHISPER_BUILD_IS_DEV=OFF`, so `whisper-cli --version` prints `1.9.5` instead of `1.9.5-dev`.
- Between releases, `master` receives daily `sync : ggml` imports of llama.cpp backend work. On 2026-10-27 it was 135 commits past v1.9.5: 126 backend syncs (several touching Metal kernels), 9 whisper-side commits worth 16 lines in `src/whisper.cpp`.

The value is reproducibility: the same binary for every transcript, so a change in the output is the audio and not a kernel update pulled in by `git pull`. The pinned version is the commit recorded for the submodule (`v1.9.5`, `git ls-tree HEAD vendor/whisper.cpp`); `WHISPER_REF` in the environment names a different ref for `just checkout` and `just upgrade`.

### Switching versions

```bash
just versions              # tags with dates, current checkout, recorded commit, how far master is ahead
just checkout v1.9.4       # detached checkout of a tag (or a commit); then `just build`
just upgrade v1.9.6        # checkout + build + smoke test, for a newer release
just upgrade               # back to the recorded commit
WHISPER_REF=master just upgrade   # follow master on purpose (branch, fast-forwarded)
just pin                   # record the checked-out commit as the new pin, in a commit of this repository
just rebuild               # delete vendor/whisper.cpp/build and build again, if a switch leaves stale objects
```

`just checkout` (`scripts/checkout.sh`) refuses to switch when the checkout has local changes, and with no argument returns to the recorded commit. Moving the submodule changes nothing in this repository until `just pin`: `git status` shows `vendor/whisper.cpp (new commits)`, and `just status` and `just check` say that the checkout differs from the recorded one. `just build` detects whether HEAD is exactly on a tag and sets `WHISPER_BUILD_IS_DEV` accordingly, so the binary reports a plain version on a release and `-dev` otherwise.

To adopt a new release for good: `just upgrade vX.Y.Z`, a real recording through `just transcribe`, then `just pin`, which commits the new submodule commit (`chore(whisper): pin whisper.cpp to vX.Y.Z`) and refuses when `just test` has not passed on that build. Then update the version named in `README.md` and in this guide. Models keep working across versions; re-download only if the checksums in `vendor/whisper.cpp/models/README.md` change.

## 5. Build it

```bash
just build
# scripts/build.sh:
#   cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build -DCMAKE_BUILD_TYPE=Release -DWHISPER_SDL2=ON -DWHISPER_BUILD_IS_DEV=OFF -DWHISPER_COREML=OFF
#   cmake --build vendor/whisper.cpp/build -j --config Release
#   vendor/whisper.cpp/build/bin/whisper-cli --version      -> whisper.cpp version: 1.9.5
```

What the flags mean:

- `-DCMAKE_BUILD_TYPE=Release`: optimized build. Debug builds are several times slower.
- Metal and Accelerate are on by default on macOS; nothing to pass. The `system_info` line printed by whisper-cli confirms it: `MTL : EMBED_LIBRARY = 1`, `NEON = 1`, `ACCELERATE = 1`.
- `-DWHISPER_SDL2=ON`: builds `whisper-stream`, the microphone-to-text tool used in section 8 for live transcription. The recipe sets it only when `sdl2-config` is on the PATH.
- `-DWHISPER_BUILD_IS_DEV=OFF`: set by the recipe only when HEAD is exactly on a tag; it only changes the reported version string.
- `-DWHISPER_COREML=OFF`: the recipe turns it on only when the Core ML encoder generated by `just coreml` is in `models/`, see section 12.

The build takes a few minutes on the M4 Pro and produces `vendor/whisper.cpp/build/bin/whisper-cli`, `whisper-stream`, `whisper-bench`, `whisper-server` and `whisper-quantize`. Warnings about `json.hpp` literal operators are expected with the current clang.

The smoke test covers the whole chain. It synthesizes a sentence in `WHISPER_LANG` with a macOS voice of that language (sentence and expected word in `config/lang/<language>/smoke-test.txt`), then runs it through convert, transcribe, stats and export, and checks the text and the output files. It needs the models of section 6, so run it after `just models`. The chain works in a temporary directory: nothing is written to `recordings/` or `transcripts/`.

```bash
just test
# [00:00] Good morning, everyone. This is a transcription test in English with Whisper.
# ok: whisper-cli 1.9.5 transcribes 'en' (voice Albert); convert, transcribe, stats and export passed
WHISPER_LANG=it just test       # the Italian sentence, with an Italian voice
```

## 6. Download the models

The Hugging Face page https://huggingface.co/openai/whisper-large-v3-turbo hosts the PyTorch weights. whisper.cpp needs the same weights in its own `ggml` format; the project publishes converted files at https://huggingface.co/ggerganov/whisper.cpp and the download script fetches them from there.

```bash
just models
# scripts/models.sh, with the upstream scripts and our models/ as destination:
#   sh vendor/whisper.cpp/models/download-ggml-model.sh large-v3-turbo models   -> models/ggml-large-v3-turbo.bin (1.5 GiB)
#   sh vendor/whisper.cpp/models/download-vad-model.sh silero-v6.2.0 models     -> models/ggml-silero-v6.2.0.bin (864 KiB)
```

The models live in `models/` at the root of this repository (git-ignored), not inside the source tree: switching or re-cloning whisper.cpp never touches them, and another location is one variable away, `WHISPER_MODELS_DIR`. `scripts/models.sh` then compares the SHA-1 of the speech model with the table in `vendor/whisper.cpp/models/README.md` (the upstream download script verifies nothing) and stops on a mismatch, which means a truncated download: delete the file and run `just models` again. By hand:

```bash
shasum models/ggml-large-v3-turbo.bin
# 4af2b29d7ec73d781377bfd1758ca957a807e941
```

The second file is Silero VAD, a small voice activity detector. With `--vad`, whisper-cli first finds the speech segments and transcribes only those: silences between sentences are skipped, which is faster and removes one source of hallucinated text.

Other models you may want (`WHISPER_MODEL=<name> just models`): `large-v3-turbo-q5_0` (547 MiB, quantized), `large-v3` (2.9 GiB, full), `medium` (1.5 GiB, older, weaker on Italian). Set `WHISPER_MODEL=<name>` to use one of them with the recipes.

## 7. Microphone and permissions

Only for recording with the Mac; skip it if your audio comes from files.

1. **Microphone permission for the terminal.** The first time the recorder (or whisper-stream) opens the microphone, macOS asks for permission for the app that launched it: Terminal, iTerm, Ghostty, VS Code. If you ever denied it, enable it in System Settings, Privacy & Security, Microphone. A denied app is refused with a message, or records silence with no error.
2. **Pick the input.** System Settings, Sound, Input: choose the device and watch the level meter while speaking normally. `just record` and `just live` use the input selected there. Aim for the meter to move to about two thirds; lower the input volume if it hits the end.
3. **List the inputs.** The one marked `(default)` is the input selected in System Settings. To use another without changing that setting, give `MIC_DEVICE` its index or its name; a part of the name is enough when it matches one input only.

   ```bash
   just devices
   #   [0] MacBook Pro Microphone (default)
   ```

4. **Five second check.** Record, then read the level line that `just record` prints after every take: a mean between -35 and -20 dB is normal speech; below -50 dB the script warns, which means the microphone is muted, too far, or not permitted.

   ```bash
   just record check 5
   # saved recordings/check.wav (5s, 16 kHz mono for whisper)
   # full quality: recordings/originals/check.flac (48000 Hz, 1 ch, 348K)
   # level: -27.4 dB mean (speech is usually between -35 and -20 dB)
   just play check          # plays the full-quality take
   ```

Which microphone:

- The built-in MacBook Pro microphone is good enough for a single speaker. Sit about 40 cm from it, in a quiet room.
- A USB or XLR microphone is better still and appears in `just devices` with its own index.
- Avoid AirPods and other Bluetooth headsets as the recording device: when their microphone is active they switch to a low-quality voice codec, and transcription accuracy drops noticeably. Wired headphones with the Mac's microphone are fine.
- An iPhone with Voice Memos is a good recorder away from the desk (section 8, method C).

## 8. Get the audio in

Every method ends with a file in `recordings/<name>.wav` at 16 kHz mono. `recordings/` is git-ignored; a date in the name keeps things sorted: `2026-10-28-meeting`, `2026-10-29-idea-2`. Names are made safe before use: lowercase, ASCII letters, digits, dot, underscore and dash, everything else becomes a dash (`My Memo (2).m4a` becomes `my-memo-2`, and the script prints the name it chose). Accented letters are dropped, so give a name yourself when the file name has them. Keep the originals: `just convert` copies them to `recordings/originals/`, and `just record` writes its full-quality take there.

A recording is never overwritten: `just record` and `just convert` stop when `recordings/<name>.wav` exists and ask for another name. `WHISPER_RECORDINGS_DIR` and `WHISPER_TRANSCRIPTS_DIR` move the two folders elsewhere, for example to an external disk.

If the audio is already a file and you want the text in one step, skip to `just transcribe-file <file>` (section 9).

### Method A: `just record` from the terminal (default)

```bash
just record 2026-10-28-notes
# scripts/record.sh:
#   .build/mic-capture record default recordings/originals/2026-10-28-notes.wav
#   ffmpeg -i recordings/originals/2026-10-28-notes.wav -vn -ar 16000 -ac 1 -c:a pcm_s16le recordings/2026-10-28-notes.wav
#   ffmpeg -i recordings/originals/2026-10-28-notes.wav -c:a flac recordings/originals/2026-10-28-notes.flac, then the WAV take is removed
just record check 5          # stops by itself after 5 seconds
```

Press `q` in the terminal to stop; Ctrl+C also stops and keeps the take. While recording, one line shows the elapsed time and the peak level.

`p` or the space bar pauses, and the same key resumes. Nothing is recorded during a pause, and the take continues in the same file with a short fade at the cut. The microphone stays open while paused, so the orange indicator in the menu bar stays on. `just record name 300` stops by itself after five minutes of recorded audio: a pause does not shorten the take.

The input is the one selected in System Settings, Sound, Input. `MIC_DEVICE=1 just record ...` or `MIC_DEVICE="USB Microphone" just record ...` selects another, by index or by name.

Each take gives two files:

- `recordings/originals/<name>.flac`: the audio exactly as the device delivers it, at its own sample rate and channel count (48 kHz mono for the built-in microphone), 24-bit. FLAC is lossless: the file decodes to the same samples as the WAV the recorder wrote, and that WAV is removed only after this is checked. This is the file to listen to, edit or share, and the one `just play` plays.
- `recordings/<name>.wav`: the 16 kHz mono file derived from it, the format whisper-cli reads.

The script then prints the duration and the mean level. It warns when the take is almost silent, when the input clipped, and when audio was lost on the way. To record at a higher sample rate, set the format of the device in Audio MIDI Setup: the recorder follows it.

The recorder is `scripts/mic-capture.swift`, a small Swift program compiled on first use into `.build/`; the compiler comes with the Command Line Tools. ffmpeg is not used to capture: its `avfoundation` input lost about 10% of the audio on the test machine (ffmpeg 9.0.2), in gaps of 512 samples that make the recording choppy.

Disk use: about 4 to 5 MB per minute for a 48 kHz mono original (55% of the 8.6 MB of the WAV on a speech take), plus 1.9 MB per minute for the 16 kHz file.

Pros: one command, full-quality original, level meter, no app to manage. Cons: no trimming.

### Method B: QuickTime Player

File, New Audio Recording. The small arrow next to the record button selects the microphone and the quality (choose Maximum). Stop, then File, Save as `.m4a`. Convert:

```bash
just convert ~/Desktop/memo.m4a 2026-10-28-notes
# scripts/convert.sh: ffmpeg -i memo.m4a -vn -ar 16000 -ac 1 -c:a pcm_s16le recordings/2026-10-28-notes.wav
```

`just convert` also copies the source into `recordings/originals/` (git-ignored), so the better-quality `.m4a` survives if you delete it from the app, and prints the level of the result.

Pros: level meter while recording, trim in place with Edit, Trim. Cons: one extra step.

### Method C: Voice Memos (Mac or iPhone)

Voice Memos on the Mac records with the same microphone. On the iPhone it is the easiest way to record away from the desk; recordings sync through iCloud and appear in Voice Memos on the Mac within a minute. In either case, drag the memo out of the app (or File, Share, Save to Files) to get the `.m4a`, then `just convert`. Turn on Enhance Recording only if the room is noisy: it is a mild noise reduction and does no harm to speech.

### Method D: screen recording (Cmd+Shift+5)

Press Cmd+Shift+5, choose Record Entire Screen or Record Selected Portion, open Options and pick the microphone. You get a `.mov` with video and audio. `just convert file.mov name` extracts the audio track (the `-vn` flag drops the video). Use this when you want the screen too, for example a demo you narrate.

### Method E: Google Meet, Zoom, Teams recordings

Meet saves to Google Drive as `.mp4`; Zoom saves locally as `.m4a` plus `.mp4`; Teams saves to OneDrive. Download, then `just convert`. ffmpeg reads all of these. Several speakers are transcribed as one stream of text: whisper does not separate them (see the FAQ on diarization).

### Method F: any other file

Podcasts, lectures, voice messages exported from a chat app, old `.mp3` files, video: anything ffmpeg can decode goes through `just convert file name`. Other recorders also work:

- `sox` (`brew install sox`): `rec -r 16000 -c 1 -b 16 recordings/take.wav` records in the right format and shows a level meter. Press Ctrl+C to stop.
- Audacity (free): level meter, waveform, easy trimming; export as WAV 16-bit then `just convert` to resample.
- OBS Studio: camera, screen and microphone together.
- Audio Hijack or BlackHole: only if you need to capture system audio too, for example the remote side of a call that the app does not record.

### Method G: live transcription with whisper-stream

`just live` prints the transcription while you speak: it waits for a pause, then transcribes the last utterance (up to 30 s). It is meant for watching the text appear in real time, for example to check that a term comes out right, not for producing the final file: its segments are decoded without context and without the vocabulary prompt, so they are less accurate than an offline pass. It listens to the same input as `just record`: the macOS default one, or `MIC_DEVICE`. Press Ctrl+C to stop. The session is kept anyway, as `transcripts/live-<date>.txt` and `recordings/live-<date>.wav` (the full-quality take is in `recordings/originals/`), so `just transcribe live-<date>` gives you the proper offline transcript of what you just said. `just` itself prints `error: interrupted by SIGINT` after the two "saved" lines: that is just reporting the Ctrl+C, the files are complete.

## 9. Transcribe

```bash
just transcribe 2026-10-28-notes                 # recordings/2026-10-28-notes.wav
just transcribe-file ~/Downloads/meeting.mp4     # any file: convert + transcribe + export, name from the file
just transcribe-file ~/Downloads/meeting.mp4 2026-10-28-meeting --max-len 80   # with a name and extra flags
```

`just transcribe-file` stops when `recordings/<name>.wav` already exists: give another name, or run `just transcribe <name>` to transcribe that recording again.

What `scripts/transcribe.sh` runs:

```bash
vendor/whisper.cpp/build/bin/whisper-cli \
  --model models/ggml-large-v3-turbo.bin \
  --file recordings/2026-10-28-notes.wav \
  --language en \
  --threads 8 \
  --vad --vad-model models/ggml-silero-v6.2.0.bin --vad-speech-pad-ms 500 \
  --print-progress \
  --output-txt --output-srt --output-json-full \
  --output-file transcripts/2026-10-28-notes \
  --prompt "$(cat config/lang/en/prompt.txt)"
```

Why each flag is there:

- `--language en`: a fixed language (`WHISPER_LANG`), so there is no detection and no drift into another language.
- `--threads 8`: CPU threads for the parts that stay on the CPU.
- `--vad`, `--vad-model`, `--vad-speech-pad-ms 500`: transcribe only the detected speech, and keep half a second around each span.
- `--output-json-full`: JSON with every token and its probability, for the confidence marks.
- `--prompt`: your vocabulary prompt, or `prompt.example.txt` when you have no `prompt.txt` yet.

Defaults that are already right and therefore not passed: beam search with 5 beams (`--beam-size 5`), flash attention on, temperature fallback on, timestamps on. The `system_info` line in the log shows `MTL` and `COREML = 0`, confirming the Metal GPU path.

Outputs in `transcripts/`:

- `<name>.txt`: one segment per line, no timestamps. The text to read or paste.
- `<name>.srt`: numbered segments with start and end times. Subtitles, or a way to find a moment in the recording.
- `<name>.json`: the same segments with millisecond offsets, every token with its probability, plus the parameters used. `just stats` and `just export` read it.
- `<name>.log`: a header with the date, whisper.cpp version, model, prompt, language and extra flags that produced the transcript, then everything whisper-cli printed, including the timings at the end. Running `just transcribe` again on the same name says so and overwrites all four files.

Extra flags pass through. Examples: `just transcribe name --max-len 80 --split-on-word` for shorter lines; `just transcribe name --print-confidence` to colour low-confidence words in the terminal; `WHISPER_PROMPT=/dev/null just transcribe name` to disable the vocabulary prompt; `WHISPER_LANG=it just transcribe meeting` for another language.

The vocabulary prompt is a short paragraph in the language of the recording that mentions the names and the foreign terms you use. Whisper treats it as text that came "just before" the audio, so it copies the spelling. Each language directory ships a generic `prompt.example.txt`; `just prompt` copies it to `config/lang/<language>/prompt.txt`, git-ignored, which is the file to edit with your own vocabulary: a project's names, people, products. `just transcribe` uses your `prompt.txt` when it exists and the example otherwise, and `just check` says which. Keep it under about 200 words. In the test run it fixed the spelling of a company name and of a word that whisper had invented, at the cost of longer segments. `WHISPER_PROMPT=path/to/other.txt` selects another file, so you can keep one per subject; `WHISPER_PROMPT=/dev/null` disables it.

Whisper also drops most hesitations ("um", "uh", "you know" said as a crutch) because its training data is clean text. To count them, the prompt has to contain some: `just transcribe-verbatim name` surrounds the prompt with the fillers listed in `config/lang/<language>/fillers.txt`, and whisper keeps them. Use that when you want the hesitations in the text, the normal prompt when you want clean text.

Everything language-specific is in `config/lang/<code>/` (`en` and `it` are shipped): the fillers, the smoke test sentence, the example prompt. `WHISPER_LANG=it just transcribe meeting` uses the Italian ones; a language without a directory still transcribes, with no prompt and no filler count. Adding a language is three small files, see `config/lang/README.md`.

## 10. Analyze and export

**Stats**, the numbers of a recording:

```bash
just stats 2026-10-28-notes
# language, duration and speaking time (the rest is pauses), words, words per minute both over the
# whole recording and while speaking, pauses longer than 2 s,
# the fillers of that language (um, uh, like, you know, I mean, ... for English),
# and the mean token confidence with the segments below 0.6, with their position
```

The two paces differ by the pauses: a big gap between them means long silences between fast sentences. Filler counts are reliable only on a `just transcribe-verbatim` take (section 9); the list is `config/lang/<language>/fillers.txt`, picked by the language recorded in the transcript, and you add your own crutch words there. The confidence is whisper's own probability for each token; segments with a low mean are where names, mumbled words or crosstalk usually hide, so they are the places to listen to again. `LOW_CONFIDENCE` (0.6) is the threshold. `STATS_TARGET_WPM` is optional: set it to a number of words per minute and the pace line says when the recording is more than 15% faster or slower than that. `--pause`, `--target-wpm` and `--low-confidence` can be passed directly to `uv run python -I scripts/transcript-stats.py transcripts/x.json`.

**Export**, one Markdown file with everything:

```bash
just export 2026-10-28-notes
# scripts/export.sh writes transcripts/2026-10-28-notes.md
```

The file starts with what produced the transcript (date, whisper.cpp version, model, prompt, language, flags, taken from the log), then the stats block, then the text as one `[mm:ss] text` line per segment, so a position in the audio can be cited; segments below the confidence threshold carry a `[?]` mark after the time. It is the file to paste into a chat, a note, a document or an LLM prompt, together with whatever instructions fit your use: summarize, extract decisions, translate. The `.txt` is there when you want the bare text.

```bash
just export-all
# every transcript exported, then transcripts/INDEX.md: one row per transcript with the date it was
# transcribed, language, duration, words, whisper.cpp version and the files present, newest first
```

`INDEX.md` is the place to look when the folder has grown: each name links to its `.md` export. Next to the `.md`, `just export` also writes `<name>.timestamps.txt`, the `[mm:ss] text` lines alone, for when plain text with positions is all you need.

**Recheck**, a second opinion where whisper was unsure:

```bash
WHISPER_MODEL=large-v3 just models      # once: the full model, 2.9 GiB, into models/
just recheck 2026-10-28-notes
# scripts/recheck.sh writes transcripts/2026-10-28-notes.recheck.md
```

Every segment that `just stats` lists under confidence is cut out of the recording (half a second of context on each side) and transcribed again on its own with `large-v3`, the same encoder with the full 32-layer decoder instead of the 4 of turbo. The result is a table with the time, the confidence, the original text and the second reading. It is not applied to the transcript: the two decoders disagree exactly where the audio is hard, so the table tells you where to listen and gives you an alternative, not a verdict. With no low-confidence segment the command says so and writes nothing. `RECHECK_MODEL` picks another model, `LOW_CONFIDENCE` the threshold.

## 11. Tuning

Only change settings when a transcript shows a problem. The defaults in the recipe handled the test audio without errors.

| Symptom                                         | Try                                                                                                  |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| A name or technical term is always misspelled   | Add it to your prompt (`just prompt`), in a natural sentence                                         |
| Sentences very long, hard to read               | `--max-len 100 --split-on-word` (display only, decoding is unchanged)                                |
| The same phrase repeated several times in a row | `--max-context 0` (do not feed previous text back), then `--entropy-thold 2.8`, then `--no-fallback` |
| Text appears during silences or music           | VAD is on by default; raise `--vad-threshold 0.6`, or `--no-speech-thold 0.8`                        |
| First or last word of sentences missing         | `--vad-speech-pad-ms 800`, or drop `--vad` for that file                                             |
| Foreign sentences come out translated           | Keep `--language` fixed; the prompt should be in the same language                                   |
| Mixed languages in one file                     | No setting handles it: `WHISPER_LANG=auto` detects one language at the start and keeps it            |
| Too slow                                        | `--no-fallback` (skips retries at higher temperature), or `WHISPER_MODEL=large-v3-turbo-q5_0`        |
| Want a time for every token, not only a segment | `--dtw large.v3.turbo --no-flash-attn` adds `t_dtw` to the JSON tokens; flash attention disables DTW |
| Want low-confidence words highlighted           | `--print-confidence` (terminal only)                                                                 |
| Want an English version                         | `--translate` writes English instead of the spoken language                                          |

One pitfall measured during setup: `--no-timestamps` changes the decoding, not only the output, and in the test it dropped half a sentence at a segment boundary. Keep timestamps on and use the `.txt` output, which has none.

Threads: the GPU does most of the work, so `--threads 8` versus the default 4 changes little. Leave it.

## 12. Optional: Core ML, server, alternatives

### Core ML encoder on the Neural Engine

whisper.cpp can run the encoder on the Apple Neural Engine through Core ML, which the project reports as up to 3x faster than CPU for the encoder; on top of Metal the gain is smaller and the decoder is unchanged. The conversion needs the full Xcode app (for the `coremlc` compiler, which the Command Line Tools do not include), a Python that coremltools supports (9.0 supports up to 3.13, not the 3.15 pinned for the project) and about ten minutes.

```bash
# once: install Xcode from the App Store, then
sudo xcode-select -s /Applications/Xcode.app
just coreml
# scripts/coreml.sh, inside vendor/whisper.cpp:
#   uv run --no-project --python 3.13 --with-requirements models/requirements-coreml.txt \
#     sh ./models/generate-coreml-model.sh large-v3-turbo
#   cmake ... -DWHISPER_COREML=1 && cmake --build ...
```

uv downloads Python 3.13 if needed and installs torch, coremltools, openai-whisper and ane_transformers in a cached throwaway environment; the upstream script finds that interpreter as `python3` on its PATH. Nothing is added to the project `.venv`.

The first transcription after that compiles the model for the device and can take minutes; later runs are fast. The upstream script writes the `.mlmodelc` folder into `vendor/whisper.cpp/models/`; `scripts/coreml.sh` moves it to `models/`, next to the ggml file, where whisper looks for it. `just build` and `just rebuild` keep Core ML on as long as that folder is there; delete it and run `just build` to turn Core ML off. ANEForge (linked from the whisper.cpp README) is a newer, faster route to the Neural Engine; it is still experimental and not covered here.

### HTTP server

`vendor/whisper.cpp/build/bin/whisper-server -m models/ggml-large-v3-turbo.bin -l en` exposes `POST /inference` on port 8080 with the same options, if you prefer to send files from a script or a browser extension.

### Homebrew formula

`brew install whisper.cpp` (the formula was called `whisper-cpp` before) installs a prebuilt 1.9.5 (bottle inspected on 2026-10-27): `whisper-cli`, `whisper-stream`, `whisper-server`, `whisper-bench`, `whisper-quantize` and a few more, with the Metal and Accelerate backends. For plain transcription it is equivalent to the source build. It lacks, compared to the checkout:

- Core ML: the bottle is not linked against the CoreML framework, so the Neural Engine path is unavailable.
- The model download scripts (`download-ggml-model.sh`, `download-vad-model.sh`): models must be fetched by hand from Hugging Face.
- The conversion scripts and their requirements (`generate-coreml-model.sh`, `convert-*-to-ggml.py`, `convert-whisper-to-coreml.py`).
- Samples, per-example READMEs, `grammars/`, bindings.
- Version choice and build flags: it is whatever Homebrew bottles.

The recipes in this repository expect the source tree in `WHISPER_DIR`, so the formula is an ad hoc alternative, not a drop-in.

## 13. Scenarios

### S1. Voice note to text

`just record 2026-10-28-idea`, speak, press `q`. `just transcribe 2026-10-28-idea`, then `just export 2026-10-28-idea` and paste `transcripts/2026-10-28-idea.md` into your notes or into an LLM with "turn this into a clean paragraph". A minute of audio takes a few seconds.

### S2. A meeting recording

Download the Meet, Zoom or Teams file and run `just transcribe-file ~/Downloads/meeting.mp4 2026-10-28-meeting`: convert, transcribe and export in one go. Put the participants' names and the project terms in your prompt first (`just prompt`, then edit `config/lang/en/prompt.txt`), or keep a file per project and pass it with `WHISPER_PROMPT=config/lang/en/prompt-acme.txt`. The speakers come out as one stream of text; the `[mm:ss]` lines of the export let you find who said what by listening at that position, and the `[?]` marks point at the crosstalk. An hour takes about 3 minutes.

### S3. A hard recording

Background noise, a phone across the room, two people talking over each other: `just stats` shows a low mean confidence and a list of segments. Run `just recheck name` and open `transcripts/name.recheck.md`: where turbo and `large-v3` agree, the text is almost certainly right; where they differ, listen at that `[mm:ss]`. Add the names you hear to your prompt and transcribe again if there are many.

### S4. A long recording, several files

Record several times during the day without transcribing. In the evening: `just transcribe-all` does the ones without a transcript, `just export-all` writes the exports and `transcripts/INDEX.md`, where duration and word count per file give the quick look.

### S5. Recording away from the Mac

Record with Voice Memos on the iPhone. When back, the memo is in Voice Memos on the Mac: drag it to `~/Downloads`, `just convert ~/Downloads/Memo.m4a 2026-10-30-walk`, continue as usual. Expect a few more errors from the distance to the phone; the vocabulary prompt still helps.

### S6. Checking terminology live

`just live`, then say the names and foreign terms you use and watch what comes out. Fix your prompt (`just prompt`) for the ones that fail. The session is saved as `live-<date>`, so `just transcribe live-<date>` gives the offline version with the prompt applied.

### S7. Subtitles for a video

`just convert video.mp4 video`, `just transcribe video --max-len 60 --split-on-word` for subtitle-sized lines; `transcripts/video.srt` loads in any player or editor. `--translate` produces English subtitles from another language.

### S8. Another language

English is the default. `WHISPER_LANG=it just transcribe interview` for an Italian file: the Italian example prompt, fillers and smoke test come with it, and `WHISPER_LANG=it just prompt` creates your Italian vocabulary file. To use Italian by default, export `WHISPER_LANG=it` in your shell profile.

Every other language takes its code the same way: `WHISPER_LANG=fr`, `de`, `es`, `ja` and so on. whisper.cpp `v1.9.5` knows 100 language codes. A language without a directory in `config/lang/` transcribes with no vocabulary prompt and no filler count; `config/lang/README.md` says how to add one.

When you do not know the language of a file, `WHISPER_LANG=auto` detects it once, at the beginning of the file, and uses it for the whole file. No vocabulary prompt is applied; `just stats` still counts the fillers when the detected language has a directory in `config/lang/`.

### S9. Counting fillers and hesitations

Transcribe the same audio twice: `just transcribe 2026-10-30-full` for clean text, `just transcribe-verbatim 2026-10-30-full-verbatim` on a copy of the WAV (`cp recordings/2026-10-30-full.wav recordings/2026-10-30-full-verbatim.wav`) for the fillers. `just stats 2026-10-30-full-verbatim` lists them with counts; the `[mm:ss]` lines of `just export` show where they cluster. Add your own crutch words to `config/lang/<language>/fillers.txt`.

## 14. FAQ

**Does anything leave the Mac?** No. Models are downloaded once from Hugging Face; audio and transcripts stay in `recordings/` and `transcripts/`, both git-ignored. Whatever you paste the export into afterwards is your choice.

**Why large-v3-turbo and not large-v3?** Same encoder, decoder cut from 32 to 4 layers: about half the parameters, several times faster decoding, and in OpenAI's and the community's measurements only a small accuracy loss, mostly on low-resource languages. English and Italian are among the well-covered languages. If a file looks worse than expected, `WHISPER_MODEL=large-v3 just transcribe name` tries the full model on the same file in a few more minutes (after `WHISPER_MODEL=large-v3 just models`).

**Why not the Hugging Face files directly?** The Hugging Face repository holds PyTorch and safetensors weights for the Transformers library. whisper.cpp needs its own `ggml` binary; the project converts the official weights and publishes them at `ggerganov/whisper.cpp` on Hugging Face, which is what the download script fetches. Converting yourself (`models/convert-pt-to-ggml.py`) gives the same file.

**Is Metal actually used?** Yes, by default. The log shows `MTL : EMBED_LIBRARY = 1` and, at the end, `ggml_metal_free`. `--no-gpu` forces the CPU, useful only to compare.

**Do I need Core ML?** No. It speeds up the encoder on the Neural Engine, but Metal already transcribes 40 minutes in about 2 minutes. It requires the full Xcode app. See section 12.

**How much memory?** About 2 GB peak for whisper-cli with this model. Anything else can keep running.

**Why 16 kHz mono?** Whisper was trained on 16 kHz audio, so higher sample rates add no accuracy, only size. whisper-cli resamples flac, mp3, ogg and wav by itself but cannot read m4a, mp4 or mov. Converting everything with ffmpeg gives every step the same format. The 16 kHz file sounds duller than the source: to listen, use the file in `recordings/originals/`, which `just play` picks by itself.

**What is VAD and should I keep it on?** Voice activity detection: the Silero model marks where speech is, and whisper transcribes only those spans. It removes hallucinated text in silences and speeds things up. Keep it on. If a file loses the first word of sentences, raise `--vad-speech-pad-ms`.

**The transcript repeats a sentence many times.** The decoder got stuck, a known Whisper failure on long files with silence or noise. VAD prevents most of it; `--max-context 0` prevents the previous text from being fed back; `--no-fallback` and a higher `--entropy-thold` are the next steps. Also trim long silences at the start and end of the recording.

**The filler count is zero but I know I say "um" a lot.** Whisper removes hesitations by default. Transcribe that file with `just transcribe-verbatim`, which puts the language's fillers in the prompt and makes the model keep them; then `just stats` counts them. Expect approximate spellings: the list in `config/lang/<language>/fillers.txt` has the common ones, add yours.

**Where is the m4a I converted?** In `recordings/originals/`, copied by `just convert`; git-ignored like the rest of `recordings/`. The full-quality takes of `just record` and `just live` are there too.

**Names and foreign words are wrong.** Put them in your prompt (`just prompt`, then edit `config/lang/<language>/prompt.txt`) inside a short sentence in the recording's language. The prompt biases the first window strongly and later ones less; `--carry-initial-prompt` repeats it for every window if a term is still wrong late in the file.

**Can it tell who is speaking?** Only for two-channel stereo recordings (`--diarize`, one speaker per channel) or with the English-only tinydiarize model. For a normal meeting recording the answer is no: use the `[mm:ss]` positions and the audio.

**Does the text carry timestamps?** Yes, one per segment. The `.srt` and `.json` files have the start and end of each segment, and `just export` writes the text as `[mm:ss]` lines. Segments follow the pauses in the speech, so there is no fixed interval; `--max-len` makes them shorter, and section 11 has the flags for a time on every token.

**Can I get the transcript in English?** `--translate` outputs English. Quality is good for understanding, not for publication.

**Which segments should I double-check?** The ones `just stats` lists under confidence and the lines marked `[?]` in the export: whisper was unsure there. Names, numbers and overlapping voices are the usual causes. `just recheck` gives you a second reading of exactly those segments by the full `large-v3` model, side by side with the original.

**How long does the first run take?** The model loads in about half a second from an SSD. There is no warm-up on the Metal path. The Core ML path, if enabled, compiles the model on the first run and can take minutes once.

**The recording is silent.** Microphone permission for the terminal app (section 7), muted input, or the wrong `MIC_DEVICE`. `just devices` lists the inputs; the level line after `just record` shows the problem.

**Can I use AirPods?** For listening yes. As the recording microphone, avoid them: the Bluetooth voice codec is narrowband and accuracy drops.

**How do I update whisper.cpp?** `just versions` shows the releases, `just upgrade vX.Y.Z` switches, rebuilds and runs the smoke test, `just pin` records the new commit. Stay on release tags unless you need a fix that is only on `master` (section 4). Models stay valid across versions; re-download only if the `models/README.md` checksum changes.

**Where is the full list of flags?** `vendor/whisper.cpp/build/bin/whisper-cli -h`, and `examples/cli/README.md` in the whisper.cpp tree.

**Do I need bash as my shell?** No. Keep `zsh`, or use `bash`: `just` runs every recipe in bash, and each script starts bash through its shebang. Running a script directly, `scripts/transcribe.sh take1`, works from zsh, bash, fish or anything else. The only thing that does not work is forcing another interpreter, `zsh scripts/transcribe.sh`, and the script says so.

**Does it run on an Intel Mac or on Linux?** Not as is. The transcription pipeline is portable bash, but recording and device listing use a Swift program built on the macOS AVFoundation framework, the smoke test uses `say`, dependencies come from Homebrew, and the build expects Metal. The scripts stop with a clear message on another platform.

**Why uv, and why `-I`?** uv pins and installs the interpreter (`.python-version`), creates `.venv`, and runs scripts with it, so the result does not depend on whichever `python3` Homebrew or macOS put on the PATH. `-I` is Python's isolated mode: it ignores the current directory and user site-packages, so a stray `json.py` next to a downloaded file cannot be imported by accident. The scripts use the standard library only.

## 15. Cheat sheet

```bash
# setup
just deps                                    # check the tools, offer to install the missing ones (Homebrew required)
just deps install                            # same, no question
just setup                                   # everything, once
just lint                                    # shellcheck + /bin/bash 3.2 parse of scripts/
just python                                  # uv python install + uv sync (Python 3.15)
just versions                                # whisper.cpp releases, checkout, recorded commit
just status                                  # checkout vs recorded, build and smoke test state, models
just upgrade v1.9.6                          # switch release, build, smoke test
just pin                                     # commit the new submodule commit as the pin
just check                                   # what is installed and where
just prompt                                  # create config/lang/en/prompt.txt, your vocabulary
just test                                    # synthesized sentence in WHISPER_LANG through convert, transcribe, stats, export

# audio in (recordings/<name>.wav, 16 kHz mono)
just devices                                 # [0] MacBook Pro Microphone (default)
just record 2026-10-28-notes                 # p pauses, q stops; full quality in recordings/originals/ (FLAC)
just record check 5                          # 5 seconds, stops alone
MIC_DEVICE=1 just record take                # another input than the macOS default, by index
MIC_DEVICE="USB Microphone" just record take # or by name
just convert file.m4a name                   # QuickTime, Voice Memos, Meet, Zoom, mov, mp4, mp3
just play name                               # the full-quality original when there is one

# transcribe (transcripts/<name>.{txt,srt,json,log})
just transcribe name                         # language, VAD, vocabulary prompt
just transcribe-file ~/Downloads/x.m4a       # any file: convert + transcribe + export
just transcribe-verbatim name                # same, keeps fillers for `just stats`
just transcribe name --max-len 80 --split-on-word
WHISPER_LANG=it just transcribe name         # another language
WHISPER_PROMPT=/dev/null just transcribe name
WHISPER_MODEL=large-v3 just transcribe name  # full model, after WHISPER_MODEL=large-v3 just models
just transcribe-all                          # everything not yet transcribed
just live                                    # whisper-stream, Ctrl+C stops; saved as live-<date>
just bench

# analyze and export
just stats name                              # duration, speaking time, wpm, pauses, fillers, confidence
STATS_TARGET_WPM=130 just stats name         # same, with the pace compared with a target
just export name                             # transcripts/name.md (settings, stats, [mm:ss] lines, [?] marks) + name.timestamps.txt
just export-all                              # every export plus transcripts/INDEX.md
just recheck name                            # [?] segments read again by large-v3 (once: WHISPER_MODEL=large-v3 just models)
uv run python -I scripts/transcript-stats.py transcripts/name.json --target-wpm 130 --pause 1.5 --low-confidence 0.5

# housekeeping
just format-docs                             # Prettier on the Markdown files
just check-docs                              # fail when a Markdown file is not formatted
just clean                                   # remove the transcripts (asks first); recordings are kept

# without just: same scripts, same env overrides
scripts/transcribe.sh name --max-len 100
WHISPER_REF=v1.9.4 scripts/checkout.sh && scripts/build.sh

# raw whisper-cli, same as the recipe
vendor/whisper.cpp/build/bin/whisper-cli -m models/ggml-large-v3-turbo.bin \
  -f recordings/name.wav -l en -t 8 --vad -vm models/ggml-silero-v6.2.0.bin -vp 500 \
  -otxt -osrt -ojf -of transcripts/name --prompt "$(cat config/lang/en/prompt.txt)"

# raw recorder (built by the first `just record` or `just devices`)
.build/mic-capture devices                                            # inputs
.build/mic-capture record default out.wav [seconds]                   # record at the device's rate, 24-bit; an index or a name in place of default

# raw ffmpeg
ffmpeg -i in.m4a -vn -ar 16000 -ac 1 -c:a pcm_s16le out.wav           # convert
ffmpeg -i out.wav -af volumedetect -f null - 2>&1 | grep volume        # levels

# useful whisper-cli flags
-l en            language          -bs 5           beam size (default)
--vad -vm FILE   voice activity    -vp MS          padding around speech
--prompt "..."   vocabulary        -mc 0           no text carried between windows
-nf              no fallback       -et 2.8         entropy threshold for retries
-ml N -sow       shorter lines     -tr             translate to English
-oj -ojf         json, full json   -dtw large.v3.turbo -nfa   token times
-pc              confidence colours -ng            CPU only
```

## 16. Sources

- whisper.cpp repository and README (build, Core ML, VAD, stream, quantization): https://github.com/ggml-org/whisper.cpp
- whisper.cpp model list and checksums: https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md
- Converted ggml models: https://huggingface.co/ggerganov/whisper.cpp
- Silero VAD models for whisper.cpp: https://huggingface.co/ggml-org/whisper-vad
- Model card, architecture and caveats: https://huggingface.co/openai/whisper-large-v3-turbo
- whisper-cli options: `examples/cli/cli.cpp` and `examples/cli/README.md` in the whisper.cpp tree
- Simon Willison's notes on whisper.cpp on macOS: https://til.simonwillison.net/macos/whisper-cpp
- Community notes on repetition and hallucination in long recordings: https://github.com/ggml-org/whisper.cpp/discussions/1490 and https://localaimaster.com/blog/whisper-hallucination-fix
- Apple Silicon benchmarks for whisper.cpp with Metal: https://www.promptquorum.com/local-llms/apple-silicon-whisper-metal-benchmark
- coremltools supported Python versions: https://pypi.org/project/coremltools/
