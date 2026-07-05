#!/usr/bin/env python3
"""Build a machine-readable manifest for QuillCode download releases."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote


SCHEMA_VERSION = 1
PRODUCT = "QuillCode"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write latest-tester-build.json for QuillCode release assets."
    )
    parser.add_argument("--assets-dir", required=True, help="Directory containing release assets.")
    parser.add_argument("--repo", required=True, help="GitHub repository, for example Lore-Hex/QuillCode.")
    parser.add_argument("--tag", required=True, help="Release tag used in download URLs.")
    parser.add_argument("--commit", required=True, help="Git commit SHA for this build.")
    parser.add_argument("--workflow-run-url", required=True, help="GitHub Actions run URL.")
    parser.add_argument("--channel", default="tester", help="Release channel label.")
    parser.add_argument("--generated-at", help="UTC ISO timestamp override for tests.")
    parser.add_argument("--output", required=True, help="Manifest JSON output path.")
    return parser.parse_args()


def sha256_hex(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_build_info(asset_directory: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for path in sorted(asset_directory.glob("BUILD_INFO*.txt")):
        for line in path.read_text(encoding="utf-8").splitlines():
            key, separator, value = line.partition("=")
            if separator and key and key not in values:
                values[key] = value
    return values


def classify_asset(name: str) -> dict[str, str]:
    if name.startswith("QuillCode-macOS-") and name.endswith(".zip"):
        arch = name.removeprefix("QuillCode-macOS-").removesuffix(".zip")
        return {"kind": "app", "platform": "macOS", "arch": arch, "install": "zip-app"}
    if name.startswith("quill-code-macOS-") and name.endswith(".tar.gz"):
        arch = name.removeprefix("quill-code-macOS-").removesuffix(".tar.gz")
        return {"kind": "cli", "platform": "macOS", "arch": arch, "install": "tarball"}
    if name.startswith("quill-code-linux-") and name.endswith(".tar.gz"):
        arch = name.removeprefix("quill-code-linux-").removesuffix(".tar.gz")
        return {"kind": "cli", "platform": "Linux", "arch": arch, "install": "tarball"}
    if name.startswith("BUILD_INFO"):
        return {"kind": "metadata", "platform": "any", "arch": "any", "install": "text"}
    if name.endswith("SHASUMS256.txt") or name == "SHASUMS256.txt":
        return {"kind": "checksum", "platform": "any", "arch": "any", "install": "text"}
    return {"kind": "asset", "platform": "any", "arch": "any", "install": "download"}


def release_download_url(repo: str, tag: str, asset_name: str) -> str:
    encoded_name = quote(asset_name, safe="")
    encoded_tag = quote(tag, safe="")
    return f"https://github.com/{repo}/releases/download/{encoded_tag}/{encoded_name}"


def build_manifest(arguments: argparse.Namespace) -> dict[str, object]:
    asset_directory = Path(arguments.assets_dir)
    output_path = Path(arguments.output)
    if not asset_directory.is_dir():
        raise SystemExit(f"assets directory does not exist: {asset_directory}")

    build_info = parse_build_info(asset_directory)
    generated_at = arguments.generated_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    assets: list[dict[str, object]] = []
    for path in sorted(asset_directory.iterdir(), key=lambda item: item.name):
        if not path.is_file():
            continue
        if path.resolve() == output_path.resolve():
            continue
        classification = classify_asset(path.name)
        assets.append(
            {
                "name": path.name,
                "kind": classification["kind"],
                "platform": classification["platform"],
                "arch": classification["arch"],
                "install": classification["install"],
                "sizeBytes": path.stat().st_size,
                "sha256": sha256_hex(path),
                "url": release_download_url(arguments.repo, arguments.tag, path.name),
            }
        )

    if not assets:
        raise SystemExit(f"no release assets found in {asset_directory}")

    return {
        "schemaVersion": SCHEMA_VERSION,
        "product": PRODUCT,
        "channel": arguments.channel,
        "tag": arguments.tag,
        "releaseURL": f"https://github.com/{arguments.repo}/releases/tag/{quote(arguments.tag, safe='')}",
        "commit": arguments.commit,
        "version": build_info.get("version", "unknown"),
        "build": build_info.get("build", "unknown"),
        "generatedAt": generated_at,
        "workflowRunURL": arguments.workflow_run_url,
        "assets": assets,
    }


def main() -> int:
    arguments = parse_arguments()
    manifest = build_manifest(arguments)
    output_path = Path(arguments.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
