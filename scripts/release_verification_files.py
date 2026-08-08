"""Bounded on-disk artifact validation for Quill Cowork releases."""

from __future__ import annotations

import hashlib
import plistlib
import re
import stat
import zipfile
from pathlib import Path
from typing import Any

from release_verification_contract import (
    BUNDLE_IDENTIFIER,
    PRODUCT,
    VerificationError,
)


APP_INFO_BYTE_LIMIT = 256 * 1024
APP_ARCHIVE_ENTRY_LIMIT = 20_000


def read_bounded(path: Path, byte_limit: int, label: str) -> bytes:
    try:
        if path.is_symlink() or not path.is_file():
            raise VerificationError(f"{label} must be a regular file")
        size = path.stat().st_size
        if size > byte_limit:
            raise VerificationError(f"{label} exceeds its {byte_limit}-byte limit")
        return path.read_bytes()
    except OSError as error:
        raise VerificationError(f"{label} could not be read") from error


def sha256_path(path: Path, expected_size: int, label: str) -> str:
    if path.is_symlink() or not path.is_file():
        raise VerificationError(f"{label} must be a regular file")
    digest = hashlib.sha256()
    size = 0
    try:
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                size += len(chunk)
                if size > expected_size:
                    raise VerificationError(f"{label} exceeds its declared size")
                digest.update(chunk)
    except OSError as error:
        raise VerificationError(f"{label} could not be read") from error
    if size != expected_size:
        raise VerificationError(
            f"{label} size mismatch: expected {expected_size}, downloaded {size}"
        )
    return digest.hexdigest()


def parse_key_value_file(path: Path, label: str) -> dict[str, str]:
    data = read_bounded(path, 256 * 1024, label)
    try:
        lines = data.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        raise VerificationError(f"{label} is not UTF-8") from error
    values: dict[str, str] = {}
    for line in lines:
        key, separator, value = line.partition("=")
        if not separator or not key or key in values:
            raise VerificationError(
                f"{label} contains malformed or duplicate metadata"
            )
        values[key] = value
    return values


def verify_build_info(
    asset_directory: Path,
    assets: list[dict[str, Any]],
    manifest: dict[str, Any],
    *,
    channel: str,
    commit: str,
) -> None:
    updater = manifest["updater"]
    app_asset = updater["macOSAppAsset"]
    build_info = parse_key_value_file(
        asset_directory / "BUILD_INFO.txt",
        "BUILD_INFO.txt",
    )
    signing_team = updater.get("signingTeamIdentifier") or "none"
    expected = {
        "product": PRODUCT,
        "platform": "macOS",
        "arch": app_asset["arch"],
        "version": manifest["version"],
        "build": manifest["build"],
        "commit": commit,
        "bundleIdentifier": BUNDLE_IDENTIFIER,
        "minimumSystemVersion": updater["minimumSystemVersion"],
        "updateChannel": channel,
        "updateManifestURL": updater["manifestURL"],
        "stableUpdateManifestURL": updater["stableManifestURL"],
        "testerUpdateManifestURL": updater["testerManifestURL"],
        "app": app_asset["name"],
        "codesign": updater.get("codesign") or "unknown",
        "signingTeamIdentifier": signing_team,
        "notarized": "true" if updater.get("notarized") is True else "false",
    }
    for key, expected_value in expected.items():
        if build_info.get(key) != expected_value:
            raise VerificationError(
                f"BUILD_INFO.txt {key} disagrees with the manifest"
            )
    asset_names = {asset["name"] for asset in assets}
    if build_info.get("cli") not in asset_names:
        raise VerificationError("BUILD_INFO.txt names a missing macOS CLI asset")


def verify_primary_checksums(
    asset_directory: Path,
    assets: list[dict[str, Any]],
) -> None:
    checksum_path = asset_directory / "SHASUMS256.txt"
    data = read_bounded(checksum_path, 1024 * 1024, "SHASUMS256.txt")
    try:
        lines = data.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        raise VerificationError("SHASUMS256.txt is not UTF-8") from error
    checksums: dict[str, str] = {}
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64})  ([^/\\]+)", line)
        if not match or match.group(2) in checksums:
            raise VerificationError(
                "SHASUMS256.txt contains malformed or duplicate entries"
            )
        checksums[match.group(2)] = match.group(1)
    expected = {
        asset["name"]: asset["sha256"]
        for asset in assets
        if asset["name"] != "SHASUMS256.txt"
    }
    if checksums != expected:
        raise VerificationError(
            "SHASUMS256.txt does not exactly cover the release assets"
        )


def verify_app_archive(
    asset_directory: Path,
    manifest: dict[str, Any],
    *,
    channel: str,
    commit: str,
) -> None:
    updater = manifest["updater"]
    app_asset = updater["macOSAppAsset"]
    archive_path = asset_directory / app_asset["name"]
    info_path = f"{PRODUCT}.app/Contents/Info.plist"
    try:
        with zipfile.ZipFile(archive_path) as archive:
            entries = archive.infolist()
            if len(entries) > APP_ARCHIVE_ENTRY_LIMIT:
                raise VerificationError("macOS app archive contains too many entries")
            matching_entries = [entry for entry in entries if entry.filename == info_path]
            if len(matching_entries) != 1:
                raise VerificationError("macOS app archive does not contain one canonical Info.plist")
            info_entry = matching_entries[0]
            if info_entry.is_dir() or info_entry.flag_bits & 0x1:
                raise VerificationError("macOS app Info.plist must be a readable regular entry")
            unix_file_type = stat.S_IFMT(info_entry.external_attr >> 16)
            if unix_file_type not in (0, stat.S_IFREG):
                raise VerificationError("macOS app Info.plist must be a readable regular entry")
            if info_entry.file_size > APP_INFO_BYTE_LIMIT:
                raise VerificationError("macOS app Info.plist exceeds its size limit")
            with archive.open(info_entry) as handle:
                info_bytes = handle.read(APP_INFO_BYTE_LIMIT + 1)
    except VerificationError:
        raise
    except (OSError, RuntimeError, zipfile.BadZipFile, zipfile.LargeZipFile) as error:
        raise VerificationError("macOS app archive is not a readable ZIP") from error
    if len(info_bytes) > APP_INFO_BYTE_LIMIT:
        raise VerificationError("macOS app Info.plist exceeds its size limit")
    try:
        values = plistlib.loads(info_bytes)
    except (plistlib.InvalidFileException, ValueError, TypeError) as error:
        raise VerificationError("macOS app Info.plist is invalid") from error
    if not isinstance(values, dict):
        raise VerificationError("macOS app Info.plist must contain a dictionary")

    expected = {
        "CFBundleName": PRODUCT,
        "CFBundleDisplayName": PRODUCT,
        "CFBundleIdentifier": BUNDLE_IDENTIFIER,
        "CFBundleShortVersionString": manifest["version"],
        "CFBundleVersion": manifest["build"],
        "LSMinimumSystemVersion": updater["minimumSystemVersion"],
        "QuillCodeBuildCommit": commit,
        "QuillCodeUpdateChannel": channel,
        "QuillCodeUpdateManifestURL": updater["manifestURL"],
        "QuillCodeStableUpdateManifestURL": updater["stableManifestURL"],
        "QuillCodeTesterUpdateManifestURL": updater["testerManifestURL"],
    }
    signing_team = updater.get("signingTeamIdentifier")
    if signing_team is not None:
        expected["QuillCodeSigningTeamIdentifier"] = signing_team
    for key, expected_value in expected.items():
        if values.get(key) != expected_value:
            raise VerificationError(
                f"macOS app Info.plist {key} disagrees with the manifest"
            )


def verify_asset_files(
    asset_directory: Path,
    assets: list[dict[str, Any]],
    manifest: dict[str, Any],
    *,
    channel: str,
    commit: str,
) -> None:
    if asset_directory.is_symlink() or not asset_directory.is_dir():
        raise VerificationError("asset directory must be a real directory")
    expected_names = {asset["name"] for asset in assets}
    actual_names = {path.name for path in asset_directory.iterdir()}
    if actual_names != expected_names:
        raise VerificationError(
            "downloaded asset directory does not exactly match the manifest"
        )
    for asset in assets:
        path = asset_directory / asset["name"]
        digest = sha256_path(path, asset["sizeBytes"], asset["name"])
        if digest != asset["sha256"]:
            raise VerificationError(
                f"downloaded asset {asset['name']!r} failed SHA-256 verification"
            )
    verify_primary_checksums(asset_directory, assets)
    verify_build_info(
        asset_directory,
        assets,
        manifest,
        channel=channel,
        commit=commit,
    )
    verify_app_archive(
        asset_directory,
        manifest,
        channel=channel,
        commit=commit,
    )
