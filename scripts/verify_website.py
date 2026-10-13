#!/usr/bin/env python3
"""Check the public website payload before GitHub Pages deployment (stdlib only)."""
import json
import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1] / "website"
ORIGIN = "https://swaddle-ios.app"


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.path, self.ids, self.links, self.images = path, set(), [], []
        self.meta, self.canonical, self.h1, self.language = {}, [], 0, None
        self.json_blocks, self.in_json, self.json_text = [], False, ""
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            assert a["id"] not in self.ids, f"Duplicate id in {self.path}: {a['id']}"
            self.ids.add(a["id"])
        if tag == "html": self.language = a.get("lang")
        if tag == "h1": self.h1 += 1
        if tag == "meta": self.meta[a.get("name", a.get("property"))] = a.get("content")
        if tag == "link" and a.get("rel") == "canonical": self.canonical.append(a["href"])
        if tag == "img": self.images.append(a)
        if tag in ("a", "link") and "href" in a: self.links.append(a["href"])
        if tag in ("img", "script") and "src" in a: self.links.append(a["src"])
        if tag == "img" and "srcset" in a:
            self.links.extend(item.strip().split()[0] for item in a["srcset"].split(","))
        if tag == "script" and a.get("type") == "application/ld+json": self.in_json = True

    def handle_data(self, data):
        if self.in_json: self.json_text += data

    def handle_endtag(self, tag):
        if tag == "script" and self.in_json:
            self.json_blocks.append(json.loads(self.json_text))
            self.json_text, self.in_json = "", False


def main():
    pages = {p: Page(p) for p in ROOT.rglob("*.html")}
    assert len(pages) == 4, "Expected home, privacy, support, and 404 pages"
    assert (ROOT / "CNAME").read_text().strip() == "swaddle-ios.app"
    assert (ROOT / ".nojekyll").exists()
    for path, page in pages.items():
        source = path.read_text()
        assert page.h1 == 1 and page.language == "en", path
        assert page.meta.get("description") and page.meta.get("viewport"), path
        assert len(page.canonical) == 1, path
        expected = "/" + str(path.relative_to(ROOT)).replace("index.html", "")
        assert page.canonical[0] == ORIGIN + expected, path
        assert page.meta.get("og:url") == page.canonical[0], path
        if path.name != "404.html": assert "noindex" not in source, path
        assert not re.search(r"TODO|SUPPORT_EMAIL_PENDING|localhost|127\.0\.0\.1|/Users/", source), path
        for img in page.images:
            assert "alt" in img and img.get("width") and img.get("height"), (path, img)
        for link in page.links:
            u = urlsplit(link)
            if u.scheme in ("mailto", "tel"): continue
            if u.netloc and u.netloc != "swaddle-ios.app":
                assert u.scheme == "https", link
                continue
            p = ROOT / unquote(u.path.lstrip("/")) if u.path else path
            if p.is_dir(): p = p / "index.html"
            assert p.is_file() and not p.is_symlink(), (path, link)
            if u.fragment: assert u.fragment in pages[p].ids, (path, link)
        assert "fedor.korotkov@gmail.com" in source or path.name in ("index.html", "404.html")
    urls = ElementTree.parse(ROOT / "sitemap.xml").getroot()
    sitemap_urls = {el.text for el in urls.iter() if el.tag.endswith("}loc")}
    assert sitemap_urls == {ORIGIN + s for s in ("/", "/privacy/", "/support/")}
    assert ORIGIN + "/sitemap.xml" in (ROOT / "robots.txt").read_text()
    allowed = {".html", ".css", ".js", ".png", ".webp", ".jpg", ".xml", ".txt"}
    files = [p for p in ROOT.rglob("*") if p.is_file()]
    for p in files:
        assert not p.is_symlink(), p
        assert p.suffix in allowed or p.name in ("CNAME", ".nojekyll"), p
        assert p.stat().st_size < 250_000, f"Optimize the large asset: {p}"
    total = sum(p.stat().st_size for p in files)
    assert total < 1_000_000, f"Website payload exceeded 1 MB: {total}"
    assert "prefers-reduced-motion" in (ROOT / "assets/site.css").read_text()
    assert not re.search(r"fetch\(|XMLHttpRequest|localStorage|document\.cookie", (ROOT / "assets/site.js").read_text())
    print(f"PASS: {len(pages)} pages; links, anchors, images, metadata, JSON-LD, sitemap, and payload checked.")
    print(f"Public payload: {len(files)} files, {total:,} bytes. No journal data, build products, or QA files.")


if __name__ == "__main__":
    main()
