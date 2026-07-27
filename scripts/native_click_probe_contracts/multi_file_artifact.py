"""Validate packaged multi-file artifact smoke evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, require

EXPECTED_PROMPT = "Create the team action brief from `notes/research.md` and `notes/risks.md`."
EXPECTED_TOOL_SEQUENCE = ["host.file.read", "host.file.read", "host.file.write"]


def validated_multi_file_artifact(report: dict[str, Any], label: str) -> dict[str, Any]:
    smoke = report.get("multiFileArtifactSmoke")
    require(isinstance(smoke, dict), f"{label} report is missing multiFileArtifactSmoke")

    require(
        smoke.get("prompt") == EXPECTED_PROMPT,
        f"{label} multi-file prompt was {smoke.get('prompt')!r}, expected {EXPECTED_PROMPT!r}",
    )
    require(
        smoke.get("toolSequence") == EXPECTED_TOOL_SEQUENCE,
        f"{label} multi-file tool sequence was {smoke.get('toolSequence')!r}",
    )
    for field in (
        "deliverableContainsResearch",
        "deliverableContainsRisk",
        "deliverableContainsNextAction",
    ):
        require(smoke.get(field) is True, f"{label} multi-file artifact did not satisfy {field}")

    source_paths = smoke.get("sourcePaths")
    require(
        isinstance(source_paths, list) and len(source_paths) == 2,
        f"{label} multi-file artifact sourcePaths was malformed: {source_paths!r}",
    )
    for expected_suffix in ("notes/research.md", "notes/risks.md"):
        require(
            any(isinstance(path, str) and path.endswith(expected_suffix) for path in source_paths),
            f"{label} multi-file artifact missed {expected_suffix}: {source_paths!r}",
        )

    deliverable_path = smoke.get("deliverablePath")
    require(
        isinstance(deliverable_path, str) and deliverable_path.endswith("team-action-brief.md"),
        f"{label} multi-file deliverable path was malformed: {deliverable_path!r}",
    )
    final_answer = smoke.get("finalAnswer")
    require(
        isinstance(final_answer, str) and "Created `team-action-brief.md`" in final_answer,
        f"{label} multi-file final answer was malformed: {final_answer!r}",
    )
    return smoke


def semantic_multi_file_artifact(smoke: dict[str, Any]) -> dict[str, Any]:
    source_paths = smoke["sourcePaths"]
    return {
        "prompt": smoke["prompt"],
        "toolSequence": smoke["toolSequence"],
        "sourcePathSuffixes": sorted(
            "notes/research.md" if str(path).endswith("notes/research.md") else "notes/risks.md"
            for path in source_paths
        ),
        "deliverablePathSuffix": "team-action-brief.md",
        "deliverableContainsResearch": smoke["deliverableContainsResearch"],
        "deliverableContainsRisk": smoke["deliverableContainsRisk"],
        "deliverableContainsNextAction": smoke["deliverableContainsNextAction"],
        "finalAnswer": smoke["finalAnswer"],
    }


def write_multi_file_artifact_manifest(
    direct_report_path: Path,
    launch_services_report_path: Path,
    manifest_path: Path,
) -> None:
    direct = validated_multi_file_artifact(load_report(direct_report_path), "direct executable")
    launch_services = validated_multi_file_artifact(
        load_report(launch_services_report_path),
        "Launch Services",
    )
    direct_semantic = semantic_multi_file_artifact(direct)
    launch_services_semantic = semantic_multi_file_artifact(launch_services)
    require(
        direct_semantic == launch_services_semantic,
        "Packaged app Launch Services multi-file artifact smoke drifted from direct executable smoke",
    )

    manifest = {
        "ok": True,
        "directReport": "direct-executable/report.json",
        "launchServicesReport": "launch-services/report.json",
        "launchServicesMatchesDirect": True,
        "multiFileArtifactMatchesDirect": True,
        **direct_semantic,
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
