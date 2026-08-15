#!/usr/bin/env python3
"""Fail closed when the staged public website drifts from its release contract."""

from __future__ import annotations

import argparse
from html.parser import HTMLParser
from pathlib import Path
import re
from urllib.parse import urlsplit


UNIVERSAL_INSTALLER_URL = (
    "https://github.com/Lore-Hex/QuillCode/releases/download/"
    "tester-latest/Quill-Cowork-macOS-universal.dmg"
)
RELEASE_URL = "https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest"
STABLE_RELEASE_API_URL = "https://api.github.com/repos/Lore-Hex/QuillCode/releases/latest"
TESTER_RELEASE_API_URL = (
    "https://api.github.com/repos/Lore-Hex/QuillCode/releases/tags/tester-latest"
)
THIN_INSTALLER_PATTERN = re.compile(r"Quill-Cowork-macOS-(?:arm64|x86_64)\.dmg")
CSS_URL_PATTERN = re.compile(r"url\(\s*(['\"]?)([^)'\"]+)\1\s*\)")
EXPECTED_FILES = {
    "404.html",
    "CNAME",
    "index.html",
    "static/cowork.css",
    "static/site.js",
    "static/fonts/archivo-latin.woff2",
    "static/fonts/ibm-plex-mono-400-latin.woff2",
    "static/fonts/spectral-300-latin.woff2",
    "static/fonts/spectral-400-latin.woff2",
    "static/fonts/spectral-500-latin.woff2",
    "static/media/quill-cowork-desktop.png",
}
MAXIMUM_TOTAL_BYTES = 2 * 1024 * 1024


class DocumentParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.references: list[tuple[str, str, str]] = []
        self.anchors: list[str] = []
        self.ids: list[str] = []
        self.images: list[dict[str, str]] = []
        self.title_parts: list[str] = []
        self._inside_title = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {name: value or "" for name, value in attrs}
        if identifier := values.get("id"):
            self.ids.append(identifier)
        if tag == "a":
            self.anchors.append(values.get("href", ""))
        if tag == "img":
            self.images.append(values)
        for attribute in ("href", "src"):
            if value := values.get(attribute):
                self.references.append((tag, attribute, value))
        if tag == "title":
            self._inside_title = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._inside_title = False

    def handle_data(self, data: str) -> None:
        if self._inside_title:
            self.title_parts.append(data)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, required=True)
    return parser.parse_args()


def fail(message: str) -> None:
    raise SystemExit(f"website verification failed: {message}")


def local_asset_path(site: Path, document: Path, reference: str) -> Path | None:
    parsed = urlsplit(reference)
    if parsed.scheme or parsed.netloc or reference.startswith(("mailto:", "#")):
        return None
    if parsed.path in {"", "/"}:
        return site / "index.html"
    if parsed.path.startswith("/"):
        return site / parsed.path.removeprefix("/")
    return document.parent / parsed.path


def verify_document(site: Path, relative_path: str) -> DocumentParser:
    document = site / relative_path
    contents = document.read_text(encoding="utf-8")
    if not contents.lstrip().lower().startswith("<!doctype html>"):
        fail(f"{relative_path} must declare the HTML doctype")

    parser = DocumentParser()
    parser.feed(contents)
    if not "".join(parser.title_parts).strip():
        fail(f"{relative_path} has no title")
    if len(parser.ids) != len(set(parser.ids)):
        fail(f"{relative_path} contains duplicate element IDs")
    for href in parser.anchors:
        if not href:
            fail(f"{relative_path} contains a link without a destination")
        if href.startswith("javascript:"):
            fail(f"{relative_path} contains a javascript URL")
        if href.startswith("#") and href.removeprefix("#") not in parser.ids:
            fail(f"{relative_path} links to missing fragment {href}")
    for image in parser.images:
        if not image.get("alt") or not image.get("width") or not image.get("height"):
            fail(f"{relative_path} images require alt text and stable dimensions")
    for _, _, reference in parser.references:
        local_path = local_asset_path(site, document, reference)
        if local_path is not None and not local_path.is_file():
            fail(f"{relative_path} references missing local asset {reference}")
    return parser


def verify_site(site: Path) -> None:
    site = site.expanduser().resolve()
    if not site.is_dir() or site.is_symlink():
        fail(f"site root is missing or unsafe: {site}")

    actual_files: set[str] = set()
    total_bytes = 0
    for path in site.rglob("*"):
        if path.is_symlink():
            fail(f"site contains symlink {path.relative_to(site)}")
        if path.is_file():
            relative = path.relative_to(site).as_posix()
            actual_files.add(relative)
            total_bytes += path.stat().st_size
    if actual_files != EXPECTED_FILES:
        missing = sorted(EXPECTED_FILES - actual_files)
        unexpected = sorted(actual_files - EXPECTED_FILES)
        fail(f"asset inventory drifted; missing={missing}, unexpected={unexpected}")
    if total_bytes > MAXIMUM_TOTAL_BYTES:
        fail(f"site payload is too large: {total_bytes} bytes")

    if (site / "CNAME").read_text(encoding="utf-8").strip() != "cowork.quillos.cloud":
        fail("CNAME must preserve cowork.quillos.cloud")

    verify_document(site, "index.html")
    verify_document(site, "404.html")
    index = (site / "index.html").read_text(encoding="utf-8")
    script = (site / "static/site.js").read_text(encoding="utf-8")
    css = (site / "static/cowork.css").read_text(encoding="utf-8")

    if index.count(UNIVERSAL_INSTALLER_URL) != 3:
        fail("index must expose exactly three universal installer links")
    if index.count('data-download-link') != 3:
        fail("every primary installer link must be live-manifest addressable")
    if index.count('data-build-label') != 2:
        fail("current build provenance must appear at both download decisions")
    if index.count('data-release-link') != 3:
        fail("release details must switch channels with every download decision")
    for attribute in (
        'data-release-kind',
        'data-release-section',
        'data-install-guidance',
        'data-release-caption',
    ):
        if index.count(attribute) != 1:
            fail(f"index must expose exactly one {attribute} target")
    if index.count(RELEASE_URL) < 3:
        fail("release notes must be available near downloads and in the footer")
    if THIN_INSTALLER_PATTERN.search(index):
        fail("human-facing pages must not require architecture selection")
    if STABLE_RELEASE_API_URL not in script or TESTER_RELEASE_API_URL not in script:
        fail("live release metadata must prefer stable and retain tester fallback releases")
    if UNIVERSAL_INSTALLER_URL.rsplit("/", 1)[-1] not in script:
        fail("live release metadata must require the universal installer")
    required_script_contracts = (
        'cache: "no-store"',
        'credentials: "omit"',
        "readCurrentRelease",
        'manifestName: "latest-stable-build.json"',
        'manifestName: "latest-tester-build.json"',
        "Developer ID signed, notarized by Apple, and stapled",
        "ad-hoc signed and not Apple-notarized.",
        "uploadedAsset(",
        "testerTitleMatch",
        "document.documentElement.dataset.version",
        "document.documentElement.dataset.build",
    )
    if any(contract not in script for contract in required_script_contracts):
        fail("live release metadata must be freshly fetched and fail-closed validated")
    if index.count('/static/site.js?v=3') != 1:
        fail("index must load the current release-identity script revision")

    for _, reference in CSS_URL_PATTERN.findall(css):
        local_path = local_asset_path(site, site / "static/cowork.css", reference)
        if local_path is not None and not local_path.is_file():
            fail(f"stylesheet references missing local asset {reference}")

    print(f"Verified Quill Cowork website ({len(actual_files)} files, {total_bytes} bytes)")


if __name__ == "__main__":
    verify_site(parse_arguments().site)
