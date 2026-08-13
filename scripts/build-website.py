#!/usr/bin/env python3
"""Stage the Quill Cowork website from reviewed main-branch sources."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import tempfile


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = REPOSITORY_ROOT / "website"
SCREENSHOT_SOURCE = REPOSITORY_ROOT / "docs/images/quill-cowork-desktop.png"
SOURCE_FILES = (
    Path("404.html"),
    Path("CNAME"),
    Path("index.html"),
    Path("static/cowork.css"),
    Path("static/site.js"),
    Path("static/fonts/archivo-latin.woff2"),
    Path("static/fonts/ibm-plex-mono-400-latin.woff2"),
    Path("static/fonts/spectral-300-latin.woff2"),
    Path("static/fonts/spectral-400-latin.woff2"),
    Path("static/fonts/spectral-500-latin.woff2"),
)
SCREENSHOT_DESTINATION = Path("static/media/quill-cowork-desktop.png")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=REPOSITORY_ROOT / "_site",
        help="Directory to replace with the staged static site.",
    )
    return parser.parse_args()


def validate_output_path(output: Path) -> Path:
    resolved = output.expanduser().resolve()
    protected = {Path("/").resolve(), Path.home().resolve(), REPOSITORY_ROOT, SOURCE_ROOT}
    if resolved in protected or SOURCE_ROOT.is_relative_to(resolved):
        raise SystemExit(f"refusing unsafe website output path: {resolved}")
    if resolved.exists() and resolved.is_symlink():
        raise SystemExit(f"refusing symlink website output path: {resolved}")
    return resolved


def require_regular_file(path: Path) -> None:
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"required website source is missing or unsafe: {path}")


def build(output: Path) -> None:
    output = validate_output_path(output)
    for relative_path in SOURCE_FILES:
        require_regular_file(SOURCE_ROOT / relative_path)
    require_regular_file(SCREENSHOT_SOURCE)

    output.parent.mkdir(parents=True, exist_ok=True)
    staging_parent = Path(
        tempfile.mkdtemp(prefix=".quill-cowork-site-", dir=output.parent)
    )
    staged_site = staging_parent / "site"
    try:
        for relative_path in SOURCE_FILES:
            destination = staged_site / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE_ROOT / relative_path, destination)

        screenshot_destination = staged_site / SCREENSHOT_DESTINATION
        screenshot_destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SCREENSHOT_SOURCE, screenshot_destination)

        if output.exists():
            if output.is_dir():
                shutil.rmtree(output)
            else:
                output.unlink()
        os.replace(staged_site, output)
    finally:
        shutil.rmtree(staging_parent, ignore_errors=True)

    print(f"Staged Quill Cowork website at {output}")


if __name__ == "__main__":
    build(parse_arguments().output)
