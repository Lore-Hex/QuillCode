#!/usr/bin/env python3
"""Publish the moving tester release with recoverable asset replacement."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from tester_publication.contracts import (
    COMMIT_PATTERN,
    PublicationError,
    REPOSITORY_PATTERN,
    RUN_ID_PATTERN,
    load_local_assets,
    load_tester_release_identity,
)
from tester_publication.publisher import TesterReleasePublisher


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets-dir", required=True, type=Path)
    parser.add_argument("--notes-file", required=True, type=Path)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--retry-delay-seconds", type=float, default=1.0)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    if not REPOSITORY_PATTERN.fullmatch(arguments.repo):
        raise PublicationError("Repository must use owner/name syntax.")
    if not COMMIT_PATTERN.fullmatch(arguments.commit):
        raise PublicationError("Commit must be a full lowercase SHA-1.")
    if not RUN_ID_PATTERN.fullmatch(arguments.run_id):
        raise PublicationError("Run ID must be a positive integer.")
    if arguments.retry_delay_seconds < 0 or arguments.retry_delay_seconds > 30:
        raise PublicationError("Retry delay must be between zero and 30 seconds.")
    if not arguments.notes_file.is_file() or arguments.notes_file.is_symlink():
        raise PublicationError("Release notes must be a regular file.")
    notes_bytes = arguments.notes_file.read_bytes()
    if not notes_bytes or len(notes_bytes) > 1_048_576:
        raise PublicationError("Release notes must contain between 1 byte and 1 MiB.")
    try:
        notes = notes_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PublicationError("Release notes must be UTF-8.") from error

    assets = load_local_assets(arguments.assets_dir)
    identity = load_tester_release_identity(
        assets,
        repository=arguments.repo,
        commit=arguments.commit,
        run_id=arguments.run_id,
    )
    TesterReleasePublisher(
        repository=arguments.repo,
        commit=arguments.commit,
        run_id=arguments.run_id,
        assets=assets,
        title=identity.title,
        notes=notes,
        notes_path=arguments.notes_file,
        retry_delay_seconds=arguments.retry_delay_seconds,
    ).publish()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PublicationError as error:
        print(f"Tester publication failed: {error}", file=sys.stderr)
        raise SystemExit(1)
