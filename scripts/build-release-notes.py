#!/usr/bin/env python3
"""Build the human-facing GitHub release page for Quill Cowork downloads."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from pathlib import Path
from urllib.parse import quote


PRODUCT = "Quill Cowork"
MAXIMUM_BUILD_INFO_BYTES = 64 * 1024
REPOSITORY_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
COMMIT_PATTERN = re.compile(r"[0-9a-f]{40}")
VERSION_PATTERN = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")
MINIMUM_SYSTEM_PATTERN = re.compile(r"[0-9]+(?:\.[0-9]+){1,2}")
TEAM_IDENTIFIER_PATTERN = re.compile(r"[A-Z0-9]{10}")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write tested, architecture-specific GitHub release notes for Quill Cowork."
    )
    parser.add_argument("--build-info", required=True, help="Canonical macOS BUILD_INFO.txt path.")
    parser.add_argument("--repo", required=True, help="GitHub repository, for example Lore-Hex/QuillCode.")
    parser.add_argument("--tag", required=True, help="Release tag used in asset URLs.")
    parser.add_argument("--channel", required=True, choices=("stable", "tester"))
    parser.add_argument("--commit", required=True, help="Exact 40-character source commit.")
    parser.add_argument("--workflow-run-url", required=True, help="Exact GitHub Actions run URL.")
    parser.add_argument("--output", required=True, help="Markdown output path.")
    return parser.parse_args()


def parse_build_info(path: Path) -> dict[str, str]:
    try:
        stat = path.stat()
    except OSError as error:
        raise SystemExit(f"unable to inspect build metadata: {error}") from error
    if not path.is_file() or stat.st_size > MAXIMUM_BUILD_INFO_BYTES:
        raise SystemExit("build metadata must be a regular file no larger than 64 KiB")

    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise SystemExit(f"unable to read build metadata: {error}") from error
    for line in lines:
        key, separator, value = line.partition("=")
        if not separator or not key or key in values:
            raise SystemExit("build metadata contains a malformed or duplicate field")
        values[key] = value
    return values


def require_value(values: dict[str, str], key: str) -> str:
    value = values.get(key)
    if not value:
        raise SystemExit(f"build metadata is missing {key}")
    return value


def validate_inputs(arguments: argparse.Namespace, values: dict[str, str]) -> None:
    if not REPOSITORY_PATTERN.fullmatch(arguments.repo):
        raise SystemExit("repo must be an owner/name GitHub repository slug")
    if not COMMIT_PATTERN.fullmatch(arguments.commit):
        raise SystemExit("commit must be a lowercase 40-character hexadecimal SHA")

    expected_tag = "tester-latest" if arguments.channel == "tester" else None
    if expected_tag is not None and arguments.tag != expected_tag:
        raise SystemExit("tester release notes must use the tester-latest tag")
    if arguments.channel == "stable" and not re.fullmatch(
        r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)",
        arguments.tag,
    ):
        raise SystemExit("stable release notes require a canonical vMAJOR.MINOR.PATCH tag")

    expected_run_prefix = f"https://github.com/{arguments.repo}/actions/runs/"
    run_identifier = arguments.workflow_run_url.removeprefix(expected_run_prefix)
    if not run_identifier.isdigit() or not arguments.workflow_run_url.startswith(expected_run_prefix):
        raise SystemExit("workflow run URL must identify a numeric run in the configured repository")

    expected_values = {
        "product": PRODUCT,
        "platform": "macOS",
        "arch": "arm64",
        "configuration": "release",
        "commit": arguments.commit,
        "updateChannel": arguments.channel,
    }
    for key, expected in expected_values.items():
        if values.get(key) != expected:
            raise SystemExit(f"BUILD_INFO {key} must be {expected!r}, found {values.get(key)!r}")

    version = require_value(values, "version")
    build = require_value(values, "build")
    minimum_system = require_value(values, "minimumSystemVersion")
    if not VERSION_PATTERN.fullmatch(version):
        raise SystemExit("BUILD_INFO version must be canonical MAJOR.MINOR.PATCH")
    if arguments.channel == "stable" and arguments.tag != f"v{version}":
        raise SystemExit("stable release tag must match the packaged app version")
    if not build.isdigit() or int(build) <= 0:
        raise SystemExit("BUILD_INFO build must be a positive integer")
    if not MINIMUM_SYSTEM_PATTERN.fullmatch(minimum_system):
        raise SystemExit("BUILD_INFO minimumSystemVersion is malformed")

    codesign = require_value(values, "codesign")
    notarized = require_value(values, "notarized")
    signing_team = require_value(values, "signingTeamIdentifier")
    if codesign == "ad-hoc":
        if notarized != "false" or signing_team != "none":
            raise SystemExit("ad-hoc BUILD_INFO must be unnotarized and have no signing team")
    elif codesign == "developer-id":
        if notarized != "true" or not TEAM_IDENTIFIER_PATTERN.fullmatch(signing_team):
            raise SystemExit("Developer ID BUILD_INFO must be notarized and name a valid team")
    else:
        raise SystemExit("BUILD_INFO codesign must be ad-hoc or developer-id")
    if arguments.channel == "stable" and codesign != "developer-id":
        raise SystemExit("stable release notes require a notarized Developer ID build")


def release_asset_url(repo: str, tag: str, name: str) -> str:
    return (
        f"https://github.com/{repo}/releases/download/"
        f"{quote(tag, safe='')}/{quote(name, safe='')}"
    )


def markdown_link(label: str, repo: str, tag: str, name: str) -> str:
    return f"[{label}]({release_asset_url(repo, tag, name)})"


def build_release_notes(arguments: argparse.Namespace, values: dict[str, str]) -> str:
    repo = arguments.repo
    tag = arguments.tag
    commit = arguments.commit
    version = values["version"]
    build = values["build"]
    minimum_system = values["minimumSystemVersion"]
    channel_label = "Stable" if arguments.channel == "stable" else "Tester"
    manifest_name = f"latest-{arguments.channel}-build.json"
    screenshot_url = (
        f"https://raw.githubusercontent.com/{repo}/{commit}/"
        "docs/images/quill-cowork-desktop.png"
    )

    arm_installer = markdown_link(
        "Download for Apple silicon",
        repo,
        tag,
        "Quill-Cowork-macOS-arm64.dmg",
    )
    intel_installer = markdown_link(
        "Download for Intel",
        repo,
        tag,
        "Quill-Cowork-macOS-x86_64.dmg",
    )
    if values["codesign"] == "developer-id":
        signing_alert = (
            "> [!NOTE]\n"
            "> This build is Developer ID signed, notarized by Apple, and stapled for normal first launch."
        )
        signing_summary = f"Developer ID, notarized (team `{values['signingTeamIdentifier']}`)"
    else:
        signing_alert = (
            "> [!IMPORTANT]\n"
            "> This tester build is ad-hoc signed and not Apple-notarized. After dragging it to "
            "Applications, Control-click **Quill Cowork**, choose **Open**, then confirm."
        )
        signing_summary = "Ad-hoc; not notarized"

    return f"""# Download Quill Cowork

![Quill Cowork desktop app]({screenshot_url})

Native macOS coding agent and AI coworker for real project work.

**{channel_label} version {version} (build {build})** | **macOS {minimum_system} or later**

| Your Mac | Installer |
| --- | --- |
| Apple silicon (M-series) | **{arm_installer}** |
| Intel processor | **{intel_installer}** |

Not sure which Mac you have? Open **Apple menu > About This Mac**. Choose Apple silicon when it
shows **Chip**, or Intel when it shows **Processor**.

## Install

1. Open the downloaded disk image.
2. Drag **Quill Cowork.app** onto **Applications**.
3. Eject the disk image and launch Quill Cowork from **Applications**.

{signing_alert}

Computer Use requires the normal macOS Screen Recording and Accessibility permissions.

## Automatic Updates

Once installed in **Applications**, Quill Cowork checks this {arguments.channel} channel automatically.
You can also choose **Quill Cowork > Check for Updates...**. Updates are verified
against their declared size, SHA-256, app identity, architecture, source commit, and code signature;
activation is atomic, and the previous build is restored if the new build cannot finish launching.

<details>
<summary>CLI downloads, updater archives, checksums, and performance evidence</summary>

- {markdown_link("Apple silicon updater archive", repo, tag, "Quill-Cowork-macOS-arm64.zip")}
- {markdown_link("Intel updater archive", repo, tag, "Quill-Cowork-macOS-x86_64.zip")}
- {markdown_link("Apple silicon macOS CLI", repo, tag, "quill-code-macOS-arm64.tar.gz")}
- {markdown_link("Intel macOS CLI", repo, tag, "quill-code-macOS-x86_64.tar.gz")}
- {markdown_link("Linux x86_64 CLI", repo, tag, "quill-code-linux-x86_64.tar.gz")}
- {markdown_link("Apple silicon performance evidence", repo, tag, "Quill-Cowork-macOS-arm64-PERFORMANCE.json")}
- {markdown_link("Intel performance evidence", repo, tag, "Quill-Cowork-macOS-x86_64-PERFORMANCE.json")}
- {markdown_link("SHA-256 checksums", repo, tag, "SHASUMS256.txt")}
- {markdown_link("Machine-readable update manifest", repo, tag, manifest_name)}

</details>

## Build Provenance

- Source: [`{commit[:8]}`](https://github.com/{repo}/commit/{commit})
- GitHub Actions: [verified build and publication run]({arguments.workflow_run_url})
- Update channel: `{arguments.channel}`
- Signing: {signing_summary}
- Manifest: {markdown_link(f"`{manifest_name}`", repo, tag, manifest_name)}
"""


def write_atomically(path: Path, contents: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            handle.write(contents)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def main() -> None:
    arguments = parse_arguments()
    values = parse_build_info(Path(arguments.build_info))
    validate_inputs(arguments, values)
    notes = build_release_notes(arguments, values)
    write_atomically(Path(arguments.output), notes)
    print(f"Wrote Quill Cowork {arguments.channel} release notes to {arguments.output}")


if __name__ == "__main__":
    main()
