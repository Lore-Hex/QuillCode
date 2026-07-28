"""Validate packaged multi-file artifact smoke evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, require
from .live_saas import CATALOG_SPREADSHEET_URL

EXPECTED_PROMPT = "Create the team action brief from `notes/research.md` and `notes/risks.md`."
EXPECTED_TOOL_SEQUENCE = ["host.file.read", "host.file.read", "host.file.write"]
EXPECTED_CATALOG_TASK_IDS = [69]
EXPECTED_ALL_HANDS_PROMPT = (
    "Draft the CEO all-hands email announcing the reorg from `org-changes.pptx` "
    "and the answers in `reorg-qa`, covering the eight hardest questions."
)
EXPECTED_ALL_HANDS_ASSERTIONS = {
    "announcesReorg",
    "preservesTimeline",
    "coversEightQuestions",
    "answersHardestQuestions",
}


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

    catalog_cases = smoke.get("catalogCases")
    require(isinstance(catalog_cases, list), f"{label} multi-file catalogCases must be a list")
    all_hands_cases = [
        case for case in catalog_cases
        if isinstance(case, dict) and case.get("taskID") == 69
    ]
    require(len(all_hands_cases) == 1, f"{label} multi-file catalogCases must include exactly one row #69 case")
    validate_all_hands_email_case(all_hands_cases[0], label)
    return smoke


def validate_all_hands_email_case(case: dict[str, Any], label: str) -> None:
    require(case.get("prompt") == EXPECTED_ALL_HANDS_PROMPT, f"{label} row #69 prompt drifted")
    require(
        case.get("toolSequence") == EXPECTED_TOOL_SEQUENCE,
        f"{label} row #69 tool sequence was {case.get('toolSequence')!r}",
    )
    source_paths = case.get("sourcePaths")
    require(
        isinstance(source_paths, list) and len(source_paths) == 2,
        f"{label} row #69 sourcePaths was malformed: {source_paths!r}",
    )
    for expected_suffix in ("org-changes.pptx", "reorg-qa/hardest-questions.md"):
        require(
            any(isinstance(path, str) and path.endswith(expected_suffix) for path in source_paths),
            f"{label} row #69 missed {expected_suffix}: {source_paths!r}",
        )
    deliverable_path = case.get("deliverablePath")
    require(
        isinstance(deliverable_path, str) and deliverable_path.endswith("ceo-reorg-all-hands-email.md"),
        f"{label} row #69 deliverable path was malformed: {deliverable_path!r}",
    )
    final_answer = case.get("finalAnswer")
    require(
        isinstance(final_answer, str) and "Created `ceo-reorg-all-hands-email.md`" in final_answer,
        f"{label} row #69 final answer was malformed: {final_answer!r}",
    )
    assertions = case.get("assertions")
    require(isinstance(assertions, dict), f"{label} row #69 assertions must be an object")
    missing = sorted(name for name in EXPECTED_ALL_HANDS_ASSERTIONS if assertions.get(name) is not True)
    require(not missing, f"{label} row #69 assertions were not all true: {missing}")


def semantic_multi_file_artifact(smoke: dict[str, Any]) -> dict[str, Any]:
    source_paths = smoke["sourcePaths"]
    catalog_cases = smoke["catalogCases"]
    all_hands_case = next(case for case in catalog_cases if case["taskID"] == 69)
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
        "catalogTaskIDs": [69],
        "catalogCases": [
            {
                "taskID": 69,
                "prompt": all_hands_case["prompt"],
                "toolSequence": all_hands_case["toolSequence"],
                "sourcePathSuffixes": sorted(
                    "org-changes.pptx"
                    if str(path).endswith("org-changes.pptx")
                    else "reorg-qa/hardest-questions.md"
                    for path in all_hands_case["sourcePaths"]
                ),
                "deliverablePathSuffix": "ceo-reorg-all-hands-email.md",
                "finalAnswer": all_hands_case["finalAnswer"],
                "assertions": all_hands_case["assertions"],
            }
        ],
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
        "packagedMultiFileArtifactValidated": True,
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "catalogTaskIDs": EXPECTED_CATALOG_TASK_IDS,
        "taskIDs": EXPECTED_CATALOG_TASK_IDS,
        "directReport": "direct-executable/report.json",
        "launchServicesReport": "launch-services/report.json",
        "launchServicesMatchesDirect": True,
        "multiFileArtifactMatchesDirect": True,
        **direct_semantic,
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
