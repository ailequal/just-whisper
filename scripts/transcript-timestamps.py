#!/usr/bin/env -S uv run python -I
"""Print a whisper-cli JSON transcript as one line per segment, prefixed with its start time.

    uv run python -I scripts/transcript-timestamps.py transcripts/<name>.json [--low-confidence 0.6]

Output lines look like `[12:34] text of the segment`, so a position in the audio can be cited.
With token data in the JSON (whisper-cli --output-json-full), segments whose mean token
probability is below the threshold get a `[?]` mark after the time. With --list-low, only those
segments are printed, as tab-separated `from_ms to_ms confidence text` (for scripts/recheck.sh).
Standard library only.
"""

import argparse
import json
import sys


def segment_confidence(segment):
    probs = [t["p"] for t in segment.get("tokens", []) if not t.get("text", "").startswith("[_") and "p" in t]
    return sum(probs) / len(probs) if probs else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("transcript", help="JSON file written by whisper-cli -oj or -ojf")
    parser.add_argument("--low-confidence", type=float, default=0.6, help="mark segments with a mean token probability below this (default 0.6)")
    parser.add_argument("--list-low", action="store_true", help="print only the low-confidence segments as tab-separated from_ms, to_ms, confidence, text")
    args = parser.parse_args()

    with open(args.transcript, encoding="utf-8") as fh:
        data = json.load(fh)
    if "transcription" not in data:
        sys.exit(f"{args.transcript}: not a whisper-cli JSON transcript (no 'transcription' key; run whisper-cli with -oj)")
    segments = data["transcription"]
    if not segments and not args.list_low:
        print("(no speech detected)")
    for seg in segments:
        text = seg["text"].strip()
        if not text:
            continue
        confidence = segment_confidence(seg)
        low = confidence is not None and confidence < args.low_confidence
        if args.list_low:
            if low:
                print(f"{seg['offsets']['from']}\t{seg['offsets']['to']}\t{confidence:.2f}\t{text}")
            continue
        start = int(seg["offsets"]["from"] // 1000)
        print(f"[{start // 60:02d}:{start % 60:02d}]{' [?]' if low else ''} {text}")


if __name__ == "__main__":
    main()
