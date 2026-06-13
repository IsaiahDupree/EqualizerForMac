#!/usr/bin/env python3
"""
Build the shippable AutoEq preset database for Sonance EQ.

Walks the (git-ignored, study-only) AutoEq clone at references/AutoEq/results and turns every
`<model> ParametricEQ.txt` into a row in Sources/SonanceEQ/Resources/autoeq.sqlite. The app bundles
that single SQLite file — the 8,850 source text files never ship.

AutoEq is MIT-licensed (Jaakko Pasanen); shipping this derived data requires attribution (see
references/README.md and the in-app About/credits).

Run from the repo root:
    python3 Tools/build_autoeq_db.py
"""
import json
import os
import re
import sqlite3
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(REPO, "references", "AutoEq", "results")
OUT = os.path.join(REPO, "Sources", "SonanceEQ", "Resources", "autoeq.sqlite")

# AutoEq parametric filter token -> our FilterType rawValue (see DSP/Biquad.swift).
TYPE_MAP = {"PK": "peaking", "LSC": "lowShelf", "HSC": "highShelf"}
CATEGORIES = ("in-ear", "over-ear", "earbud")

PREAMP_RE = re.compile(r"^Preamp:\s*(-?[\d.]+)\s*dB", re.M)
FILTER_RE = re.compile(
    r"^Filter\s+\d+:\s+ON\s+(\w+)\s+Fc\s+([\d.]+)\s+Hz\s+Gain\s+(-?[\d.]+)\s+dB\s+Q\s+([\d.]+)",
    re.M,
)


def parse(path):
    """Return (preamp, [filter dicts]) or None if the file has no usable filters."""
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    pre = PREAMP_RE.search(text)
    preamp = float(pre.group(1)) if pre else 0.0
    filters = []
    for tok, fc, gain, q in FILTER_RE.findall(text):
        ftype = TYPE_MAP.get(tok)
        if ftype is None:
            continue  # skip unknown shapes rather than guessing
        filters.append({
            "type": ftype,
            "frequency": float(fc),
            "gain": float(gain),
            "q": float(q),
        })
    return (preamp, filters) if filters else None


def split_category(segment):
    """`segment` is the form-factor dir, sometimes prefixed by a measurement rig
    (e.g. 'GRAS 43AG-7 over-ear'). Return (category, rig)."""
    for cat in CATEGORIES:
        if segment == cat:
            return cat, ""
        if segment.endswith(" " + cat):
            return cat, segment[: -len(cat) - 1].strip()
    return "other", segment


def main():
    if not os.path.isdir(RESULTS):
        sys.exit(f"AutoEq results not found at {RESULTS}\n"
                 f"Clone it first: git clone https://github.com/jaakkopasanen/AutoEq references/AutoEq")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    if os.path.exists(OUT):
        os.remove(OUT)

    db = sqlite3.connect(OUT)
    db.execute("""
        CREATE TABLE presets (
            id       INTEGER PRIMARY KEY,
            model    TEXT NOT NULL,
            brand    TEXT NOT NULL,
            category TEXT NOT NULL,
            source   TEXT NOT NULL,
            rig      TEXT NOT NULL,
            preamp   REAL NOT NULL,
            filters  TEXT NOT NULL
        )
    """)

    rows = []
    skipped = 0
    for dirpath, _dirs, files in os.walk(RESULTS):
        for fn in files:
            if not fn.endswith(" ParametricEQ.txt"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), RESULTS).split(os.sep)
            if len(rel) != 4:
                skipped += 1
                continue
            source, ff_segment, model, _file = rel
            parsed = parse(os.path.join(dirpath, fn))
            if parsed is None:
                skipped += 1
                continue
            preamp, filters = parsed
            category, rig = split_category(ff_segment)
            brand = model.split(" ", 1)[0]
            rows.append((model, brand, category, source, rig, preamp, json.dumps(filters, separators=(",", ":"))))

    db.executemany(
        "INSERT INTO presets (model, brand, category, source, rig, preamp, filters) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        rows,
    )
    # Case-insensitive search index on model + brand.
    db.execute("CREATE INDEX idx_model ON presets (model COLLATE NOCASE)")
    db.execute("CREATE INDEX idx_brand ON presets (brand COLLATE NOCASE)")
    db.commit()

    count = db.execute("SELECT COUNT(*) FROM presets").fetchone()[0]
    sources = db.execute("SELECT COUNT(DISTINCT source) FROM presets").fetchone()[0]
    db.execute("VACUUM")
    db.close()

    size_mb = os.path.getsize(OUT) / 1e6
    print(f"Wrote {count} presets from {sources} sources → {OUT} ({size_mb:.1f} MB)")
    if skipped:
        print(f"Skipped {skipped} files (unexpected path depth or no filters)")


if __name__ == "__main__":
    main()
