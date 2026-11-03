"""Convert the Groove MIDI Dataset (CC BY 4.0) into 2-bar drum patterns.

Usage: uv run --project tools/train python -I tools/train/groove.py data/raw/groove/groove
Writes data/corpus/drums/groove.jsonl (one pattern per line) and the source file list into licenses.json. Raw files are parsed as data only (mido), never executed.
"""
import csv
import json
import sys
from pathlib import Path

import mido

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data/corpus/drums/groove.jsonl"
STEP = 120  # 16th at PPQ 480
WINDOWS_PER_FILE = 2  # ponytail: first 2 distinct 2-bar windows per performance, raise if drums underfit

# GM / Roland TD-11 note -> pad: 0 kick, 1 snare, 2 closed hat, 3 open hat, 4 tom, 5 crash/ride
PADS = {
    35: 0, 36: 0,
    37: 1, 38: 1, 39: 1, 40: 1,
    22: 2, 42: 2, 44: 2,
    26: 3, 46: 3,
    41: 4, 43: 4, 45: 4, 47: 4, 48: 4, 50: 4, 58: 4,
    49: 5, 51: 5, 52: 5, 53: 5, 55: 5, 57: 5, 59: 5,
}


def hits(path: Path) -> dict[tuple[int, int], int]:
    """(16th step, pad) -> max velocity, quantized to the 16th grid."""
    mid = mido.MidiFile(path)
    q = mid.ticks_per_beat / 4
    out: dict[tuple[int, int], int] = {}
    for track in mid.tracks:
        t = 0
        for msg in track:
            t += msg.time
            if msg.type == "note_on" and msg.velocity > 0 and msg.note in PADS:
                k = (round(t / q), PADS[msg.note])
                out[k] = max(out.get(k, 0), msg.velocity)
    return out


def main(raw: Path) -> None:
    rows = [r for r in csv.DictReader(open(raw / "info.csv"))
            if r["beat_type"] == "beat" and r["time_signature"] == "4-4"]
    lines = []
    for r in sorted(rows, key=lambda r: r["midi_filename"]):
        h = hits(raw / r["midi_filename"])
        if not h:
            continue
        last_bar = max(s for s, _ in h) // 16
        seen = set()
        for start in range(0, last_bar - 1, 2):  # full 2-bar windows only
            win = sorted((s - start * 16, p, v) for (s, p), v in h.items() if start * 16 <= s < (start + 2) * 16)
            key = tuple((s, p) for s, p, _ in win)
            pads = {p for _, p, _ in win}
            if len(win) < 6 or not ({0, 1} & pads) or key in seen:
                continue
            seen.add(key)
            lines.append({"id": f"groove/{r['id']}/{start}", "group": r["midi_filename"], "role": "drums",
                          "source": r["midi_filename"], "bpm": int(r["bpm"]), "bars": 2,
                          "notes": [[s * STEP, p, v] for s, p, v in win]})
            if len(seen) == WINDOWS_PER_FILE:
                break
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(json.dumps(l, separators=(",", ":")) + "\n" for l in lines))
    lic_path = ROOT / "licenses.json"
    lic = json.loads(lic_path.read_text())
    next(e for e in lic if e["path"] == "data/corpus/drums/groove.jsonl")["files"] = sorted({l["source"] for l in lines})
    lic_path.write_text(json.dumps(lic, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(lines)} drum patterns from {len({l['group'] for l in lines})} files -> {OUT}")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
