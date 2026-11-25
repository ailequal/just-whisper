# Changelog

All notable changes to just-whisper are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- whisper.cpp pinned to release `v1.9.6`; the pin was `v1.9.5`.

## [1.2.0] - 2026-11-20

### Added

- Pause and resume while recording, with `p` or the space bar (`just record`).
- Input selection by name in `MIC_DEVICE`.
- macOS default input marked in `just devices`.

### Changed

- `just record` and `just live` record the macOS default input when `MIC_DEVICE` is not set; the default was index `0`.
- Full-quality takes are kept as lossless FLAC in `recordings/originals/<name>.flac`, in place of WAV.
- `just live` gives `whisper-stream` the same input as the recorder.

## [1.1.0] - 2026-11-20

### Added

- Full-quality microphone takes in `recordings/originals/<name>.wav`, at the sample rate and channel count of the device, 24-bit (`just record`, `just live`).
- Elapsed time and peak level shown while recording; warnings for clipped input and lost audio.
- Swift compiler reported by `just check`.

### Changed

- `just record`, `just live` and `just devices` use the Swift recorder `scripts/mic-capture.swift`, compiled on first use into `.build/`, in place of ffmpeg's `avfoundation` input.
- `recordings/<name>.wav` at 16 kHz mono is derived from the full-quality take.
- `just play` plays the file in `recordings/originals/` when there is one.

### Fixed

- Audio lost while recording from the microphone.

## [1.0.0] - 2026-11-17

### Added

- Recording from the microphone with ffmpeg (`just record`), conversion of any audio or video file (`just convert`), playback and device listing; an existing recording is never overwritten.
- Transcription with whisper.cpp and `large-v3-turbo` on Metal, with Silero VAD, a per-language vocabulary prompt and full JSON output (`just transcribe`, `just transcribe-file`, `just transcribe-all`).
- Verbatim mode that keeps hesitations for counting fillers (`just transcribe-verbatim`).
- Live transcription from the microphone with `whisper-stream`, with the session saved as text and audio (`just live`).
- Transcript statistics: duration, speaking time, pace, pauses, fillers and low-confidence segments, with an optional target pace (`just stats`).
- Markdown export with settings, statistics and `[mm:ss]` lines, a timestamped text file, an index of all transcripts (`just export`, `just export-all`).
- Second reading of the low-confidence segments with the full `large-v3` model (`just recheck`).
- Per-language configuration in `config/lang/<code>/`: fillers, smoke test sentence, example prompt; English (the default) and Italian shipped, any other language Whisper supports through `WHISPER_LANG`; personal prompt created by `just prompt`.
- Settings as environment variables, including the folders for recordings, transcripts and models (`WHISPER_RECORDINGS_DIR`, `WHISPER_TRANSCRIPTS_DIR`, `WHISPER_MODELS_DIR`).
- whisper.cpp as the git submodule `vendor/whisper.cpp`, pinned to release `v1.9.5`; `just versions`, `just checkout`, `just upgrade`, `just pin` and `just status` to manage the pin; models kept in `models/` with SHA-1 verification.
- Dependency check and installer for macOS on Apple Silicon with Homebrew (`just deps`, `scripts/deps.sh install`), full setup (`just setup`), environment report (`just check`).
- Smoke test that runs a synthesized sentence in the configured language through convert, transcribe, stats and export, in a temporary directory (`just test`).
- shellcheck and bash 3.2 lint (`just lint`), Prettier checks for the documentation with Node.js 26 LTS.
- Optional Core ML encoder build (`just coreml`), kept by later builds while the encoder is in `models/`.
- README, GUIDE with setup, recording methods, tuning, scenarios, FAQ and cheat sheet; MIT license.

[Unreleased]: https://github.com/ailequal/just-whisper/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/ailequal/just-whisper/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/ailequal/just-whisper/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ailequal/just-whisper/releases/tag/v1.0.0
