#!/usr/bin/env python3
"""Verify a published Quill Cowork release through its public download contract."""

from __future__ import annotations

import argparse
import os
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import quote

from release_verification_contract import (
    API_BYTE_LIMIT,
    MANIFEST_BYTE_LIMIT,
    REPOSITORY_PATTERN,
    SHA_PATTERN,
    VerificationError,
    discover_workflow_run_url,
    expected_urls,
    load_json_bytes,
    validate_manifest,
)
from release_verification_files import read_bounded, verify_asset_files
from release_verification_remote import (
    api_json,
    download_asset,
    fetch_bytes,
    resolve_tag_commit,
    retry,
)


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
    provenance = parser.add_mutually_exclusive_group(required=True)
    provenance.add_argument(
        "--workflow-run-url",
        help="Expected publishing run URL.",
    )
    provenance.add_argument(
        "--discover-workflow-run-url",
        action="store_true",
        help="Discover the expected publishing run URL from the bounded public manifest.",
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
    if arguments.discover_workflow_run_url:
        arguments.workflow_run_url = discover_workflow_run_url(
            manifest_bytes,
            arguments.repo,
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
    if arguments.discover_workflow_run_url:
        arguments.workflow_run_url = retry(
            lambda: discover_workflow_run_url(
                fetch_bytes(urls["manifest"], MANIFEST_BYTE_LIMIT),
                arguments.repo,
            ),
            attempts=arguments.attempts,
            delay=arguments.retry_delay,
            label="public release provenance",
        )

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
