from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
from typing import Any, Iterable


TAG = "tester-latest"
TITLE_PREFIX = "Quill Cowork Tester"
MANIFEST_NAME = "latest-tester-build.json"
MANIFEST_MAXIMUM_BYTES = 1_048_576
ASSET_NAME_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,179}")
COMMIT_PATTERN = re.compile(r"[0-9a-f]{40}")
REPOSITORY_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
RUN_ID_PATTERN = re.compile(r"[1-9][0-9]*")
VERSION_PATTERN = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
)
BUILD_PATTERN = re.compile(r"[1-9][0-9]*")
TRANSACTION_ALIAS_PATTERN = re.compile(
    r"quill-cowork-(candidate|rollback)-([1-9][0-9]*)-(.+)"
)


class PublicationError(RuntimeError):
    pass


@dataclass(frozen=True)
class LocalAsset:
    name: str
    path: Path
    size: int
    digest: str


@dataclass(frozen=True)
class TesterReleaseIdentity:
    version: str
    build: str

    @property
    def title(self) -> str:
        return f"{TITLE_PREFIX} {self.version} ({self.build})"


@dataclass(frozen=True)
class RemoteAsset:
    identifier: int
    name: str
    size: int
    digest: str
    state: str


@dataclass(frozen=True)
class ReleaseSnapshot:
    identifier: int
    tag_name: str
    target_commitish: str
    name: str
    body: str
    draft: bool
    prerelease: bool
    immutable: bool
    assets: dict[str, RemoteAsset]


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise PublicationError(f"GitHub release {label} must be a string.")
    return value


def require_boolean(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise PublicationError(f"GitHub release {label} must be a boolean.")
    return value


def require_integer(value: Any, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise PublicationError(f"GitHub release {label} must be a positive integer.")
    return value


def decode_release(payload: str) -> ReleaseSnapshot:
    try:
        value = json.loads(payload)
    except json.JSONDecodeError as error:
        raise PublicationError(f"GitHub returned malformed release JSON: {error}") from error
    if not isinstance(value, dict):
        raise PublicationError("GitHub release response must be an object.")

    assets_value = value.get("assets")
    if not isinstance(assets_value, list):
        raise PublicationError("GitHub release assets must be an array.")
    assets: dict[str, RemoteAsset] = {}
    identifiers: set[int] = set()
    for index, item in enumerate(assets_value):
        if not isinstance(item, dict):
            raise PublicationError(f"GitHub release asset {index} must be an object.")
        name = require_string(item.get("name"), f"asset {index} name")
        identifier = require_integer(item.get("id"), f"asset {name} id")
        size = item.get("size")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise PublicationError(f"GitHub release asset {name} size must be non-negative.")
        digest = require_string(item.get("digest"), f"asset {name} digest")
        state = require_string(item.get("state"), f"asset {name} state")
        if name in assets or identifier in identifiers:
            raise PublicationError("GitHub release asset names and identifiers must be unique.")
        assets[name] = RemoteAsset(identifier, name, size, digest, state)
        identifiers.add(identifier)

    return ReleaseSnapshot(
        identifier=require_integer(value.get("id"), "id"),
        tag_name=require_string(value.get("tag_name"), "tag_name"),
        target_commitish=require_string(value.get("target_commitish"), "target_commitish"),
        name=require_string(value.get("name"), "name"),
        body=require_string(value.get("body"), "body"),
        draft=require_boolean(value.get("draft"), "draft"),
        prerelease=require_boolean(value.get("prerelease"), "prerelease"),
        immutable=require_boolean(value.get("immutable", False), "immutable"),
        assets=assets,
    )


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def load_local_assets(directory: Path) -> dict[str, LocalAsset]:
    if not directory.is_dir() or directory.is_symlink():
        raise PublicationError("Release assets directory must be a real directory.")
    assets: dict[str, LocalAsset] = {}
    for path in directory.iterdir():
        if not path.is_file() or path.is_symlink():
            raise PublicationError(f"Release asset must be a regular file: {path.name}")
        name = path.name
        if not ASSET_NAME_PATTERN.fullmatch(name):
            raise PublicationError(f"Release asset has an unsafe name: {name!r}")
        if TRANSACTION_ALIAS_PATTERN.fullmatch(name):
            raise PublicationError(f"Release asset collides with transaction namespace: {name}")
        assets[name] = LocalAsset(name, path, path.stat().st_size, file_digest(path))
    if not assets or len(assets) > 64:
        raise PublicationError("Release must contain between 1 and 64 assets.")
    if MANIFEST_NAME not in assets:
        raise PublicationError(f"Release assets must include {MANIFEST_NAME}.")
    return assets


def load_tester_release_identity(
    assets: dict[str, LocalAsset],
    *,
    repository: str,
    commit: str,
    run_id: str,
) -> TesterReleaseIdentity:
    manifest_asset = assets[MANIFEST_NAME]
    if manifest_asset.size <= 0 or manifest_asset.size > MANIFEST_MAXIMUM_BYTES:
        raise PublicationError("Tester manifest must contain between 1 byte and 1 MiB.")
    try:
        value = json.loads(manifest_asset.path.read_bytes().decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PublicationError("Tester manifest must be valid UTF-8 JSON.") from error
    if not isinstance(value, dict):
        raise PublicationError("Tester manifest must be a JSON object.")

    expected = {
        "product": "Quill Cowork",
        "channel": "tester",
        "tag": TAG,
        "releaseURL": f"https://github.com/{repository}/releases/tag/{TAG}",
        "commit": commit,
        "workflowRunURL": f"https://github.com/{repository}/actions/runs/{run_id}",
    }
    if type(value.get("schemaVersion")) is not int or value["schemaVersion"] != 1:
        raise PublicationError("Tester manifest schemaVersion must be 1.")
    for field, expected_value in expected.items():
        if value.get(field) != expected_value:
            raise PublicationError(f"Tester manifest {field} disagrees with publication.")

    version = value.get("version")
    build = value.get("build")
    if not isinstance(version, str) or VERSION_PATTERN.fullmatch(version) is None:
        raise PublicationError("Tester manifest version must be canonical semantic versioning.")
    if not isinstance(build, str) or BUILD_PATTERN.fullmatch(build) is None:
        raise PublicationError("Tester manifest build must be a positive canonical integer.")
    return TesterReleaseIdentity(version=version, build=build)


def ordered_asset_names(names: Iterable[str]) -> list[str]:
    name_set = set(names)
    values = sorted(name for name in name_set if name != MANIFEST_NAME)
    if MANIFEST_NAME in name_set:
        values.append(MANIFEST_NAME)
    return values


def validate_release_metadata(
    release: ReleaseSnapshot,
    commit: str,
    title: str,
    notes: str,
) -> None:
    if (
        release.tag_name != TAG
        or release.target_commitish != commit
        or release.name != title
        or release.body != notes
        or release.draft
        or not release.prerelease
        or release.immutable
    ):
        raise PublicationError("Published tester release metadata disagrees with the transaction.")


def validate_exact_assets(
    release: ReleaseSnapshot,
    assets: dict[str, LocalAsset],
) -> None:
    if set(release.assets) != set(assets):
        raise PublicationError("Published tester release has an unexpected asset inventory.")
    for name, local in assets.items():
        remote = release.assets[name]
        if remote.state != "uploaded" or remote.size != local.size or remote.digest != local.digest:
            raise PublicationError(f"Published GitHub asset metadata disagrees for {name}.")
