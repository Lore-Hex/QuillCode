"""Command-line entrypoint for native click-probe contract validation."""

from __future__ import annotations

import argparse
from pathlib import Path

from .accessibility_frames import write_accessibility_frames_manifest
from .packaged_window import (
    validate_packaged_window_report,
    write_accessibility_readiness_manifest,
    write_comparison_manifest,
)
from .probe_contracts import validate_report


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate QuillCode native click-probe contracts emitted by smoke reports.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="validate one native smoke report's click probes")
    validate_parser.add_argument("report", type=Path)
    validate_parser.add_argument("--label", default="quill-code-desktop native smoke")

    compare_parser = subparsers.add_parser("compare", help="compare direct executable and Launch Services click probes")
    compare_parser.add_argument("direct_report", type=Path)
    compare_parser.add_argument("launch_services_report", type=Path)
    compare_parser.add_argument("--manifest", required=True, type=Path)

    readiness_parser = subparsers.add_parser("readiness", help="write packaged native Accessibility readiness evidence")
    readiness_parser.add_argument("artifact_root", type=Path)
    readiness_parser.add_argument("--manifest", required=True, type=Path)

    window_parser = subparsers.add_parser("window", help="validate packaged live-window smoke report and screenshot")
    window_parser.add_argument("report", type=Path)
    window_parser.add_argument("screenshot", type=Path)

    frames_parser = subparsers.add_parser("frames", help="write live packaged Accessibility frame evidence")
    frames_parser.add_argument("report", type=Path)
    frames_parser.add_argument("screenshot", type=Path)
    frames_parser.add_argument("--click-probe-manifest", type=Path)
    frames_parser.add_argument("--manifest", required=True, type=Path)

    args = parser.parse_args()
    if args.command == "validate":
        validate_report(args.report, args.label)
    elif args.command == "compare":
        write_comparison_manifest(args.direct_report, args.launch_services_report, args.manifest)
    elif args.command == "readiness":
        write_accessibility_readiness_manifest(args.artifact_root, args.manifest)
    elif args.command == "window":
        validate_packaged_window_report(args.report, args.screenshot)
    elif args.command == "frames":
        write_accessibility_frames_manifest(
            args.report,
            args.screenshot,
            args.click_probe_manifest,
            args.manifest,
        )
