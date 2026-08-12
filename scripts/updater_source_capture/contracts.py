from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
from typing import Any


PRODUCT = "Quill Cowork"
BUNDLE_IDENTIFIER = "co.lorehex.QuillCowork"
MANIFEST_MAX_BYTES = 1_048_576
APP_MAX_BYTES = 536_870_912
COMMIT_PATTERN = re.compile(r"[0-9a-f]{40}")
REPOSITORY_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
STABLE_TAG_PATTERN = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+")
VERSION_PATTERN = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")


class CaptureError(RuntimeError):
    pass


@dataclass(frozen=True)
class ReleaseAsset:
    name: str
    size: int
    digest: str
    state: str


@dataclass(frozen=True)
class Release:
    tag: str
    target_commit: str
    draft: bool
    prerelease: bool
    assets: dict[str, ReleaseAsset]


@dataclass(frozen=True)
class SourceMetadata:
    channel: str
    tag: str
    architecture: str
    version: str
    build: str
    commit: str
    app_name: str
    app_size: int
    app_digest: str


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise CaptureError(f"{label} must be a non-empty string.")
    return value


def require_boolean(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise CaptureError(f"{label} must be a boolean.")
    return value


def require_integer(
    value: Any,
    label: str,
    *,
    minimum: int = 0,
    maximum: int | None = None,
) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise CaptureError(f"{label} must be an integer of at least {minimum}.")
    if maximum is not None and value > maximum:
        raise CaptureError(f"{label} exceeds its supported size limit.")
    return value


def decode_release(payload: str, channel: str) -> Release:
    try:
        value = json.loads(payload)
    except json.JSONDecodeError as error:
        raise CaptureError(f"GitHub returned malformed release JSON: {error}") from error
    if not isinstance(value, dict):
        raise CaptureError("GitHub release response must be an object.")

    tag = require_string(value.get("tag_name"), "Release tag")
    target = require_string(value.get("target_commitish"), "Release target")
    if not COMMIT_PATTERN.fullmatch(target):
        raise CaptureError("Published source release must target an exact commit.")
    if channel == "tester" and tag != "tester-latest":
        raise CaptureError("Tester source release must use tester-latest.")
    if channel == "stable" and not STABLE_TAG_PATTERN.fullmatch(tag):
        raise CaptureError("Stable source release must use a canonical version tag.")

    values = value.get("assets")
    if not isinstance(values, list) or not values or len(values) > 64:
        raise CaptureError("Published source release must contain between 1 and 64 assets.")
    assets: dict[str, ReleaseAsset] = {}
    for index, item in enumerate(values):
        if not isinstance(item, dict):
            raise CaptureError(f"Release asset {index} must be an object.")
        name = require_string(item.get("name"), f"Release asset {index} name")
        if name in assets:
            raise CaptureError(f"Release asset name is duplicated: {name}")
        size_limit = MANIFEST_MAX_BYTES if name.endswith("-build.json") else APP_MAX_BYTES
        size = require_integer(
            item.get("size"),
            f"Release asset {name} size",
            minimum=1,
            maximum=size_limit,
        )
        digest = require_string(item.get("digest"), f"Release asset {name} digest")
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise CaptureError(f"Release asset {name} has an invalid SHA-256 digest.")
        assets[name] = ReleaseAsset(
            name=name,
            size=size,
            digest=digest,
            state=require_string(item.get("state"), f"Release asset {name} state"),
        )

    release = Release(
        tag=tag,
        target_commit=target,
        draft=require_boolean(value.get("draft"), "Release draft state"),
        prerelease=require_boolean(value.get("prerelease"), "Release prerelease state"),
        assets=assets,
    )
    if release.draft or (channel == "tester" and not release.prerelease):
        raise CaptureError("Published updater source has an invalid release state.")
    if channel == "stable" and release.prerelease:
        raise CaptureError("Stable updater source must be a final release.")
    return release


def decode_manifest(
    payload: bytes,
    repository: str,
    channel: str,
    architecture: str,
    release: Release,
) -> SourceMetadata:
    if not payload or len(payload) > MANIFEST_MAX_BYTES:
        raise CaptureError("Published source manifest has an invalid byte size.")
    try:
        value = json.loads(payload)
    except json.JSONDecodeError as error:
        raise CaptureError(f"Published source manifest is malformed: {error}") from error
    if not isinstance(value, dict):
        raise CaptureError("Published source manifest must be an object.")

    if value.get("schemaVersion") != 1 or value.get("product") != PRODUCT:
        raise CaptureError("Published source manifest has an unsupported product contract.")
    if value.get("channel") != channel or value.get("tag") != release.tag:
        raise CaptureError("Published source manifest channel or tag disagrees with its release.")
    commit = require_string(value.get("commit"), "Source manifest commit")
    if commit != release.target_commit:
        raise CaptureError("Published source manifest commit disagrees with its release.")
    version = require_string(value.get("version"), "Source manifest version")
    if not VERSION_PATTERN.fullmatch(version):
        raise CaptureError("Published source manifest version must be canonical.")
    if channel == "stable" and release.tag != f"v{version}":
        raise CaptureError("Stable source manifest version disagrees with its release tag.")
    build = require_string(value.get("build"), "Source manifest build")
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise CaptureError("Published source manifest build must be a positive integer.")

    updater = value.get("updater")
    if not isinstance(updater, dict):
        raise CaptureError("Published source manifest updater must be an object.")
    if updater.get("bundleIdentifier") != BUNDLE_IDENTIFIER or updater.get("channel") != channel:
        raise CaptureError("Published source updater identity disagrees with its manifest.")
    assets = updater.get("macOSAppAssets")
    if not isinstance(assets, list):
        raise CaptureError("Published source updater assets must be an array.")
    matches = [asset for asset in assets if isinstance(asset, dict) and asset.get("arch") == architecture]
    if len(matches) != 1:
        raise CaptureError(f"Published source manifest must contain one {architecture} app asset.")
    asset = matches[0]
    expected_name = f"Quill-Cowork-macOS-{architecture}.zip"
    expected_url = (
        f"https://github.com/{repository}/releases/download/{release.tag}/{expected_name}"
    )
    if (
        asset.get("name") != expected_name
        or asset.get("platform") != "macOS"
        or asset.get("kind") != "app"
        or asset.get("install") != "zip-app"
        or asset.get("url") != expected_url
    ):
        raise CaptureError("Published source updater app asset has an invalid identity.")
    app_size = require_integer(
        asset.get("sizeBytes"),
        "Source app size",
        minimum=1,
        maximum=APP_MAX_BYTES,
    )
    app_digest = require_string(asset.get("sha256"), "Source app SHA-256")
    if not re.fullmatch(r"[0-9a-f]{64}", app_digest):
        raise CaptureError("Published source app SHA-256 is invalid.")

    return SourceMetadata(
        channel=channel,
        tag=release.tag,
        architecture=architecture,
        version=version,
        build=build,
        commit=commit,
        app_name=expected_name,
        app_size=app_size,
        app_digest=app_digest,
    )


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def repository_is_valid(value: str) -> bool:
    if not REPOSITORY_PATTERN.fullmatch(value):
        return False
    owner, name = value.split("/", maxsplit=1)
    return owner not in {".", ".."} and name not in {".", ".."}
