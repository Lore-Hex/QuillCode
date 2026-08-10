from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import tempfile

from updater_source_capture.contracts import (
    CaptureError,
    ReleaseAsset,
    SourceMetadata,
    decode_manifest,
    file_digest,
)
from updater_source_capture.remote import CaptureRemote


def validate_download(path: Path, release_asset: ReleaseAsset, expected_digest: str) -> None:
    size = path.stat().st_size
    digest = file_digest(path)
    if release_asset.state != "uploaded" or size != release_asset.size:
        raise CaptureError(f"Downloaded source asset size or state disagrees for {release_asset.name}.")
    if release_asset.digest != f"sha256:{digest}" or digest != expected_digest:
        raise CaptureError(f"Downloaded source asset digest disagrees for {release_asset.name}.")


def capture_payload(metadata: SourceMetadata) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "sourceAvailable": True,
        "channel": metadata.channel,
        "tag": metadata.tag,
        "architecture": metadata.architecture,
        "version": metadata.version,
        "build": metadata.build,
        "commit": metadata.commit,
        "appName": metadata.app_name,
        "appSizeBytes": metadata.app_size,
        "appSHA256": metadata.app_digest,
    }


def write_json(path: Path, value: dict[str, object]) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def capture_source(
    repository: str,
    channel: str,
    architecture: str,
    output_directory: Path,
    *,
    allow_missing: bool,
) -> None:
    if output_directory.exists() or output_directory.is_symlink():
        raise CaptureError("Capture output directory must not already exist.")
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    remote = CaptureRemote(repository, channel)
    release = remote.get_release(missing_ok=allow_missing)

    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{output_directory.name}.capture-",
            dir=output_directory.parent,
        )
    )
    try:
        if release is None:
            write_json(
                staging / "capture.json",
                {
                    "schemaVersion": 1,
                    "sourceAvailable": False,
                    "channel": channel,
                    "architecture": architecture,
                    "reason": "release-not-found",
                },
            )
            os.replace(staging, output_directory)
            print(f"No previous {channel} release exists for {architecture}; using first-release fallback.")
            return

        manifest_name = f"latest-{channel}-build.json"
        app_name = f"Quill-Cowork-macOS-{architecture}.zip"
        manifest_asset = release.assets.get(manifest_name)
        app_asset = release.assets.get(app_name)
        if manifest_asset is None or app_asset is None:
            raise CaptureError("Published source release is missing required updater assets.")

        downloads = staging / "downloads"
        downloads.mkdir()
        manifest_path = remote.download_asset(release, manifest_name, downloads)
        app_path = remote.download_asset(release, app_name, downloads)
        validate_download(
            manifest_path,
            manifest_asset,
            manifest_asset.digest.removeprefix("sha256:"),
        )
        manifest_bytes = manifest_path.read_bytes()
        metadata = decode_manifest(
            manifest_bytes,
            repository,
            channel,
            architecture,
            release,
        )
        validate_download(app_path, app_asset, metadata.app_digest)
        if app_path.stat().st_size != metadata.app_size:
            raise CaptureError("Downloaded source app size disagrees with its manifest.")

        shutil.copyfile(manifest_path, staging / "source-manifest.json")
        shutil.copyfile(app_path, staging / "source-app.zip")
        write_json(staging / "capture.json", capture_payload(metadata))
        shutil.rmtree(downloads)
        os.replace(staging, output_directory)
        print(
            f"Captured {channel} {architecture} updater source "
            f"{metadata.version} ({metadata.build}) at {metadata.commit}."
        )
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
