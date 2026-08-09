#!/usr/bin/env python3
"""Verify a published Quill Cowork release through its public download contract."""

from __future__ import annotations

import argparse
import hashlib
import os
import tempfile
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path
from typing import Any, TypeVar
from urllib.parse import quote

from release_verification_contract import (
    API_BYTE_LIMIT,
    MANIFEST_BYTE_LIMIT,
    REPOSITORY_PATTERN,
    SHA_PATTERN,
    VerificationError,
    expected_urls,
    load_json_bytes,
    validate_manifest,
)
from release_verification_files import read_bounded, verify_asset_files


Result = TypeVar("Result")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download and verify a published Quill Cowork GitHub release."
    )
    parser.add_argument("--repo", required=True, help="GitHub owner/repository slug.")
    parser.add_argument("--tag", required=True, help="Published release tag.")
    parser.add_argument("--channel", required=True, choices=("stable", "tester"))
    parser.add_argument(
        "--stable-candidate",
        action="store_true",
        help="Require a public stable prerelease that has not been promoted to latest.",
    )
    parser.add_argument("--commit", required=True, help="Expected 40-character commit SHA.")
    parser.add_argument(
        "--workflow-run-url",
        required=True,
        help="Expected publishing run URL.",
    )
    parser.add_argument(
        "--attempts",
        type=int,
        default=6,
        help="Public snapshot retry count.",
    )
    parser.add_argument(
        "--retry-delay",
        type=float,
        default=5,
        help="Seconds between retries.",
    )
    parser.add_argument("--release-json", type=Path, help="Offline release API fixture.")
    parser.add_argument(
        "--latest-release-json",
        type=Path,
        help="Offline GitHub latest-release API fixture for final stable verification.",
    )
    parser.add_argument("--tag-commit", help="Offline resolved tag commit.")
    parser.add_argument("--manifest", type=Path, help="Offline manifest fixture.")
    parser.add_argument(
        "--stable-feed-manifest",
        type=Path,
        help="Offline latest-stable-build.json fixture for final stable verification.",
    )
    parser.add_argument(
        "--assets-dir",
        type=Path,
        help="Offline directory containing release assets.",
    )
    arguments = parser.parse_args()
    if not REPOSITORY_PATTERN.fullmatch(arguments.repo):
        parser.error("--repo must be an owner/repository slug")
    if not SHA_PATTERN.fullmatch(arguments.commit):
        parser.error("--commit must be a lowercase 40-character SHA")
    if arguments.attempts < 1 or arguments.attempts > 20:
        parser.error("--attempts must be between 1 and 20")
    if arguments.retry_delay < 0 or arguments.retry_delay > 60:
        parser.error("--retry-delay must be between 0 and 60 seconds")
    if arguments.stable_candidate and arguments.channel != "stable":
        parser.error("--stable-candidate requires --channel stable")
    offline_values = (
        arguments.release_json,
        arguments.tag_commit,
        arguments.manifest,
        arguments.assets_dir,
    )
    if any(value is not None for value in offline_values) and not all(
        value is not None for value in offline_values
    ):
        parser.error(
            "offline verification requires --release-json, --tag-commit, "
            "--manifest, and --assets-dir"
        )
    final_stable = arguments.channel == "stable" and not arguments.stable_candidate
    stable_promotion_values = (
        arguments.latest_release_json,
        arguments.stable_feed_manifest,
    )
    if arguments.release_json is not None and final_stable and not all(
        value is not None for value in stable_promotion_values
    ):
        parser.error(
            "offline final stable verification requires --latest-release-json "
            "and --stable-feed-manifest"
        )
    if (arguments.release_json is None or not final_stable) and any(
        value is not None for value in stable_promotion_values
    ):
        parser.error(
            "latest-release fixtures are only valid for offline final stable verification"
        )
    return arguments


def fetch_bytes(
    url: str,
    byte_limit: int,
    *,
    token: str | None = None,
    accept: str = "application/octet-stream",
) -> bytes:
    headers = {
        "Accept": accept,
        "User-Agent": "Quill-Cowork-Release-Verifier/1",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise VerificationError(f"GET {url} returned HTTP {response.status}")
            length = response.headers.get("Content-Length")
            if length and int(length) > byte_limit:
                raise VerificationError(
                    f"GET {url} exceeds its {byte_limit}-byte limit"
                )
            data = response.read(byte_limit + 1)
    except VerificationError:
        raise
    except urllib.error.HTTPError as error:
        raise VerificationError(f"GET {url} returned HTTP {error.code}") from error
    except urllib.error.URLError as error:
        raise VerificationError(f"GET {url} failed: {error.reason}") from error
    except (OSError, ValueError) as error:
        raise VerificationError(f"GET {url} failed: {error}") from error
    if len(data) > byte_limit:
        raise VerificationError(f"GET {url} exceeds its {byte_limit}-byte limit")
    return data


def api_json(repo: str, path: str, token: str | None) -> dict[str, Any]:
    url = f"https://api.github.com/repos/{repo}/{path}"
    return load_json_bytes(
        fetch_bytes(
            url,
            API_BYTE_LIMIT,
            token=token,
            accept="application/vnd.github+json",
        ),
        url,
    )


def resolve_tag_commit(repo: str, tag: str, token: str | None) -> str:
    reference = api_json(repo, f"git/ref/tags/{quote(tag, safe='')}", token)
    target = reference.get("object")
    for _ in range(5):
        if not isinstance(target, dict):
            break
        target_type = target.get("type")
        sha = target.get("sha")
        if not isinstance(sha, str) or not SHA_PATTERN.fullmatch(sha):
            break
        if target_type == "commit":
            return sha
        if target_type != "tag":
            break
        tag_object = api_json(repo, f"git/tags/{sha}", token)
        target = tag_object.get("object")
    raise VerificationError(f"release tag {tag!r} does not resolve to a commit")


def download_asset(url: str, destination: Path, size: int, digest: str) -> None:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/octet-stream",
            "User-Agent": "Quill-Cowork-Release-Verifier/1",
        },
    )
    temporary = destination.with_suffix(destination.suffix + ".part")
    try:
        with urllib.request.urlopen(request, timeout=60) as response, temporary.open(
            "xb"
        ) as output:
            if response.status != 200 or not response.geturl().lower().startswith(
                "https://"
            ):
                raise VerificationError(
                    f"download for {destination.name!r} returned an invalid response"
                )
            response_length = response.headers.get("Content-Length")
            if response_length and int(response_length) != size:
                raise VerificationError(
                    f"download for {destination.name!r} reported the wrong size"
                )
            hasher = hashlib.sha256()
            downloaded = 0
            while chunk := response.read(1024 * 1024):
                downloaded += len(chunk)
                if downloaded > size:
                    raise VerificationError(
                        f"download for {destination.name!r} exceeded its size"
                    )
                output.write(chunk)
                hasher.update(chunk)
        if downloaded != size or hasher.hexdigest() != digest:
            raise VerificationError(
                f"download for {destination.name!r} failed integrity verification"
            )
        temporary.replace(destination)
    except VerificationError:
        temporary.unlink(missing_ok=True)
        raise
    except urllib.error.HTTPError as error:
        temporary.unlink(missing_ok=True)
        raise VerificationError(
            f"download for {destination.name!r} returned HTTP {error.code}"
        ) from error
    except urllib.error.URLError as error:
        temporary.unlink(missing_ok=True)
        raise VerificationError(
            f"download for {destination.name!r} failed: {error.reason}"
        ) from error
    except (OSError, ValueError) as error:
        temporary.unlink(missing_ok=True)
        raise VerificationError(
            f"download for {destination.name!r} failed: {error}"
        ) from error


def retry(
    operation: Callable[[], Result],
    *,
    attempts: int,
    delay: float,
    label: str,
) -> Result:
    last_error: VerificationError | None = None
    for attempt in range(1, attempts + 1):
        try:
            return operation()
        except VerificationError as error:
            last_error = error
            if attempt < attempts:
                print(
                    f"{label} attempt {attempt} failed: {error}; retrying",
                    flush=True,
                )
                time.sleep(delay)
    if last_error is None:
        raise VerificationError(f"{label} did not run")
    raise last_error


def validate_snapshot(
    release: dict[str, Any],
    manifest_bytes: bytes,
    tag_commit: str,
    arguments: argparse.Namespace,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    manifest = load_json_bytes(manifest_bytes, "manifest")
    assets = validate_manifest(
        manifest,
        manifest_bytes,
        release,
        tag_commit,
        repo=arguments.repo,
        tag=arguments.tag,
        channel=arguments.channel,
        commit=arguments.commit,
        workflow_run_url=arguments.workflow_run_url,
        stable_candidate=arguments.stable_candidate,
    )
    return manifest, assets


def validate_stable_promotion(
    release: dict[str, Any],
    latest_release: dict[str, Any],
    manifest_bytes: bytes,
    stable_feed_bytes: bytes,
    tag: str,
) -> None:
    release_id = release.get("id")
    if type(release_id) is not int or latest_release.get("id") != release_id:
        raise VerificationError("GitHub latest release is not the verified stable release")
    if latest_release.get("tag_name") != tag:
        raise VerificationError("GitHub latest release tag does not match the stable tag")
    if stable_feed_bytes != manifest_bytes:
        raise VerificationError(
            "latest stable feed does not match the versioned release manifest"
        )


def verify_offline(arguments: argparse.Namespace) -> None:
    if (
        arguments.release_json is None
        or arguments.tag_commit is None
        or arguments.manifest is None
        or arguments.assets_dir is None
    ):
        raise VerificationError("offline verifier arguments are incomplete")
    release = load_json_bytes(
        read_bounded(arguments.release_json, API_BYTE_LIMIT, "release JSON"),
        "release JSON",
    )
    manifest_bytes = read_bounded(
        arguments.manifest,
        MANIFEST_BYTE_LIMIT,
        "manifest",
    )
    manifest, assets = validate_snapshot(
        release,
        manifest_bytes,
        arguments.tag_commit,
        arguments,
    )
    if arguments.channel == "stable" and not arguments.stable_candidate:
        latest_release = load_json_bytes(
            read_bounded(
                arguments.latest_release_json,
                API_BYTE_LIMIT,
                "latest release JSON",
            ),
            "latest release JSON",
        )
        stable_feed_bytes = read_bounded(
            arguments.stable_feed_manifest,
            MANIFEST_BYTE_LIMIT,
            "stable feed manifest",
        )
        validate_stable_promotion(
            release,
            latest_release,
            manifest_bytes,
            stable_feed_bytes,
            arguments.tag,
        )
    verify_asset_files(
        arguments.assets_dir,
        assets,
        manifest,
        channel=arguments.channel,
        commit=arguments.commit,
    )


def verify_public(arguments: argparse.Namespace) -> None:
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    urls = expected_urls(arguments.repo, arguments.tag, arguments.channel)

    def fetch_snapshot() -> tuple[dict[str, Any], list[dict[str, Any]]]:
        release = api_json(
            arguments.repo,
            f"releases/tags/{quote(arguments.tag, safe='')}",
            token,
        )
        tag_commit = resolve_tag_commit(arguments.repo, arguments.tag, token)
        manifest_bytes = fetch_bytes(urls["manifest"], MANIFEST_BYTE_LIMIT)
        if arguments.channel == "stable" and not arguments.stable_candidate:
            latest_release = api_json(arguments.repo, "releases/latest", token)
            stable_feed_bytes = fetch_bytes(urls["stable"], MANIFEST_BYTE_LIMIT)
            validate_stable_promotion(
                release,
                latest_release,
                manifest_bytes,
                stable_feed_bytes,
                arguments.tag,
            )
        return validate_snapshot(release, manifest_bytes, tag_commit, arguments)

    manifest, assets = retry(
        fetch_snapshot,
        attempts=arguments.attempts,
        delay=arguments.retry_delay,
        label="public release snapshot",
    )
    with tempfile.TemporaryDirectory(
        prefix="quill-cowork-release-verify-"
    ) as directory:
        asset_directory = Path(directory)
        for asset in assets:
            destination = asset_directory / asset["name"]
            retry(
                lambda asset=asset, destination=destination: download_asset(
                    asset["url"],
                    destination,
                    asset["sizeBytes"],
                    asset["sha256"],
                ),
                attempts=3,
                delay=arguments.retry_delay,
                label=f"asset {asset['name']}",
            )
        verify_asset_files(
            asset_directory,
            assets,
            manifest,
            channel=arguments.channel,
            commit=arguments.commit,
        )


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.release_json is not None:
            verify_offline(arguments)
        else:
            verify_public(arguments)
    except VerificationError as error:
        print(f"Published release verification failed: {error}", file=os.sys.stderr)
        return 2
    print(
        f"Verified public Quill Cowork {arguments.channel} release {arguments.tag} "
        f"at {arguments.commit}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
