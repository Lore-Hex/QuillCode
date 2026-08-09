#!/usr/bin/env python3
"""Build a machine-readable manifest for Quill Cowork download releases."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote


SCHEMA_VERSION = 1
PRODUCT = "Quill Cowork"
MACOS_ARCHITECTURES = ("arm64", "x86_64")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write a channel download manifest for Quill Cowork release assets."
    )
    parser.add_argument("--assets-dir", required=True, help="Directory containing release assets.")
    parser.add_argument("--repo", required=True, help="GitHub repository, for example Lore-Hex/QuillCode.")
    parser.add_argument("--tag", required=True, help="Release tag used in download URLs.")
    parser.add_argument("--commit", required=True, help="Git commit SHA for this build.")
    parser.add_argument("--workflow-run-url", required=True, help="GitHub Actions run URL.")
    parser.add_argument(
        "--channel",
        choices=("stable", "tester"),
        default="tester",
        help="Release channel label.",
    )
    parser.add_argument("--generated-at", help="UTC ISO timestamp override for tests.")
    parser.add_argument("--output", required=True, help="Manifest JSON output path.")
    return parser.parse_args()


def sha256_hex(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_build_info_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if not separator or not key or key in values:
            raise SystemExit(f"{path.name} contains malformed or duplicate metadata")
        values[key] = value
    return values


def parse_macos_build_info(asset_directory: Path) -> dict[str, dict[str, str]]:
    values_by_arch: dict[str, dict[str, str]] = {}
    for architecture in MACOS_ARCHITECTURES:
        path = asset_directory / f"BUILD_INFO-macOS-{architecture}.txt"
        if not path.is_file():
            raise SystemExit(f"missing macOS build metadata: {path.name}")
        values = parse_build_info_file(path)
        if values.get("platform") != "macOS" or values.get("arch") != architecture:
            raise SystemExit(f"{path.name} has the wrong platform or architecture")
        if values.get("symbolsStripped") != "true":
            raise SystemExit(f"{path.name} must declare symbolsStripped=true")
        executable_size = values.get("executableSizeBytes", "")
        if not executable_size.isdecimal() or int(executable_size) <= 0:
            raise SystemExit(f"{path.name} executableSizeBytes must be a positive integer")
        values_by_arch[architecture] = values

    canonical_path = asset_directory / "BUILD_INFO.txt"
    arm_path = asset_directory / "BUILD_INFO-macOS-arm64.txt"
    if not canonical_path.is_file() or canonical_path.read_bytes() != arm_path.read_bytes():
        raise SystemExit("BUILD_INFO.txt must exactly mirror BUILD_INFO-macOS-arm64.txt")

    shared_keys = (
        "product",
        "platform",
        "version",
        "build",
        "commit",
        "configuration",
        "symbolsStripped",
        "bundleIdentifier",
        "minimumSystemVersion",
        "updateChannel",
        "updateManifestURL",
        "stableUpdateManifestURL",
        "testerUpdateManifestURL",
        "codesign",
        "signingTeamIdentifier",
        "notarized",
    )
    arm_values = values_by_arch["arm64"]
    for architecture, values in values_by_arch.items():
        for key in shared_keys:
            if values.get(key) != arm_values.get(key):
                raise SystemExit(
                    f"BUILD_INFO macOS {architecture} {key} disagrees with arm64"
                )
    return values_by_arch


def classify_asset(name: str) -> dict[str, str]:
    if name.startswith("Quill-Cowork-macOS-") and name.endswith(".dmg"):
        arch = name.removeprefix("Quill-Cowork-macOS-").removesuffix(".dmg")
        return {"kind": "installer", "platform": "macOS", "arch": arch, "install": "dmg-app"}
    if name.startswith("Quill-Cowork-macOS-") and name.endswith(".zip"):
        arch = name.removeprefix("Quill-Cowork-macOS-").removesuffix(".zip")
        return {"kind": "app", "platform": "macOS", "arch": arch, "install": "zip-app"}
    if name.startswith("quill-code-macOS-") and name.endswith(".tar.gz"):
        arch = name.removeprefix("quill-code-macOS-").removesuffix(".tar.gz")
        return {"kind": "cli", "platform": "macOS", "arch": arch, "install": "tarball"}
    if name.startswith("quill-code-linux-") and name.endswith(".tar.gz"):
        arch = name.removeprefix("quill-code-linux-").removesuffix(".tar.gz")
        return {"kind": "cli", "platform": "Linux", "arch": arch, "install": "tarball"}
    if name.startswith("Quill-Cowork-macOS-") and name.endswith("-PERFORMANCE.json"):
        arch = name.removeprefix("Quill-Cowork-macOS-").removesuffix("-PERFORMANCE.json")
        return {"kind": "performance", "platform": "macOS", "arch": arch, "install": "json"}
    if name == "BUILD_INFO.txt":
        return {"kind": "metadata", "platform": "macOS", "arch": "any", "install": "text"}
    if name.startswith("BUILD_INFO-macOS-") and name.endswith(".txt"):
        arch = name.removeprefix("BUILD_INFO-macOS-").removesuffix(".txt")
        return {"kind": "metadata", "platform": "macOS", "arch": arch, "install": "text"}
    if name.startswith("BUILD_INFO-linux-") and name.endswith(".txt"):
        arch = name.removeprefix("BUILD_INFO-linux-").removesuffix(".txt")
        return {"kind": "metadata", "platform": "Linux", "arch": arch, "install": "text"}
    if name.startswith("BUILD_INFO"):
        return {"kind": "metadata", "platform": "any", "arch": "any", "install": "text"}
    if name.endswith("SHASUMS256.txt") or name == "SHASUMS256.txt":
        return {"kind": "checksum", "platform": "any", "arch": "any", "install": "text"}
    return {"kind": "asset", "platform": "any", "arch": "any", "install": "download"}


def release_download_url(repo: str, tag: str, asset_name: str) -> str:
    encoded_name = quote(asset_name, safe="")
    encoded_tag = quote(tag, safe="")
    return f"https://github.com/{repo}/releases/download/{encoded_tag}/{encoded_name}"


def latest_release_download_url(repo: str, asset_name: str) -> str:
    encoded_name = quote(asset_name, safe="")
    return f"https://github.com/{repo}/releases/latest/download/{encoded_name}"


def exact_macos_assets(
    assets: list[dict[str, object]],
    *,
    kind: str,
    install: str,
) -> list[dict[str, object]]:
    assets_by_arch: dict[str, dict[str, object]] = {}
    for asset in assets:
        if (
            asset.get("kind") != kind
            or asset.get("platform") != "macOS"
        ):
            continue
        if asset.get("install") != install:
            raise SystemExit(
                f"release macOS {kind} assets must use {install} installation"
            )
        architecture = str(asset.get("arch"))
        if architecture not in MACOS_ARCHITECTURES or architecture in assets_by_arch:
            raise SystemExit(
                f"release must contain exactly one macOS {kind} for each architecture"
            )
        assets_by_arch[architecture] = asset
    if set(assets_by_arch) != set(MACOS_ARCHITECTURES):
        raise SystemExit(
            f"release must contain exactly one macOS {kind} for each architecture"
        )
    return [assets_by_arch[architecture] for architecture in MACOS_ARCHITECTURES]


def build_updater_metadata(
    *,
    repo: str,
    channel: str,
    build_infos: dict[str, dict[str, str]],
    assets: list[dict[str, object]],
) -> dict[str, object]:
    app_assets = exact_macos_assets(assets, kind="app", install="zip-app")
    for kind, install in (
        ("installer", "dmg-app"),
        ("performance", "json"),
        ("cli", "tarball"),
    ):
        exact_macos_assets(assets, kind=kind, install=install)

    build_info = build_infos["arm64"]
    signing_team = build_info.get("signingTeamIdentifier")
    if not signing_team or signing_team == "none":
        signing_team = None
    stable_manifest_url = latest_release_download_url(repo, "latest-stable-build.json")
    tester_manifest_url = release_download_url(
        repo,
        "tester-latest",
        "latest-tester-build.json",
    )
    manifest_url = stable_manifest_url if channel == "stable" else tester_manifest_url
    expected_build_info = {
        "updateChannel": channel,
        "updateManifestURL": manifest_url,
        "stableUpdateManifestURL": stable_manifest_url,
        "testerUpdateManifestURL": tester_manifest_url,
    }
    for key, expected in expected_build_info.items():
        actual = build_info.get(key)
        if actual != expected:
            raise SystemExit(
                f"BUILD_INFO {key} must be {expected!r}, found {actual!r}"
            )
    return {
        "schemaVersion": 1,
        "format": "github-release-manifest",
        "channel": channel,
        "manifestURL": manifest_url,
        "stableManifestURL": stable_manifest_url,
        "testerManifestURL": tester_manifest_url,
        "bundleIdentifier": build_info.get("bundleIdentifier", "co.lorehex.QuillCowork"),
        "minimumSystemVersion": build_info.get("minimumSystemVersion", "14.0"),
        "codesign": build_info.get("codesign", "unknown"),
        "signingTeamIdentifier": signing_team,
        "notarized": build_info.get("notarized", "false").lower() == "true",
        "macOSAppAsset": app_assets[0],
        "macOSAppAssets": app_assets,
    }


def build_manifest(arguments: argparse.Namespace) -> dict[str, object]:
    asset_directory = Path(arguments.assets_dir)
    output_path = Path(arguments.output)
    if not asset_directory.is_dir():
        raise SystemExit(f"assets directory does not exist: {asset_directory}")

    build_infos = parse_macos_build_info(asset_directory)
    build_info = build_infos["arm64"]
    if build_info.get("commit") != arguments.commit:
        raise SystemExit("BUILD_INFO commit must match --commit")
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

    updater = build_updater_metadata(
        repo=arguments.repo,
        channel=arguments.channel,
        build_infos=build_infos,
        assets=assets,
    )

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
        "updater": updater,
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
