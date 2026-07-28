"""Validate packaged one-turn office coworker smoke evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, require
from .live_saas import CATALOG_SPREADSHEET_URL

EXPECTED_CASES = {
    15: {
        "toolName": "host.file.write",
        "artifactSuffix": "launch-announcement.md",
        "artifactContains": "Billing portal launch email ready.",
        "answerContains": "Wrote `launch-announcement.md`.",
    },
    16: {
        "toolName": "host.shell.run",
        "artifactSuffix": "signup-slice.csv",
        "artifactContains": "organic,31",
        "answerContains": "wrote signup-slice.csv",
    },
    20: {
        "toolName": "host.shell.run",
        "artifactSuffix": "regional-revenue-chart.png",
        "artifactContains": "PNG 320x200 stacked revenue chart",
        "answerContains": "wrote regional-revenue-chart.png",
    },
    28: {
        "toolName": "host.file.write",
        "artifactSuffix": "dependency-map.mmd",
        "artifactContains": "Engineering --> Launch",
        "answerContains": "Wrote `dependency-map.mmd`.",
    },
    68: {
        "toolName": "host.shell.run",
        "artifactSuffix": "weekly-review.csv",
        "artifactContains": "Launch,3,2",
        "answerContains": "wrote weekly-review.csv",
    },
}


def validated_one_turn_coworker(report: dict[str, Any], label: str) -> dict[str, Any]:
    smoke = report.get("oneTurnCoworkerSmoke")
    require(isinstance(smoke, dict), f"{label} report is missing oneTurnCoworkerSmoke")

    cases = smoke.get("cases")
    require(isinstance(cases, list), f"{label} one-turn coworker cases were malformed")
    by_id = {
        case.get("taskID"): case
        for case in cases
        if isinstance(case, dict) and isinstance(case.get("taskID"), int)
    }
    require(
        set(by_id) == set(EXPECTED_CASES),
        f"{label} one-turn coworker task IDs were {sorted(by_id)}, expected {sorted(EXPECTED_CASES)}",
    )

    for task_id, expected in EXPECTED_CASES.items():
        case = by_id[task_id]
        require(
            case.get("toolName") == expected["toolName"],
            f"{label} task {task_id} tool was {case.get('toolName')!r}",
        )
        artifact_path = case.get("artifactPath")
        require(
            isinstance(artifact_path, str) and artifact_path.endswith(expected["artifactSuffix"]),
            f"{label} task {task_id} artifact path was malformed: {artifact_path!r}",
        )
        require(
            case.get("artifactContains") == expected["artifactContains"],
            f"{label} task {task_id} artifact assertion was {case.get('artifactContains')!r}",
        )
        final_answer = case.get("finalAnswer")
        require(
            isinstance(final_answer, str) and expected["answerContains"] in final_answer,
            f"{label} task {task_id} final answer was malformed: {final_answer!r}",
        )

    return smoke


def semantic_one_turn_coworker(smoke: dict[str, Any]) -> dict[str, Any]:
    cases = sorted(smoke["cases"], key=lambda case: case["taskID"])
    return {
        "taskIDs": [case["taskID"] for case in cases],
        "toolSequence": [case["toolName"] for case in cases],
        "artifactPathSuffixes": [
            EXPECTED_CASES[case["taskID"]]["artifactSuffix"]
            for case in cases
        ],
        "artifactContains": [case["artifactContains"] for case in cases],
        "finalAnswers": [case["finalAnswer"] for case in cases],
    }


def write_one_turn_coworker_manifest(
    direct_report_path: Path,
    launch_services_report_path: Path,
    manifest_path: Path,
) -> None:
    direct = validated_one_turn_coworker(load_report(direct_report_path), "direct executable")
    launch_services = validated_one_turn_coworker(
        load_report(launch_services_report_path),
        "Launch Services",
    )
    direct_semantic = semantic_one_turn_coworker(direct)
    launch_services_semantic = semantic_one_turn_coworker(launch_services)
    require(
        direct_semantic == launch_services_semantic,
        "Packaged app Launch Services one-turn coworker smoke drifted from direct executable smoke",
    )

    manifest = {
        "ok": True,
        "packagedOneTurnCoworkerValidated": True,
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "catalogTaskIDs": direct_semantic["taskIDs"],
        "directReport": "direct-executable/report.json",
        "launchServicesReport": "launch-services/report.json",
        "launchServicesMatchesDirect": True,
        "oneTurnCoworkerMatchesDirect": True,
        **direct_semantic,
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
