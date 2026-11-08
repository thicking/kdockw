#!/usr/bin/env python3
"""Validate the assembled static website and its published media assets."""

from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

SITE_HOST = "thicking.github.io"
SITE_PREFIX = "/kdockw/"


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.refs: list[tuple[str, str]] = []
        self.images_without_alt: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "img":
            if values.get("alt") is None:
                self.images_without_alt.append(values.get("src", "<missing src>") or "<missing src>")
            src = values.get("src")
            if src:
                self.refs.append(("image", src))
        elif tag == "video":
            for attr in ("src", "poster"):
                if values.get(attr):
                    self.refs.append(("video", values[attr] or ""))
        elif tag == "source" and values.get("src"):
            self.refs.append(("video", values["src"] or ""))
        elif tag in {"link", "script"}:
            key = "href" if tag == "link" else "src"
            if values.get(key):
                self.refs.append(("resource", values[key] or ""))
        elif tag == "a" and values.get("href"):
            self.refs.append(("link", values["href"] or ""))
        elif tag == "meta" and values.get("property") == "og:image":
            if values.get("content"):
                self.refs.append(("image", values["content"] or ""))


def local_target(site: Path, raw: str) -> Path | None:
    parsed = urlsplit(raw)
    if parsed.scheme in {"mailto", "tel", "data", "javascript"}:
        return None
    if parsed.scheme and parsed.netloc:
        if parsed.hostname != SITE_HOST:
            return None
        path = unquote(parsed.path)
        if path.startswith(SITE_PREFIX):
            path = path[len(SITE_PREFIX) :]
        relative = path.lstrip("/")
        return site / (relative + "index.html" if path.endswith("/") or not relative else relative)
    if parsed.path.startswith("/"):
        path = unquote(parsed.path)
        if path.startswith(SITE_PREFIX):
            path = path[len(SITE_PREFIX) :]
        relative = path.lstrip("/")
        return site / (relative + "index.html" if path.endswith("/") or not relative else relative)
    if not parsed.path or parsed.path.startswith("#"):
        return None
    path = unquote(parsed.path)
    if path in {".", "./"} or path.endswith("/"):
        return site / (path.rstrip("/") + "/index.html" if path not in {".", "./"} else "index.html")
    return site / path


def main() -> int:
    site = Path(sys.argv[1] if len(sys.argv) > 1 else "_site").resolve()
    page = site / "index.html"
    pages = sorted(site.rglob("*.html"))
    if not page.is_file() or not pages:
        print(f"FAIL: {page} is missing")
        return 1

    failures: list[str] = []
    total_refs = 0
    for html_page in pages:
        parser = PageParser()
        page_text = html_page.read_text(encoding="utf-8")
        parser.feed(page_text)
        total_refs += len(parser.refs)
        for label, raw in parser.refs:
            target = local_target(site, raw)
            if target is not None and not target.is_file():
                failures.append(f"broken {label} reference in {html_page.relative_to(site)}: {raw} -> {target}")
        for image in parser.images_without_alt:
            failures.append(f"image has no alt attribute in {html_page.relative_to(site)}: {image}")

    index_text = page.read_text(encoding="utf-8").lower()
    if 'rel="canonical" href="https://thicking.github.io/kdockw/"' not in index_text:
        failures.append("index.html canonical URL is missing or incorrect")
    if "noindex" in index_text:
        failures.append("index.html contains a noindex directive")
    robots = site / "robots.txt"
    sitemap = site / "sitemap.xml"
    if not robots.is_file() or "sitemap: https://thicking.github.io/kdockw/sitemap.xml" not in robots.read_text(encoding="utf-8").lower():
        failures.append("robots.txt does not point to the public sitemap")
    if not sitemap.is_file() or "https://thicking.github.io/kdockw/" not in sitemap.read_text(encoding="utf-8"):
        failures.append("sitemap.xml does not list the canonical homepage")

    for asset in site.rglob("*.png"):
        with asset.open("rb") as stream:
            signature = stream.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            failures.append(f"{asset.relative_to(site)} is not a real PNG (possible Git LFS pointer)")

    for asset in site.rglob("*.ico"):
        with asset.open("rb") as stream:
            signature = stream.read(4)
        if signature != b"\x00\x00\x01\x00":
            failures.append(f"{asset.relative_to(site)} is not a valid ICO file")

    for asset in site.rglob("*.svg"):
        try:
            ET.parse(asset)
        except ET.ParseError as error:
            failures.append(f"{asset.relative_to(site)} is not valid SVG/XML: {error}")

    manifest = site / "site.webmanifest"
    if manifest.is_file():
        try:
            manifest_data = json.loads(manifest.read_text(encoding="utf-8"))
            for icon in manifest_data.get("icons", []):
                icon_path = site / icon.get("src", "")
                if not icon_path.is_file():
                    failures.append(f"site.webmanifest references missing icon: {icon.get('src')}")
        except json.JSONDecodeError as error:
            failures.append(f"site.webmanifest is not valid JSON: {error}")

    video = site / "screenshots/kdockw-demo.mp4"
    if video.is_file():
        head = video.read_bytes()[:64]
        if len(head) < 12 or head[4:8] != b"ftyp" or head.startswith(b"version https://git-lfs.github.com/spec/v1"):
            failures.append("screenshots/kdockw-demo.mp4 is not a real MP4 file (possible Git LFS pointer)")

    if failures:
        print("Website checks failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print(f"Website checks passed: {len(pages)} pages, {total_refs} references, canonical/indexing metadata, accessible image alt attributes, and valid PNG/ICO/SVG/MP4 assets in {site}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
