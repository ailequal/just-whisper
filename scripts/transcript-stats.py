#!/usr/bin/env -S uv run python -I
"""Speech statistics from a whisper-cli JSON transcript.

Run it through uv, which picks the interpreter pinned in .python-version:

    uv run python -I scripts/transcript-stats.py transcripts/<name>.json
        [--lang-root config/lang] [--fillers FILE] [--pause 2.0] [--target-wpm N] [--low-confidence 0.6]

`just stats <name>` does exactly that. Standard library only, no dependencies.

Prints duration, speaking time, word count, pace (over the whole recording and while speaking),
long pauses, filler words and the segments whose mean token confidence is low. With --target-wpm
the pace is compared with that target; without it the pace is only reported. The fillers list
is read from <lang-root>/<language>/fillers.txt, where the language is the one recorded in the
transcript, unless --fillers names a file. Whisper drops most hesitations unless the prompt
contains some: see `just transcribe-verbatim`. Confidence needs a transcript written with
--output-json-full (the default of `just transcribe`).
"""

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

WORD_CHARS = set("'’")


def words_of(text):
    out, cur = [], []
    for ch in text.lower():
        if ch.isalnum() or ch in WORD_CHARS:
            cur.append(ch)
        elif cur:
            out.append("".join(cur))
            cur = []
    if cur:
        out.append("".join(cur))
    return out


def transcript_language(data):
    """The language asked for (params), or the detected one when it was 'auto'; silence makes whisper report 'en'."""
    asked = (data.get("params") or {}).get("language") or ""
    detected = (data.get("result") or {}).get("language") or ""
    return detected if asked in ("", "auto") else asked


def fmt_time(ms):
    s = int(ms // 1000)
    return f"{s // 60:02d}:{s % 60:02d}"


def load(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if "transcription" not in data:
        sys.exit(f"{path}: not a whisper-cli JSON transcript (no 'transcription' key; run whisper-cli with -oj)")
    segments = data["transcription"]
    language = transcript_language(data)
    return segments, language


def load_fillers(path):
    fillers = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        line = line.strip().lower()
        if line and not line.startswith("#"):
            fillers.append(line)
    return fillers


def segment_confidence(segment):
    """Mean probability of the real tokens of a segment, or None without token data."""
    probs = [t["p"] for t in segment.get("tokens", []) if not t.get("text", "").startswith("[_") and "p" in t]
    return sum(probs) / len(probs) if probs else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("transcript", help="JSON file written by whisper-cli -oj or -ojf")
    parser.add_argument("--lang-root", default="config/lang", help="directory with one <language>/fillers.txt per language (default config/lang)")
    parser.add_argument("--fillers", help="fillers list to use instead of the language's one")
    parser.add_argument("--pause", type=float, default=2.0, help="report pauses longer than this many seconds (default 2.0)")
    parser.add_argument("--target-wpm", type=float, default=None, help="optional target pace in words per minute: the pace line then says when the recording is more than 15%% faster or slower")
    parser.add_argument("--low-confidence", type=float, default=0.6, help="report segments with a mean token probability below this (default 0.6)")
    args = parser.parse_args()

    segments, language = load(args.transcript)
    if not segments:
        print(f"transcript   {args.transcript}")
        print(f"language     {language or 'unknown'}")
        print("speech       none detected: the file is silent, or the VAD found no speech (see the level line of `just record`)")
        return
    text = " ".join(seg["text"].strip() for seg in segments)
    words = words_of(text)
    duration_ms = max(seg["offsets"]["to"] for seg in segments)
    speaking_ms = sum(seg["offsets"]["to"] - seg["offsets"]["from"] for seg in segments)
    minutes = duration_ms / 60000 if duration_ms else 0
    speaking_minutes = speaking_ms / 60000 if speaking_ms else 0
    wpm = len(words) / minutes if minutes else 0
    speaking_wpm = len(words) / speaking_minutes if speaking_minutes else 0

    print(f"transcript   {args.transcript}")
    print(f"language     {language or 'unknown'}")
    print(f"duration     {fmt_time(duration_ms)} ({minutes:.1f} min)")
    print(f"speaking     {fmt_time(speaking_ms)} ({(speaking_ms / duration_ms * 100) if duration_ms else 0:.0f}% of the time, the rest is pauses)")
    print(f"words        {len(words)}")
    target = f" (target {args.target_wpm:.0f})" if args.target_wpm else ""
    print(f"pace         {wpm:.0f} words/min over the whole recording{target}")
    print(f"             {speaking_wpm:.0f} words/min while speaking")
    if args.target_wpm and wpm > args.target_wpm * 1.15:
        print("             faster than target")
    elif args.target_wpm and wpm and wpm < args.target_wpm * 0.85:
        print("             slower than target")

    pauses = []
    for prev, cur in zip(segments, segments[1:]):
        gap = (cur["offsets"]["from"] - prev["offsets"]["to"]) / 1000
        if gap >= args.pause:
            pauses.append((prev["offsets"]["to"], gap, cur["text"].strip()[:60]))
    print(f"pauses       {len(pauses)} longer than {args.pause:.1f}s")
    for at, gap, nxt in pauses:
        print(f"             {fmt_time(at)}  {gap:4.1f}s  before: {nxt}")

    fillers_path = Path(args.fillers) if args.fillers else Path(args.lang_root) / language / "fillers.txt"
    if fillers_path.is_file():
        lowered = " " + " ".join(words) + " "
        counts = Counter()
        for filler in load_fillers(fillers_path):
            n = lowered.count(" " + " ".join(words_of(filler)) + " ")
            if n:
                counts[filler] = n
        total = sum(counts.values())
        print(f"fillers      {total} ({(total / len(words) * 100) if words else 0:.1f}% of words, list: {fillers_path})")
        for filler, n in counts.most_common():
            print(f"             {n:4d}  {filler}")
    else:
        print(f"fillers      not counted: no list at {fillers_path}")

    confidences = [(seg, segment_confidence(seg)) for seg in segments]
    known = [c for _, c in confidences if c is not None]
    if known:
        low = [(seg, c) for seg, c in confidences if c is not None and c < args.low_confidence]
        print(f"confidence   {sum(known) / len(known):.2f} mean over {len(known)} segments, {len(low)} below {args.low_confidence:.2f}")
        for seg, c in low:
            print(f"             {fmt_time(seg['offsets']['from'])}  {c:.2f}  {seg['text'].strip()[:60]}")
    else:
        print("confidence   not available (transcribe with --output-json-full, the default of `just transcribe`)")


if __name__ == "__main__":
    main()
