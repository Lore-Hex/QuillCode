#!/usr/bin/env python3
"""Capture and verify the public app that must update to the next release."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from updater_source_capture.capture import capture_source
from updater_source_capture.contracts import CaptureError, repository_is_valid


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--channel", choices=["tester", "stable"], required=True)
    parser.add_argument("--arch", choices=["arm64", "x86_64"], required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--allow-missing", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    if not repository_is_valid(arguments.repo):
        raise CaptureError("Repository must use owner/name syntax.")
    capture_source(
        arguments.repo,
        arguments.channel,
        arguments.arch,
        arguments.output_dir,
        allow_missing=arguments.allow_missing,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CaptureError as error:
        print(f"Updater source capture failed: {error}", file=sys.stderr)
        raise SystemExit(1)
