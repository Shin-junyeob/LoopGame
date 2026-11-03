"""Self-authored bass / chords / melody corpus (license: self, written by Claude on the user's behalf).

The musical content is the hand-written figures below (bar-long rhythm/figure strings and melodic
cells, all expressed relative to the current chord / scale). Patterns are expanded deterministically
over keys and progressions, then checked against G3 (every note in scale, onsets on beats 1 and 3
are chord tones). Usage: uv run --project tools/train python tools/train/author.py
Writes data/corpus/<role>/patterns.jsonl.
"""
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEED = 7
PER_ROLE = 130
BAR = 1920
STEP = 120

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]
# (tonic pitch class, mode, weight): mostly C major / A minor, a few others.
KEYS = [(0, "major", 5), (9, "minor", 5), (7, "major", 1), (5, "major", 1), (2, "minor", 1), (4, "minor", 1)]
ROMAN = {"i": 0, "ii": 1, "iii": 2, "iv": 3, "v": 4, "vi": 5, "vii": 6}
PROGS = {
    "major": ["I V vi IV", "I vi IV V", "I IV V I", "ii V I I", "I IV vi V", "vi IV I V", "I iii IV V",
              "IV V iii vi", "I V IV I", "I IV I V", "ii V I vi", "I vi ii V", "IV I V vi", "I V", "I IV", "ii V", "I"],
    "minor": ["i VI III VII", "i iv v i", "i VII VI VII", "i iv VII III", "i VI iv v", "i III VII iv",
              "VI VII i i", "i v VI III", "i VII", "i iv", "i"],
}

# --- bass: 16 slots per bar. R root, 3 third, 5 fifth, 8 octave, w/v scale step above/below root,
# a approach tone (scale neighbour of next bar's root), _ sustain, . rest. Slots 0/8 only chord tones.
BASS = [
    "R_______________", "R_______R_______", "R___R___R___R___", "R_R_R_R_R_R_R_R_",
    "R__R__R_R__R__R_", "R___5___R___5___", "R___5___8___5___", "R_.RR_._R_.RR_._",
    "R__R__5_R__R__a_", "R___3___5___a___", "R___w___3___5___", "8___5___3___a___",
    "R_.R_.R_R_.R_.a_", "R.R.5.R.R.R.5.a.", ".R_R.R_R.R_R.R_a", "R_____R_____R___",
    "R__5__8_R__5__8_", "R_______5___a___", "R_RR__R_R_RR__5_", "R___R_5_R___v___",
    "R_8_R_8_R_8_R_8_", "R__R__R__R__R_R_", "R_______..R_R_a_", "R__.R__.5__.a__.",
    "5___R___..R_3_R_",
]
BASS_FILLS = ["R___5___8_5_3_a_", "R__R__R_5_w_3_a_", "R_______R_5_8_5_", "R___R___R_w_v_a_"]

# --- chords: X voice-led triad, 1/3/5 single chord tones, 8 root an octave up,
# h upper scale neighbour of the previous note (weak slots only).
CHORDS = [
    "X_______________", "X_______X_______", "X___X___X___X___", "X_X_X_X_X_X_X_X_",
    "..X...X...X...X.", "X__X__X___X_X___", "X__X__X_X__X__X_", "1_3_5_3_1_3_5_3_",
    "1_5_8_5_1_5_8_5_", "1__5__8_3__5__8_", "X___.X__X___.X__", "X_.X_.X.X_.X_.X.",
    "X_____X_____X___", "X_______.X_X_X__", "1_3_5_h_5_3_1___", ".X_X.X_X.X_X.X_X",
    "X___X_X_.X__X___", "5_3_1_3_5_3_1_3_", "X_______X___X_X_", "X__.X__.X__.X_X_",
]

# --- melody cells (one bar): "slot:sym". c nearest chord tone, c+/c- nearest chord tone above/below,
# 1/3/5 that chord tone nearest the previous note, +n/-n diatonic steps, s repeat, r rest.
# Strong slots (0, 8) always use chord-tone symbols or rest.
CELLS = {
    "open": [
        "0:5 4:+1 6:-1 8:3 12:-1", "0:3 2:+1 4:+1 8:c 10:-1 12:-1", "0:1 4:3 8:5 12:+1 14:-1",
        "0:c 6:c+ 8:c 12:+2 14:-1", "0:5 2:s 4:+1 6:-2 8:3", "0:r 2:5 4:+1 6:-1 8:3 12:r",
        "0:3 3:s 6:+1 8:5 11:-1 14:-1", "0:1 2:+1 4:+1 6:+1 8:5", "0:c 4:r 6:+1 8:c 10:+1 12:-2",
        "0:5 6:+1 8:5 10:-1 12:-1 14:-1", "0:r 4:3 6:+1 8:5 12:c+", "0:8 4:-1 6:-1 8:5",
    ],
    "mid": [
        "0:c 2:-1 4:-1 6:+1 8:c 12:r", "0:c- 4:+1 8:c+ 10:-1 12:-1 14:-1", "0:3 2:-1 4:+2 6:-1 8:1",
        "0:5 2:+1 4:-1 6:-1 8:3 10:-1 12:+1", "0:c 4:c 8:c+ 12:-1", "0:c 3:+1 6:+1 8:c 14:-1",
        "0:r 2:c 4:+1 6:+1 8:c 12:-1 14:-1", "0:c+ 6:-1 8:c 12:r 14:+1", "0:c 2:s 4:-1 6:-1 8:c- 12:+1",
        "0:3 4:5 6:+1 8:c 10:-1 12:-2", "0:c 1:+1 2:-1 4:-1 8:c 12:+1 13:+1 14:+1",
        "0:5 4:-1 8:3 10:+1 12:+1 14:-1",
    ],
    "end": [
        "0:1", "0:3 4:-1 8:1", "0:c 4:-1 6:-1 8:1 12:r", "0:5 4:+1 6:-1 8:c-",
        "0:3 2:-1 4:-1 8:1 14:r", "0:1 8:r", "0:c 6:-1 8:c- 12:r", "0:5 2:-1 4:-1 6:-1 8:1",
    ],
}
FORMS = {1: ["A"], 2: ["AE", "ME"], 4: ["AMAE", "AAME", "AMME", "MAME"], 8: ["AMAEAMME", "AAMEMAME"]}


def scale_pitches(tonic, mode, lo, hi):
    steps = MAJOR if mode == "major" else MINOR
    return [p for p in range(lo, hi + 1) if (p - tonic) % 12 in steps]


def chord_of(tonic, mode, numeral):
    steps = MAJOR if mode == "major" else MINOR
    d = ROMAN[numeral.lower()]
    root = (tonic + steps[d]) % 12
    third = (steps[(d + 2) % 7] - steps[d]) % 12
    assert third in (3, 4), numeral
    return {"root": root, "quality": "major" if third == 4 else "minor"}


def tones(ch):
    return {(ch["root"] + i) % 12 for i in (0, 4 if ch["quality"] == "major" else 3, 7)}


def fn_pc(ch, f):  # chord function 1/3/5 -> pitch class
    return (ch["root"] + {"1": 0, "3": 4 if ch["quality"] == "major" else 3, "5": 7, "8": 0}[f]) % 12


def nearest(cands, target):
    return min(cands, key=lambda p: (abs(p - target), -p))


def slots(fig):
    """Figure string -> [(slot, sym, length_in_slots)]."""
    out = []
    for i, c in enumerate(fig):
        if c not in "_.":
            n = 1
            while i + n < 16 and fig[i + n] == "_":
                n += 1
            out.append((i, c, n))
    return out


def bass_bar(fig, ch, next_ch, scale, prev):
    r = 36 + (ch["root"] - 36) % 12
    third = r + (4 if ch["quality"] == "major" else 3)
    notes = []
    for s, c, n in slots(fig):
        if c == "a":
            nr = 36 + (next_ch["root"] - 36) % 12
            p = nearest([q for q in scale if abs(q - nr) in (1, 2) and q != nr], prev or r)
        elif c == "w":
            p = min(q for q in scale if q > r)
        elif c == "v":
            p = max(q for q in scale if q < r)
        else:
            p = {"R": r, "3": third, "5": r + 7, "8": r + 12}[c]
        notes.append((s, n, p))
        prev = p
    return notes, prev


def voicing(ch, prev):
    pcs = tones(ch)
    pool = [p for p in range(55, 77) if p % 12 in pcs]
    options = [pool[i:i + 3] for i in range(len(pool) - 2)]
    ref = prev or [60, 64, 67]
    return min(options, key=lambda v: (sum(abs(a - b) for a, b in zip(v, ref)), v[0]))


def chords_bar(fig, ch, scale, prev_block):
    block = voicing(ch, prev_block)
    notes, last = [], block[-1]
    for s, c, n in slots(fig):
        if c == "X":
            notes += [(s, n, p) for p in block]
            last = block[-1]
            continue
        if c == "h":
            p = min(q for q in scale if q > last)
        elif c == "8":
            p = next(q for q in block if q % 12 == ch["root"]) + 12
        else:
            p = next(q for q in block if q % 12 == fn_pc(ch, c))
        notes.append((s, n, p))
        last = p
    return notes, block


def melody_bar(cell, ch, scale, prev):
    pcs = tones(ch)
    ct = [p for p in scale if p % 12 in pcs]
    events = []
    for tok in cell.split():
        s, sym = tok.split(":")
        s, ref = int(s), prev or 67
        if sym == "r":
            events.append((s, None))
            continue
        if sym in ("c", "c+", "c-"):
            c = [p for p in ct if (sym == "c" or (p > ref if sym == "c+" else p < ref))] or ct
            p = nearest(c, ref)
        elif sym in "1358":
            p = nearest([q for q in ct if q % 12 == fn_pc(ch, sym)], ref + (7 if sym == "8" else 0))
        elif sym == "s":
            p = ref
        else:
            i = scale.index(ref) + int(sym)
            if not 0 <= i < len(scale):
                i = scale.index(ref) - int(sym)
            p = scale[i]
        events.append((s, p))
        prev = p
    notes = []
    for k, (s, p) in enumerate(events):
        end = events[k + 1][0] if k + 1 < len(events) else 16
        if p is not None:
            notes.append((s, end - s, p))
    return notes, prev


def g3_ok(notes, tonic, mode, prog):
    steps = MAJOR if mode == "major" else MINOR
    for t, _, p, _ in notes:
        if (p - tonic) % 12 not in steps:
            return False
        if t % BAR in (0, BAR // 2) and p % 12 not in tones(prog[(t // BAR) % len(prog)]):
            return False
    return True


def make(role, rng):
    tonic, mode, _ = rng.choices(KEYS, weights=[k[2] for k in KEYS])[0]
    numerals = rng.choice(PROGS[mode]).split()
    prog = [chord_of(tonic, mode, n) for n in numerals]
    bars = len(prog) * (2 if len(prog) == 4 and rng.random() < 0.25 else 1)
    if len(prog) == 1:
        bars = rng.choice([1, 2])
    notes, state = [], None
    if role == "bass":
        scale = scale_pitches(tonic, mode, 28, 64)
        main, alt = rng.randrange(len(BASS)), rng.randrange(len(BASS))
        fill = rng.choice(BASS_FILLS) if bars >= 4 and rng.random() < 0.5 else None
        group = f"bass/{main}"
        figs = [BASS[alt] if bars == 8 and b >= 4 and b % 2 else BASS[main] for b in range(bars)]
        if fill:
            figs[-1] = fill
    elif role == "chords":
        scale = scale_pitches(tonic, mode, 50, 84)
        main = rng.randrange(len(CHORDS))
        group = f"chords/{main}"
        alt = CHORDS[rng.randrange(len(CHORDS))] if rng.random() < 0.3 else CHORDS[main]
        figs = [alt if b % 4 == 3 else CHORDS[main] for b in range(bars)]
    else:
        scale = scale_pitches(tonic, mode, 60, 81)  # beginner-singable register
        form = rng.choice(FORMS[bars])
        pick = {f: rng.randrange(len(CELLS[{"A": "open", "M": "mid", "E": "end"}[f]])) for f in "AME"}
        group = f"melody/A{pick['A']}"
        figs = [CELLS[{"A": "open", "M": "mid", "E": "end"}[f]][pick[f]] for f in form]
        if bars == 1:
            figs = [CELLS["open"][pick["A"]]]
    for b, fig in enumerate(figs):
        ch, nxt = prog[b % len(prog)], prog[(b + 1) % len(prog)]
        if role == "bass":
            bar_notes, state = bass_bar(fig, ch, nxt, scale, state)
        elif role == "chords":
            bar_notes, state = chords_bar(fig, ch, scale, state)
        else:
            bar_notes, state = melody_bar(fig, ch, scale, state)
        for s, n, p in bar_notes:
            vel = 96 if s in (0, 8) else 84 if s % 4 == 0 else 72
            notes.append([b * BAR + s * STEP, n * STEP, p, vel])
    notes.sort()
    return {"group": group, "role": role, "key": {"root": tonic, "mode": mode}, "progression": prog,
            "numerals": numerals, "bpm": rng.randrange(80, 125, 5), "bars": bars, "notes": notes}


def main():
    rng = random.Random(SEED)
    for role in ("bass", "chords", "melody"):
        seen, out = set(), []
        while len(out) < PER_ROLE:
            p = make(role, rng)
            k = json.dumps([p["key"], p["bars"], p["notes"]])
            if k in seen:
                continue
            if role == "melody" and max(n[2] for n in p["notes"]) - min(n[2] for n in p["notes"]) > 12:
                continue  # keep each melody within an octave
            assert g3_ok(p["notes"], p["key"]["root"], p["key"]["mode"], p["progression"]), p
            seen.add(k)
            out.append({"id": f"{role}/{len(out):03d}", **p})
        path = ROOT / f"data/corpus/{role}/patterns.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(p, separators=(",", ":")) + "\n" for p in out))
        print(role, len(out), "patterns,", len({p["group"] for p in out}), "groups")


if __name__ == "__main__":
    main()
