#!/usr/bin/env -S uv run python -I
"""Print a Markdown index of every transcript in a directory, one row per JSON file.

    uv run python -I scripts/transcript-index.py transcripts/ > transcripts/INDEX.md

Columns: name, transcribed on (from the .log header), language, duration, words, whisper.cpp version
(from the .log header), and which output files exist. Newest first. Standard library only.
"""

import json
import re
import sys
from pathlib import Path


def words_in(text):
    # same rule as transcript-stats.py: letters, digits and apostrophes form a word
    return len(re.findall(r"[\w'’]+", text))


def transcript_language(data):
    """The language asked for (params), or the detected one when it was 'auto'; silence makes whisper report 'en'."""
    asked = (data.get("params") or {}).get("language") or ""
    detected = (data.get("result") or {}).get("language") or ""
    return detected if asked in ("", "auto") else asked


def fmt_time(ms):
    s = int(ms // 1000)
    return f"{s // 3600:d}:{(s % 3600) // 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60:02d}:{s % 60:02d}"


def log_header(path):
    """Values from the '# key ...' lines scripts/transcribe.sh writes at the top of the log."""
    info = {"date": "", "version": ""}
    if not path.is_file():
        return info
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.startswith("# "):
                break
            m = re.match(r"# transcribed on (\S+ \S+)", line)
            if m:
                info["date"] = m.group(1)
            m = re.match(r"# whisper\.cpp (\S+)", line)
            if m:
                info["version"] = m.group(1)
    return info


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = Path(sys.argv[1])
    rows = []
    for json_path in sorted(folder.glob("*.json")):
        name = json_path.stem
        try:
            with open(json_path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue
        if "transcription" not in data:
            continue
        segments = data["transcription"]
        language = transcript_language(data)
        duration = max((seg["offsets"]["to"] for seg in segments), default=0)
        words = words_in(" ".join(seg["text"] for seg in segments))
        info = log_header(folder / f"{name}.log")
        files = " ".join(ext for ext in ("txt", "srt", "md", "timestamps.txt", "recheck.md") if (folder / f"{name}.{ext}").is_file())
        rows.append((info["date"], name, language, fmt_time(duration), words, info["version"], files))
    rows.sort(key=lambda r: (r[0], r[1]), reverse=True)

    print("# Transcripts")
    print()
    print(f"{len(rows)} transcript{'s' if len(rows) != 1 else ''} in `{folder}/`, newest first. Regenerate with `just export-all`.")
    print()
    print("| Name | Transcribed on | Language | Duration | Words | whisper.cpp | Files |")
    print("| --- | --- | --- | --- | ---: | --- | --- |")
    for date, name, language, duration, words, version, files in rows:
        print(f"| [{name}]({name}.md) | {date} | {language} | {duration} | {words} | {version} | {files} |")


if __name__ == "__main__":
    main()
