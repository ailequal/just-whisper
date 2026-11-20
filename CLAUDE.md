# Working in this repository

Read `README.md` first, then `GUIDE.md` for the full workflow. Keep these conventions:

- Python runs only through uv (`uv run python -I ...`), never `python3` directly. The version is pinned in `.python-version`.
- The `justfile` is a launcher with no logic: every command with logic calls the script of the same name in `scripts/` (a few recipes reuse another script with a flag or an environment variable, and `python`, `lint`, `format-docs`, `check-docs`, `clean` are one-liners), and the scripts source `scripts/lib/common.sh` for settings and helpers. Put logic in the scripts, keep them bash 3.2 compatible (macOS `/bin/bash`), and run `just lint` after editing them.
- whisper.cpp is the git submodule `vendor/whisper.cpp`; the commit recorded for it is the pinned version (a release tag). Do not switch it to `master` or move the pin without being asked; `just versions`, `just upgrade <tag>` and `just pin` are the tools for that, and a new pin also means updating the version named in `README.md` and `GUIDE.md`. Models live in `models/`, git-ignored.
- The target platform is macOS on Apple Silicon only.
- The microphone is recorded by `scripts/mic-capture.swift`, compiled on first use into `.build/` (git-ignored). Do not capture with ffmpeg's `avfoundation` input: it loses audio. The take is kept at full quality in `recordings/originals/` and the 16 kHz mono file is derived from it.
- `recordings/` and `transcripts/` hold personal recordings and their transcripts, git-ignored: never delete, rewrite or commit their contents. Tests and experiments point `WHISPER_RECORDINGS_DIR` and `WHISPER_TRANSCRIPTS_DIR` at a temporary directory, as `scripts/test.sh` does.
- The tool is general purpose: record or convert audio, transcribe it, export the text. Do not tie it to one use of the transcripts (a talk, a meeting, notes); such things belong to the user's other repositories.
- When a command, flag, path or default changes, update `README.md` and `GUIDE.md` in the same change, then run `just format-docs` and `just check-docs`.
- Commits are conventional commits (`type(scope): description`) with an `Assisted-by: <agent>/<model>` trailer when an AI agent helped.
- Language-specific data (fillers, smoke test sentence, example prompt) lives in `config/lang/<code>/`; the personal `prompt.txt` there is git-ignored. Do not hardcode a language in the scripts: read `WHISPER_LANG` and these files.
