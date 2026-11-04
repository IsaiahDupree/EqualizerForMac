#!/usr/bin/env python3
"""Report real preset coverage; optionally check Beats' lineup and OPRA for updates.

Read-only. Never creates a preset, substitutes another generation, downloads review
measurements, or changes the shipping catalog. No app-runtime network dependency.
"""
import argparse
import json
import sqlite3
import sys
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
from contextlib import closing

from build_autoeq_db import OUT, OPRA, SUPPLEMENTAL, search_key


class BeatsProducts(HTMLParser):
    """Read named product links; ignore accessories, colors, shop buttons and duplicates."""
    def __init__(self):
        super().__init__()
        self.products = {}
        self.href = None
        self.parts = []

    def handle_starttag(self, tag, attributes):
        if tag == "a":
            self.href = dict(attributes).get("href")
            self.parts = []

    def handle_data(self, data):
        if self.href:
            self.parts.append(data)

    def handle_endtag(self, tag):
        if tag != "a" or not self.href:
            return
        path = urlparse(self.href).path.rstrip("/")
        label = " ".join(" ".join(self.parts).split())
        if (path.startswith(("/headphones/", "/earbuds/")) and "cushion" not in path
                and label.startswith(("Beats ", "Powerbeats ")) and len(label) < 60):
            self.products[path] = label
        self.href = None


def coverage(database=OUT):
    inventory = json.loads((Path(SUPPLEMENTAL) / "coverage.json").read_text())
    with closing(sqlite3.connect(f"file:{Path(database).resolve()}?mode=ro", uri=True)) as db:
        rows = db.execute("SELECT p.id,p.brand,m.display_model,m.search_key "
                          "FROM presets p JOIN preset_metadata m ON p.id=m.preset_id").fetchall()
    results = []
    for device in inventory["devices"]:
        key = search_key(device["query"])
        matches = [(r[0], r[2]) for r in rows if r[1] == device["brand"] and key in r[3]]
        results.append({**device, "status": "available" if matches else "needs_preset_data",
                        "preset_count": len(matches), "matched_models": sorted({r[1] for r in matches})})
    return {"reviewed": inventory["reviewed"], "total_presets": len(rows),
            "beats_presets": sum(r[1] == "Beats" for r in rows), "devices": results}


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "SonanceEQ-CatalogAudit/1.0"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.read()


def check_upstream(report):
    parser = BeatsProducts()
    parser.feed(fetch("https://www.beatsbydre.com/us/products").decode())
    if not parser.products:
        raise ValueError("Beats' product page returned no named headphones/earbuds; coverage is unknown")
    known = {urlparse(d["product_url"]).path.rstrip("/"): d["model"]
             for d in report["devices"] if d["scope"] == "current_beats"}
    new = {path: name for path, name in parser.products.items() if path not in known}
    commits = json.loads(fetch("https://api.github.com/repos/opra-project/OPRA/commits?per_page=1"))
    latest = commits[0]["sha"]
    pinned = json.loads((Path(OPRA) / "manifest.json").read_text())["source_commit"]
    return {"beats_product_url": "https://www.beatsbydre.com/us/products",
            "current_beats_products": parser.products, "unreviewed_beats_products": new,
            "opra_pinned_commit": pinned, "opra_latest_commit": latest,
            "opra_needs_review": latest != pinned}


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--database", default=OUT)
    cli.add_argument("--json", action="store_true", help="Print the complete evidence-linked report")
    cli.add_argument("--check-upstream", action="store_true", help="Read current official Beats products and OPRA revision")
    cli.add_argument("--fail-on-new-release", action="store_true", help="Exit 1 for an unreviewed product/source revision")
    args = cli.parse_args()
    if args.fail_on_new_release and not args.check_upstream:
        cli.error("--fail-on-new-release requires --check-upstream")
    try:
        report = coverage(args.database)
        if args.check_upstream:
            report["upstream"] = check_upstream(report)
    except (OSError, ValueError, sqlite3.Error, KeyError, IndexError) as error:
        print(f"Coverage unknown: {error}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(f"{report['total_presets']:,} presets; {report['beats_presets']} Beats corrections")
        for device in report["devices"]:
            print(f"{device['status']:18} {device['model']} ({device['preset_count']} presets)")
        if "upstream" in report:
            print(json.dumps(report["upstream"], indent=2))
    upstream = report.get("upstream", {})
    return int(args.fail_on_new_release and bool(upstream.get("unreviewed_beats_products")
                                                or upstream.get("opra_needs_review")))


if __name__ == "__main__":
    sys.exit(main())
