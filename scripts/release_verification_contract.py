"""Structural contract validation for published Quill Cowork releases."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any
from urllib.parse import quote


PRODUCT = "Quill Cowork"
BUNDLE_IDENTIFIER = "co.lorehex.QuillCowork"
MACOS_ARCHITECTURES = ("arm64", "x86_64")
MACOS_INSTALLER_ARCHITECTURES = ("universal", *MACOS_ARCHITECTURES)
MANIFEST_BYTE_LIMIT = 256 * 1024
API_BYTE_LIMIT = 4 * 1024 * 1024
MAXIMUM_ASSET_BYTES = 2 * 1024 * 1024 * 1024
MAXIMUM_RELEASE_BYTES = 4 * 1024 * 1024 * 1024
SHA_PATTERN = re.compile(r"[0-9a-f]{40}")
DIGEST_PATTERN = re.compile(r"[0-9a-f]{64}")
VERSION_PATTERN = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
)
BUILD_PATTERN = re.compile(r"0|[1-9][0-9]*")
REPOSITORY_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")


class VerificationError(RuntimeError):
    """A public release violated the distribution contract."""


def expected_urls(repo: str, tag: str, channel: str) -> dict[str, str]:
    encoded_tag = quote(tag, safe="")
    manifest_name = f"latest-{channel}-build.json"
    return {
        "manifest_name": manifest_name,
        "manifest": (
            f"https://github.com/{repo}/releases/download/{encoded_tag}/"
            f"{quote(manifest_name, safe='')}"
        ),
        "release": f"https://github.com/{repo}/releases/tag/{encoded_tag}",
        "stable": (
            f"https://github.com/{repo}/releases/latest/download/"
            "latest-stable-build.json"
        ),
        "tester": (
            f"https://github.com/{repo}/releases/download/tester-latest/"
            "latest-tester-build.json"
        ),
    }


def load_json_bytes(data: bytes, label: str) -> dict[str, Any]:
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise VerificationError(f"{label} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise VerificationError(f"{label} must be a JSON object")
    return value


def discover_workflow_run_url(manifest_bytes: bytes, repo: str) -> str:
    manifest = load_json_bytes(manifest_bytes, "provenance manifest")
    value = manifest.get("workflowRunURL")
    pattern = rf"https://github\.com/{re.escape(repo)}/actions/runs/[1-9][0-9]*"
    if not isinstance(value, str) or re.fullmatch(pattern, value) is None:
        raise VerificationError("manifest publishing run URL is invalid")
    return value


def required_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise VerificationError(f"{label} must be a nonempty string")
    return value


def required_integer(value: Any, label: str) -> int:
    if type(value) is not int:
        raise VerificationError(f"{label} must be an integer")
    return value


def api_asset_map(release: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw_assets = release.get("assets")
    if not isinstance(raw_assets, list):
        raise VerificationError("release assets must be an array")
    assets: dict[str, dict[str, Any]] = {}
    for index, raw_asset in enumerate(raw_assets):
        if not isinstance(raw_asset, dict):
            raise VerificationError(f"release asset {index} must be an object")
        name = required_string(raw_asset.get("name"), f"release asset {index} name")
        if name in assets:
            raise VerificationError(f"release contains duplicate asset {name!r}")
        assets[name] = raw_asset
    return assets


def validate_api_asset(
    api_asset: dict[str, Any],
    *,
    name: str,
    size: int,
    digest: str,
    url: str,
) -> None:
    if api_asset.get("state") != "uploaded":
        raise VerificationError(f"release asset {name!r} is not uploaded")
    if required_integer(api_asset.get("size"), f"release asset {name} size") != size:
        raise VerificationError(
            f"release asset {name!r} size disagrees with the manifest"
        )
    if api_asset.get("digest") != f"sha256:{digest}":
        raise VerificationError(
            f"release asset {name!r} digest disagrees with the manifest"
        )
    if api_asset.get("browser_download_url") != url:
        raise VerificationError(
            f"release asset {name!r} URL disagrees with the manifest"
        )


def exact_macos_assets(
    assets: list[dict[str, Any]],
    *,
    kind: str,
    install: str,
    architectures: tuple[str, ...] = MACOS_ARCHITECTURES,
) -> list[dict[str, Any]]:
    matching = [
        asset
        for asset in assets
        if asset["kind"] == kind
        and asset["platform"] == "macOS"
    ]
    assets_by_arch: dict[str, dict[str, Any]] = {}
    for asset in matching:
        if asset["install"] != install:
            raise VerificationError(
                f"release macOS {kind} assets must use {install} installation"
            )
        architecture = asset["arch"]
        if architecture not in architectures or architecture in assets_by_arch:
            raise VerificationError(
                f"release must contain exactly one macOS {kind} for each architecture"
            )
        assets_by_arch[architecture] = asset
    if set(assets_by_arch) != set(architectures):
        raise VerificationError(
            f"release must contain exactly one macOS {kind} for each architecture"
        )
    return [assets_by_arch[architecture] for architecture in architectures]


def validate_manifest(
    manifest: dict[str, Any],
    manifest_bytes: bytes,
    release: dict[str, Any],
    tag_commit: str,
    *,
    repo: str,
    tag: str,
    channel: str,
    commit: str,
    workflow_run_url: str,
    stable_candidate: bool = False,
) -> list[dict[str, Any]]:
    urls = expected_urls(repo, tag, channel)
    if stable_candidate and channel != "stable":
        raise VerificationError(
            "stable-candidate verification is only valid for the stable channel"
        )
    expected_prerelease = channel == "tester" or stable_candidate
    if release.get("tag_name") != tag:
        raise VerificationError("GitHub release tag does not match the requested tag")
    if release.get("draft") is not False:
        raise VerificationError("GitHub release is still a draft")
    if release.get("prerelease") is not expected_prerelease:
        raise VerificationError(
            "GitHub release prerelease state does not match its channel"
        )
    if tag_commit != commit:
        raise VerificationError(f"release tag resolves to {tag_commit}, expected {commit}")

    expected_top_level = {
        "schemaVersion": 1,
        "product": PRODUCT,
        "channel": channel,
        "tag": tag,
        "releaseURL": urls["release"],
        "commit": commit,
        "workflowRunURL": workflow_run_url,
    }
    for key, expected in expected_top_level.items():
        if manifest.get(key) != expected:
            raise VerificationError(
                f"manifest {key} does not match the published release"
            )
    version = required_string(manifest.get("version"), "manifest version")
    build = required_string(manifest.get("build"), "manifest build")
    if not VERSION_PATTERN.fullmatch(version) or not BUILD_PATTERN.fullmatch(build):
        raise VerificationError("manifest version/build metadata is not canonical")
    if channel == "stable" and tag != f"v{version}":
        raise VerificationError("stable release tag does not match the manifest version")
    expected_release_name = (
        f"Quill Cowork {tag}"
        if channel == "stable"
        else f"Quill Cowork Tester {version} ({build})"
    )
    if release.get("name") != expected_release_name:
        raise VerificationError("GitHub release name does not match the manifest identity")
    generated_at = required_string(manifest.get("generatedAt"), "manifest generatedAt")
    timestamp_pattern = r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"
    if not re.fullmatch(timestamp_pattern, generated_at):
        raise VerificationError("manifest generatedAt is not a UTC timestamp")

    updater = manifest.get("updater")
    if not isinstance(updater, dict):
        raise VerificationError("manifest updater must be an object")
    expected_feed = urls["stable"] if channel == "stable" else urls["tester"]
    expected_updater = {
        "schemaVersion": 1,
        "format": "github-release-manifest",
        "channel": channel,
        "manifestURL": expected_feed,
        "stableManifestURL": urls["stable"],
        "testerManifestURL": urls["tester"],
        "bundleIdentifier": BUNDLE_IDENTIFIER,
    }
    for key, expected in expected_updater.items():
        if updater.get(key) != expected:
            raise VerificationError(
                f"manifest updater {key} does not match the app feed contract"
            )
    required_string(updater.get("minimumSystemVersion"), "updater minimumSystemVersion")
    if channel == "stable":
        if updater.get("codesign") != "developer-id":
            raise VerificationError("stable updater metadata is not Developer ID signed")
        required_string(
            updater.get("signingTeamIdentifier"),
            "updater signingTeamIdentifier",
        )
        if updater.get("notarized") is not True:
            raise VerificationError("stable updater metadata is not notarized")

    raw_assets = manifest.get("assets")
    if not isinstance(raw_assets, list) or not raw_assets:
        raise VerificationError("manifest assets must be a nonempty array")
    api_assets = api_asset_map(release)
    assets: list[dict[str, Any]] = []
    names: set[str] = set()
    total_size = 0
    for index, raw_asset in enumerate(raw_assets):
        if not isinstance(raw_asset, dict):
            raise VerificationError(f"manifest asset {index} must be an object")
        name = required_string(raw_asset.get("name"), f"manifest asset {index} name")
        if (
            name in names
            or name != Path(name).name
            or name in (".", "..")
            or ".." in name
            or "/" in name
            or "\\" in name
            or len(name) > 180
        ):
            raise VerificationError(
                f"manifest asset name {name!r} is unsafe or duplicated"
            )
        names.add(name)
        for field in ("kind", "platform", "arch", "install"):
            required_string(raw_asset.get(field), f"manifest asset {name} {field}")
        size = required_integer(
            raw_asset.get("sizeBytes"),
            f"manifest asset {name} sizeBytes",
        )
        digest = required_string(
            raw_asset.get("sha256"),
            f"manifest asset {name} sha256",
        )
        if size <= 0 or size > MAXIMUM_ASSET_BYTES:
            raise VerificationError(f"manifest asset {name!r} has an invalid size")
        if not DIGEST_PATTERN.fullmatch(digest):
            raise VerificationError(f"manifest asset {name!r} has an invalid SHA-256")
        expected_url = (
            f"https://github.com/{repo}/releases/download/"
            f"{quote(tag, safe='')}/{quote(name, safe='')}"
        )
        if raw_asset.get("url") != expected_url:
            raise VerificationError(f"manifest asset {name!r} has an unexpected URL")
        api_asset = api_assets.get(name)
        if api_asset is None:
            raise VerificationError(f"GitHub release is missing manifest asset {name!r}")
        validate_api_asset(
            api_asset,
            name=name,
            size=size,
            digest=digest,
            url=expected_url,
        )
        total_size += size
        if total_size > MAXIMUM_RELEASE_BYTES:
            raise VerificationError("manifest release size exceeds its aggregate limit")
        assets.append(raw_asset)

    manifest_name = urls["manifest_name"]
    expected_names = names | {manifest_name}
    if set(api_assets) != expected_names:
        raise VerificationError(
            "GitHub release asset inventory does not exactly match the manifest"
        )
    manifest_digest = hashlib.sha256(manifest_bytes).hexdigest()
    validate_api_asset(
        api_assets[manifest_name],
        name=manifest_name,
        size=len(manifest_bytes),
        digest=manifest_digest,
        url=urls["manifest"],
    )

    app_assets = exact_macos_assets(assets, kind="app", install="zip-app")
    installer_assets = exact_macos_assets(
        assets,
        kind="installer",
        install="dmg-app",
        architectures=MACOS_INSTALLER_ARCHITECTURES,
    )
    for kind, install in (("performance", "json"), ("cli", "tarball")):
        exact_macos_assets(assets, kind=kind, install=install)
    if updater.get("macOSUniversalInstaller") != installer_assets[0]:
        raise VerificationError(
            "updater universal installer must match the published universal DMG"
        )
    if updater.get("macOSAppAsset") != app_assets[0]:
        raise VerificationError("legacy updater asset must be the arm64 app archive")
    if updater.get("macOSAppAssets") != app_assets:
        raise VerificationError(
            "updater macOS app assets must exactly cover arm64 and x86_64"
        )
    return assets
