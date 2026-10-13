#!/usr/bin/env python3
"""Freeze CDC checklist text for review; generate Swift offline from the frozen JSON.

Run --fetch only during an intentional source review. No network at app runtime.
"""
import argparse
import hashlib
import html
import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "ReferenceData/Milestones"
VERSION = "cdc-2026-10-10"
PAGES = {2: "2-months", 4: "4-months", 6: "6-months", 9: "9-months",
         12: "1-year", 15: "15-months", 18: "18-months", 24: "2-years"}
DOMAINS = {"Social/Emotional": "social", "Language/Communication": "language",
           "Cognitive": "cognitive", "Movement/Physical": "movement"}


def clean(markup):
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", markup)).split())


def fetch():
    DATA.mkdir(parents=True, exist_ok=True)
    pages, skills = [], []
    for month, slug in PAGES.items():
        url = f"https://www.cdc.gov/act-early/milestones/{slug}.html"
        raw = urllib.request.urlopen(url, timeout=30).read()
        source = raw.decode("utf-8")
        page = {"months": month, "url": url, "retrieved": "2026-10-10",
                "sha256": hashlib.sha256(raw).hexdigest()}
        updated = re.search(r"Updated:\s*</[^>]+>\s*([^<]+)", source)
        page["updated"] = clean(updated[1]) if updated else "See source page"
        counts = {}
        for prefix, domain in DOMAINS.items():
            groups = re.findall(r"<h3[^>]*>(" + re.escape(prefix) + r".*?)</h3>\s*<ul[^>]*>(.*?)</ul>", source, re.S)
            assert len(groups) == 1, (url, domain, len(groups))
            items = re.findall(r"<li[^>]*>(.*?)</li>", groups[0][1], re.S)
            counts[domain] = len(items)
            assert items, (url, domain)
            for item in items:
                anchor = re.search(r'href="#([^\"]+)"', item)
                key = anchor[1].lower() if anchor else re.sub(r"[^a-z0-9]+", "-", clean(item).lower()).strip("-")
                skills.append({"id": f"cdc-{month}-{key}", "months": month,
                               "domain": domain, "title": clean(item), "sourceURL": url,
                               "sourceVersion": VERSION})
        page["counts"] = counts
        pages.append(page)
    assert len(set(s["id"] for s in skills)) == len(skills)
    (DATA / "cdc-checklists.json").write_text(json.dumps({"version": VERSION, "pages": pages, "skills": skills}, indent=2, ensure_ascii=False) + "\n")


def generate():
    catalog = json.loads((DATA / "cdc-checklists.json").read_text())
    lines = ["// Generated from reviewed ReferenceData/Milestones/cdc-checklists.json.",
             "// Source: CDC. See that directory for provenance and reuse attribution.",
             "extension MilestoneCatalog {", "    static let cdcSkills: [MilestoneSkill] = ["]
    for skill in catalog["skills"]:
        quote = lambda key: json.dumps(skill[key], ensure_ascii=False)
        lines.append(f'        .init(id: {quote("id")}, title: {quote("title")}, domain: .{skill["domain"]}, months: {skill["months"]}, sourceVersion: {quote("sourceVersion")}, sourceURL: {quote("sourceURL")}),')
    lines += ["    ]", "}", ""]
    (ROOT / "BabyActivityRecorder/Domain/MilestoneCatalogData.swift").write_text("\n".join(lines))
    print(f'Generated {len(catalog["skills"])} skills in {len(catalog["pages"])} CDC chapters.')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fetch", action="store_true")
    args = parser.parse_args()
    if args.fetch:
        fetch()
    generate()
