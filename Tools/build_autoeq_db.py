#!/usr/bin/env python3
"""
Build the shippable AutoEq preset database for Sonance EQ.

Walks the (git-ignored, study-only) AutoEq clone at references/AutoEq/results and turns every
`<model> ParametricEQ.txt` into a row in Sources/SonanceEQ/Resources/autoeq.sqlite. The app bundles
that single SQLite file — the source text files never ship. Reviewed additions in
Tools/headphone_presets/manifest.json are appended after the AutoEq catalog.

AutoEq is MIT-licensed (Jaakko Pasanen); shipping this derived data requires attribution (see
references/README.md and the in-app About/credits).

Run from the repo root:
    python3 Tools/build_autoeq_db.py
"""
import argparse
import hashlib
import json
import math
import os
import re
import sqlite3
import sys
import tempfile
import unicodedata
from contextlib import closing

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(REPO, "references", "AutoEq", "results")
OUT = os.path.join(REPO, "Sources", "SonanceEQ", "Resources", "autoeq.sqlite")
SUPPLEMENTAL = os.path.join(REPO, "Tools", "headphone_presets")
OPRA = os.path.join(SUPPLEMENTAL, "opra")

# AutoEq parametric filter token -> our FilterType rawValue (see DSP/Biquad.swift).
TYPE_MAP = {"PK": "peaking", "LSC": "lowShelf", "HSC": "highShelf"}
CATEGORIES = ("in-ear", "over-ear", "earbud")

PREAMP_RE = re.compile(r"^Preamp:\s*([+-]?[\d.]+)\s*dB", re.M)
FILTER_RE = re.compile(
    r"^Filter\s+\d+:\s+ON\s+(\w+)\s+Fc\s+([\d.]+)\s+Hz\s+Gain\s+([+-]?[\d.]+)\s+dB\s+Q\s+([\d.]+)",
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


def supplemental_rows():
    """Import pinned, attributed preset data; never substitute another headphone's curve."""
    with open(os.path.join(SUPPLEMENTAL, "manifest.json"), encoding="utf-8") as fh:
        entries = json.load(fh)
    rows = []
    for entry in entries:
        path = os.path.join(SUPPLEMENTAL, entry["file"])
        with open(path, "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        if digest != entry["sha256"]:
            raise ValueError(f"Preset source checksum changed: {entry['file']}")
        parsed = parse(path)
        if parsed is None or len(parsed[1]) != entry["filter_count"]:
            raise ValueError(f"Incomplete supplemental preset: {entry['file']}")
        preamp, filters = parsed
        if not math.isfinite(preamp) or preamp > 0 or any(
            not (math.isfinite(f["frequency"]) and 20 <= f["frequency"] <= 20_000
                 and math.isfinite(f["gain"]) and math.isfinite(f["q"]) and f["q"] > 0)
            for f in filters
        ):
            raise ValueError(f"Invalid supplemental preset: {entry['file']}")
        rows.append((entry["model"], entry["brand"], entry["category"], entry["source"],
                     entry["rig"], preamp, json.dumps(filters, separators=(",", ":"))))
    return rows


def search_key(text):
    """Match spacing/punctuation variants without conflating Buds and Buds +."""
    text = unicodedata.normalize("NFKD", text.lower().replace("+", "plus"))
    return "".join(c for c in text if c in "abcdefghijklmnopqrstuvwxyz0123456789")


def display_model(model):
    """Correct labels only. Original measurement names/conditions remain in presets."""
    if not model.startswith(("Apple ", "Beats ")):
        return model
    model = model.replace("Beats Beats Powerbeats", "Beats Powerbeats")
    model = model.replace("Beats PowerBeats", "Beats Powerbeats")
    model = model.replace("Apple AirPod 4", "Apple AirPods 4")
    model = model.replace("Apple Airpods", "Apple AirPods")
    return re.sub(r"\b(AirPods|Pro|Solo|Studio)([234])\b", r"\1 \2", model)


def opra_rows():
    """Read reviewed, checksum-pinned data, not external application code."""
    with open(os.path.join(OPRA, "manifest.json"), encoding="utf-8") as fh:
        manifest = json.load(fh)
    for file, checksum in [("OPRA-LICENSE.txt", "license_sha256"), ("OPRA-logo.png", "logo_sha256")]:
        with open(os.path.join(REPO, "Sources", "SonanceEQ", "Resources", file), "rb") as fh:
            if hashlib.sha256(fh.read()).hexdigest() != manifest[checksum]:
                raise ValueError(f"OPRA attribution asset changed: {file}")
    rows, provenance, portable = [], [], []
    type_map = {"peak_dip": "peaking", "low_shelf": "lowShelf", "high_shelf": "highShelf"}
    for entry in manifest["entries"]:
        path = os.path.join(OPRA, entry["file"])
        with open(path, "rb") as fh:
            raw = fh.read()
        if hashlib.sha256(raw).hexdigest() != entry["sha256"]:
            raise ValueError(f"OPRA source checksum changed: {entry['file']}")
        data = json.loads(raw)
        if data["type"] != "parametric_eq" or data["author"] != entry["author"]:
            raise ValueError(f"Unexpected OPRA data: {entry['file']}")
        parameters = data["parameters"]
        filters = [{"type": type_map[f["type"]], "frequency": f["frequency"],
                    "gain": f["gain_db"], "q": f["q"]} for f in parameters["bands"]]
        preamp = entry.get("preamp_db", parameters["gain_db"])
        if (len(filters) != entry["filter_count"] or not math.isfinite(preamp) or preamp > 0
                or preamp > parameters["gain_db"]
                or any(not (math.isfinite(f["frequency"]) and 20 <= f["frequency"] <= 20_000
                           and math.isfinite(f["gain"]) and math.isfinite(f["q"]) and f["q"] > 0)
                       for f in filters)):
            raise ValueError(f"Invalid OPRA preset: {entry['file']}")
        source = f"{data['author']} · {data['details']} · OPRA"
        rows.append((entry["model"], entry["brand"], entry["category"], source, "", preamp,
                     json.dumps(filters, separators=(",", ":"))))
        provenance.append((entry["source_url"], manifest["license"]))
        portable.append({"id": entry["id"], "model": entry["model"], "source_url": entry["source_url"],
                         "license": manifest["license"], "preamp_db": preamp, "data": data})
    return rows, provenance, {"repository": manifest["repository"], "license": manifest["license"],
                              "license_url": manifest["license_url"], "changes": manifest["changes"],
                              "entries": portable}


def write_catalog(output, rows, provenance):
    """Replace the output atomically; an invalid input cannot destroy the shipping DB."""
    fd, staging = tempfile.mkstemp(prefix="autoeq-", suffix=".sqlite", dir=os.path.dirname(output))
    os.close(fd)
    try:
        with closing(sqlite3.connect(staging)) as db:
            db.execute("""CREATE TABLE presets (
                id INTEGER PRIMARY KEY, model TEXT NOT NULL, brand TEXT NOT NULL,
                category TEXT NOT NULL, source TEXT NOT NULL, rig TEXT NOT NULL,
                preamp REAL NOT NULL, filters TEXT NOT NULL)""")
            db.executemany("INSERT INTO presets (model,brand,category,source,rig,preamp,filters) "
                           "VALUES (?,?,?,?,?,?,?)", rows)
            db.execute("""CREATE TABLE preset_metadata (
                preset_id INTEGER PRIMARY KEY REFERENCES presets(id),
                display_model TEXT NOT NULL, category TEXT NOT NULL, search_key TEXT NOT NULL,
                source_url TEXT, data_license TEXT)""")
            metadata = []
            for index, row in enumerate(rows, start=1):
                model, brand, category = row[:3]
                label = display_model(model)
                # Upstream classifies these earphones as over-ear. Keep its raw row intact.
                if model == "Beats Powerbeats 2 Wireless":
                    category = "in-ear"
                url, license_name = provenance.get(index, (None, None))
                metadata.append((index, label, category,
                                 search_key(model) + " " + search_key(label) + " " + search_key(brand),
                                 url, license_name))
            db.executemany("INSERT INTO preset_metadata VALUES (?,?,?,?,?,?)", metadata)
            db.execute("CREATE INDEX idx_model ON presets (model COLLATE NOCASE)")
            db.execute("CREATE INDEX idx_brand ON presets (brand COLLATE NOCASE)")
            db.commit()
            db.execute("VACUUM")
            if db.execute("PRAGMA integrity_check").fetchone() != ("ok",):
                raise ValueError("Generated catalog failed SQLite integrity check")
        os.replace(staging, output)
    finally:
        if os.path.exists(staging):
            os.remove(staging)


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--results", default=RESULTS, help="Existing AutoEq results directory")
    cli.add_argument("--output", default=OUT, help="Destination SQLite database")
    args = cli.parse_args()
    if not os.path.isdir(args.results):
        sys.exit(f"AutoEq results not found at {args.results}\n"
                 f"Clone it first: git clone https://github.com/jaakkopasanen/AutoEq references/AutoEq")

    additions = supplemental_rows()
    opra, opra_provenance, portable = opra_rows()
    output = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(output), exist_ok=True)

    rows = []
    skipped = 0
    for dirpath, _dirs, files in os.walk(args.results):
        for fn in files:
            if not fn.endswith(" ParametricEQ.txt"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), args.results).split(os.sep)
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

    rows.extend(additions)
    provenance = {}
    with open(os.path.join(SUPPLEMENTAL, "manifest.json"), encoding="utf-8") as fh:
        supplemental_manifest = json.load(fh)
    for index, entry in enumerate(supplemental_manifest, start=len(rows) - len(additions) + 1):
        provenance[index] = (entry["preset_url"], "MIT")
    provenance.update({len(rows) + i: value for i, value in enumerate(opra_provenance, start=1)})
    rows.extend(opra)
    write_catalog(output, rows, provenance)
    # The separately licensed data remains freely accessible outside the Pro feature and App Store.
    portable_path = os.path.join(os.path.dirname(output), "OPRA-Beats.json")
    with open(portable_path, "w", encoding="utf-8") as fh:
        json.dump(portable, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    count, sources = len(rows), len({r[3] for r in rows})

    size_mb = os.path.getsize(output) / 1e6
    print(f"Wrote {count} presets from {sources} sources → {output} ({size_mb:.1f} MB)")
    if skipped:
        print(f"Skipped {skipped} files (unexpected path depth or no filters)")


if __name__ == "__main__":
    main()
