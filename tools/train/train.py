"""Corpus -> per-role n-gram models + holdout jitter fixture.

Usage: uv run --project tools/train python tools/train/train.py
1. Group-level 80/20 split (seeded) BEFORE any jitter. Groups = source performance (drums) or the
   authored figure the pattern is built on (pitched), so transposed near-copies never straddle the split.
2. Trigram model per role on train patterns, interpolated absolute discounting (D=0.75) over an
   add-one unigram; written ARPA-style (log p of seen grams + backoff weight per context, natural log).
3. 300 jittered holdout items (75 per role) -> LoopCore/Tests/LoopCoreTests/Fixtures/holdout.json.
Tokens (plan §3b): pitched "pos:interval" (16th in bar, scale-degree step from previous note; first
note "^degree"), drums "pos:pad". Sequences padded with <s> <s> ... </s>.
"""
import json
import math
import random
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEED = 2026
ORDER = 3
D = 0.75
ROLES = ("drums", "bass", "chords", "melody")
ITEMS_PER_ROLE = 75
MODEL_DIR = ROOT / "LoopCore/Sources/LoopCore/Resources/model"
FIXTURE = ROOT / "LoopCore/Tests/LoopCoreTests/Fixtures/holdout.json"
STEPS = {"major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10]}


def load(role):
    path = ROOT / ("data/corpus/drums/groove.jsonl" if role == "drums" else f"data/corpus/{role}/patterns.jsonl")
    pats = [json.loads(l) for l in path.read_text().splitlines()]
    for p in pats:  # one note format everywhere: [tick, duration, pitch|pad, velocity]
        if role == "drums":
            p["notes"] = [[t, 60, pad, v] for t, pad, v in p["notes"]]
    return pats


def split(pats, rng):
    groups = sorted({p["group"] for p in pats})
    rng.shuffle(groups)
    hold, n = set(), 0
    for g in groups:
        if n >= 0.2 * len(pats):
            break
        hold.add(g)
        n += sum(p["group"] == g for p in pats)
    return [p for p in pats if p["group"] not in hold], [p for p in pats if p["group"] in hold]


def degree(pitch, key):
    rel = pitch - key["root"]
    return (rel // 12) * 7 + STEPS[key["mode"]].index(rel % 12)


def tokens(p):
    out, prev = [], None
    for t, _, x, _ in sorted(p["notes"], key=lambda n: (n[0], n[2])):
        pos = (t % 1920) // 120
        if p["role"] == "drums":
            out.append(f"{pos}:{x}")
            continue
        d = degree(x, p["key"])
        out.append(f"{pos}:^{d % 7}" if prev is None else f"{pos}:{max(-14, min(14, d - prev)):+d}")
        prev = d
    return ["<s>"] * (ORDER - 1) + out + ["</s>"]


def train(seqs):
    counts = [Counter() for _ in range(ORDER + 1)]  # counts[n][gram tuple]
    for s in seqs:
        for n in range(1, ORDER + 1):
            for i in range(len(s) - n + 1):
                g = tuple(s[i:i + n])
                if g[-1] != "<s>":
                    counts[n][g] += 1
    vocab = sorted({g[0] for g in counts[1]} | {"<unk>"})
    total = sum(counts[1].values())
    logp, backoff = {}, {}
    prob = {(w,): (counts[1].get((w,), 0) + 1) / (total + len(vocab)) for w in vocab}

    def lower(g):  # interpolated lower-order probability for any gram
        if g in prob:
            return prob[g]
        ctx = g[:-1]
        return backoff_w.get(ctx, 1.0) * lower(g[1:])

    backoff_w = {}
    for n in range(2, ORDER + 1):
        ctx_total, ctx_types = Counter(), Counter()
        for g, c in counts[n].items():
            ctx_total[g[:-1]] += c
            ctx_types[g[:-1]] += 1
        for ctx in ctx_total:
            backoff_w[ctx] = D * ctx_types[ctx] / ctx_total[ctx]
        for g, c in counts[n].items():
            prob[g] = (c - D) / ctx_total[g[:-1]] + backoff_w[g[:-1]] * lower(g[1:])
    for g, p in prob.items():
        logp[" ".join(g)] = round(math.log(p), 4)
    for ctx, b in backoff_w.items():
        backoff[" ".join(ctx)] = round(math.log(b), 4)
    return {"order": ORDER, "smoothing": f"interpolated absolute discounting D={D}, add-one unigram",
            "log": "natural", "vocab": vocab, "logp": logp, "backoff": backoff}


def logprob(m, w, ctx):
    ctx = list(ctx)[-(m["order"] - 1):]
    g = " ".join(ctx + [w])
    if g in m["logp"]:
        return m["logp"][g]
    if not ctx:
        return m["logp"]["<unk>"]
    return m["backoff"].get(" ".join(ctx), 0.0) + logprob(m, w, ctx[1:])


def jitter(p, rng):
    notes = [list(n) for n in p["notes"]]
    span = p["bars"] * 1920
    sigma_ms = rng.uniform(10, 80)
    ms_to_ticks = p["bpm"] / 60 * 480 / 1000
    out = []
    for t, d, x, v in notes:
        r = rng.random()
        if r < 0.025:  # drop
            continue
        off = max(-80.0, min(80.0, rng.gauss(0, sigma_ms)))
        if p["role"] != "drums" and rng.random() < 0.10:
            x += rng.choice([-2, -1, 1, 2])
        out.append([min(span - 1, max(0, t + round(off * ms_to_ticks))), d, x, v])
        if r > 0.975:  # add a stray note
            src = rng.choice(notes)
            x2 = rng.randrange(6) if p["role"] == "drums" else src[2] + rng.randint(-2, 2)
            out.append([rng.randrange(span), src[1], x2, 70])
    return sorted(out), round(sigma_ms, 1)


def main():
    rng = random.Random(SEED)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    items = []
    for role in ROLES:
        tr, ho = split(load(role), rng)
        m = train([tokens(p) for p in tr])
        m["role"] = role
        path = MODEL_DIR / f"{role}.json"
        path.write_text(json.dumps(m, separators=(",", ":"), sort_keys=True))
        size = path.stat().st_size
        assert size <= 1_000_000, (role, size)
        # self-check: backoff model is a proper distribution in a seen and an unseen context
        for ctx in (tokens(tr[0])[1:3], ["9:+5", "3:-7"]):
            z = sum(math.exp(logprob(m, w, ctx)) for w in m["vocab"])
            assert abs(z - 1) < 0.01, (role, ctx, z)
        ho_ll = [logprob(m, w, s[i - 2:i]) for s in map(tokens, ho) for i, w in enumerate(s) if i >= 2]
        print(f"{role}: {len(tr)} train / {len(ho)} holdout patterns, vocab {len(m['vocab'])}, "
              f"{len(m['logp'])} grams, {size / 1024:.0f} KB, holdout ppl {math.exp(-sum(ho_ll) / len(ho_ll)):.1f}")
        order = rng.sample(ho, len(ho))
        for k in range(ITEMS_PER_ROLE):
            p = order[k % len(order)]
            jit, sigma = jitter(p, rng)
            items.append({"role": role, "patternId": p["id"], "key": p.get("key"), "progression": p.get("progression"),
                          "bpm": p["bpm"], "bars": p["bars"], "jitterSigmaMs": sigma,
                          "original": p["notes"], "jittered": jit})
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(json.dumps({"ppq": 480, "noteFormat": "[tick, duration, pitch|pad, velocity]",
                                   "items": items}, separators=(",", ":")))
    print(f"fixture: {len(items)} items, {FIXTURE.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
