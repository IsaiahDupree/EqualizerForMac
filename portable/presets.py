#!/usr/bin/env python3
"""Read Sonance EQ v1 presets and the actual bundled AutoEq headphone database.

This is control-plane/preset tooling, not a real-time audio backend or desktop UI.
It uses only the Python standard library and never modifies the source database.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sqlite3
import sys


FILTERS = ("peaking", "lowShelf", "highShelf", "lowPass", "highPass", "notch", "bandPass", "allPass")
SLOPES = (6, 12, 18, 24, 36, 48, 72, 96)
DATABASE = Path(__file__).resolve().parents[1] / "Sources/SonanceEQ/Resources/autoeq.sqlite"


def number(value, label: str, minimum: float, maximum: float | None = None) -> float:
    if type(value) not in (int, float):
        raise ValueError(f"{label} must be a finite number")
    try:
        result = float(value)
    except (ValueError, OverflowError) as exc:
        raise ValueError(f"{label} must be a finite number") from exc
    if not math.isfinite(result) or result < minimum or (maximum is not None and result > maximum):
        raise ValueError(f"{label} is outside the supported range")
    return result


def validate(value: dict) -> dict:
    """Normalize the shipping version-1 shape, including its legacy slope default."""
    keys = {"app", "version", "name", "preampDb", "bands"}
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError("expected the Sonance EQ version-1 preset fields")
    if value["app"] != "SonanceEQ" or type(value["version"]) is not int or value["version"] != 1:
        raise ValueError("unsupported preset app or version")
    if not isinstance(value["name"], str) or not value["name"].strip() or len(value["name"]) > 512:
        raise ValueError("preset name must contain 1 to 512 characters")
    if not isinstance(value["bands"], list) or len(value["bands"]) > 32:
        raise ValueError("expected at most 32 bands")
    bands, sections = [], 0
    required = {"type", "frequency", "gain", "q", "enabled"}
    for index, item in enumerate(value["bands"]):
        if not isinstance(item, dict) or not required <= set(item) or set(item) - required - {"slopeDbPerOct"}:
            raise ValueError(f"invalid fields in band {index}")
        if item["type"] not in FILTERS or type(item["enabled"]) is not bool:
            raise ValueError(f"invalid type or enabled flag in band {index}")
        band = {
            "type": item["type"],
            "frequency": number(item["frequency"], "frequency", 1),
            "gain": number(item["gain"], "gain", -60, 60),
            "q": number(item["q"], "Q", 0.0001, 100),
            "enabled": item["enabled"],
            "slopeDbPerOct": number(item.get("slopeDbPerOct", 12), "slope", 0),
        }
        cut = band["type"] in ("lowPass", "highPass")
        if cut and band["slopeDbPerOct"] not in SLOPES:
            raise ValueError(f"unsupported cut slope in band {index}")
        if band["enabled"]:
            sections += math.ceil(band["slopeDbPerOct"] / 12) if cut else 1
        bands.append(band)
    if sections > 32:
        raise ValueError("preset exceeds the 32-section processing capacity")
    return {"app": "SonanceEQ", "version": 1, "name": value["name"],
            "preampDb": number(value["preampDb"], "preamp", -60, 60), "bands": bands}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def load(path: Path) -> dict:
    if path.stat().st_size > 1024 * 1024:
        raise ValueError("preset exceeds 1 MiB")
    return validate(json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object))


def database(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def search(path: Path, query: str, limit: int = 20) -> list[dict]:
    if type(limit) is not int or not 1 <= limit <= 100:
        raise ValueError("search limit must be between 1 and 100")
    if not isinstance(query, str) or len(query) > 256:
        raise ValueError("search query must contain at most 256 characters")
    pattern = "%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
    connection = database(path)
    try:
        rows = connection.execute(
            "SELECT id,model,brand,category,source,preamp FROM presets "
            "WHERE model LIKE ? ESCAPE '\\' ORDER BY model COLLATE NOCASE,id LIMIT ?", (pattern, limit)
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        connection.close()


def export_headphone(path: Path, preset_id: int) -> dict:
    if type(preset_id) is not int or preset_id < 1:
        raise ValueError("headphone ID must be a positive integer")
    connection = database(path)
    try:
        row = connection.execute("SELECT model,source,preamp,filters FROM presets WHERE id=?", (preset_id,)).fetchone()
    finally:
        connection.close()
    if row is None:
        raise ValueError(f"headphone preset {preset_id} does not exist")
    filters = json.loads(row["filters"], object_pairs_hook=unique_object)
    if not isinstance(filters, list):
        raise ValueError("headphone filters must be a list")
    bands = [{**item, "enabled": True, "slopeDbPerOct": 12} for item in filters]
    return validate({"app": "SonanceEQ", "version": 1, "name": f'{row["model"]} · {row["source"]}',
                     "preampDb": row["preamp"], "bands": bands})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("validate", help="validate and normalize an existing Mac preset")
    check.add_argument("preset", type=Path)
    find = sub.add_parser("search", help="search the real bundled headphone library")
    find.add_argument("query")
    find.add_argument("--database", type=Path, default=DATABASE)
    find.add_argument("--limit", type=int, default=20)
    export = sub.add_parser("export", help="write a real headphone correction as Sonance EQ preset JSON")
    export.add_argument("preset_id", type=int)
    export.add_argument("--database", type=Path, default=DATABASE)
    args = parser.parse_args()
    try:
        if args.command == "validate":
            result = load(args.preset)
        elif args.command == "search":
            result = search(args.database, args.query, args.limit)
        else:
            result = export_headphone(args.database, args.preset_id)
        print(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False))
    except (OSError, ValueError, TypeError, sqlite3.Error) as exc:
        print(f"Preset error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
