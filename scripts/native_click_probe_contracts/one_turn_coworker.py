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
    17: {
        "toolName": "host.shell.run",
        "artifactSuffix": "archive-readme.md",
        "artifactContains": "Archive/2024-Q4/Acme-old.txt",
        "answerContains": "wrote archive-readme.md",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "Archive/2024-Q4/Acme-old.txt",
                "artifactContains": "Acme contract",
            },
        ],
    },
    18: {
        "toolName": "host.shell.run",
        "artifactSuffix": "benefits-plan-matrix.csv",
        "artifactContains": "Silver,150,1000,4000,35,Tier 2",
        "answerContains": "wrote benefits-plan-matrix.csv",
    },
    19: {
        "toolName": "host.shell.run",
        "artifactSuffix": "marketing-budget-model.csv",
        "artifactContains": "quarter_rollup,Q1,all,24500,Q1",
        "answerContains": "wrote marketing-budget-model.csv",
    },
    20: {
        "toolName": "host.shell.run",
        "artifactSuffix": "regional-revenue-chart.png",
        "artifactContains": "PNG 320x200 stacked revenue chart",
        "answerContains": "wrote regional-revenue-chart.png",
    },
    21: {
        "toolName": "host.shell.run",
        "artifactSuffix": "cohort-retention.csv",
        "artifactContains": "2026-01,3,67%,2026-02",
        "answerContains": "wrote cohort-retention.csv",
    },
    22: {
        "toolName": "host.shell.run",
        "artifactSuffix": "collections-chase-emails.md",
        "artifactContains": "90-plus,urgent payment plan,INV-309",
        "answerContains": "wrote collections-chase-emails.md",
    },
    23: {
        "toolName": "host.shell.run",
        "artifactSuffix": "donors-split.csv",
        "artifactContains": "No city state zip,,,,true",
        "answerContains": "wrote donors-split.csv",
    },
    24: {
        "toolName": "host.shell.run",
        "artifactSuffix": "support-replies/ticket-001.md",
        "artifactContains": "billing-access-restored-today",
        "answerContains": "wrote support-replies/ticket-001.md and support-replies/ticket-002.md",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "support-replies/ticket-002.md",
                "artifactContains": "corrected-csv-attached",
            },
        ],
    },
    25: {
        "toolName": "host.shell.run",
        "artifactSuffix": "newsletter-clean.csv",
        "artifactContains": "+14155550100",
        "answerContains": "wrote newsletter-clean.csv and newsletter-bad-rows.csv",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "newsletter-bad-rows.csv",
                "artifactContains": "invalid-email,not-a-phone",
            },
        ],
    },
    26: {
        "toolName": "host.shell.run",
        "artifactSuffix": "members-normalized.csv",
        "artifactContains": "Cam,2026-07-14,text date",
        "answerContains": "wrote members-normalized.csv",
    },
    27: {
        "toolName": "host.file.write",
        "artifactSuffix": "delay-notice.md",
        "artifactContains": "your order is delayed until Friday",
        "answerContains": "Wrote `delay-notice.md`.",
    },
    28: {
        "toolName": "host.file.write",
        "artifactSuffix": "dependency-map.mmd",
        "artifactContains": "Engineering --> Launch",
        "answerContains": "Wrote `dependency-map.mmd`.",
    },
    29: {
        "toolName": "host.shell.run",
        "artifactSuffix": "exhibits/Exhibit-A-Purchase-Agreement.pdf",
        "artifactContains": "Exhibit A - Purchase Agreement",
        "answerContains": "wrote exhibits/Exhibit-A-Purchase-Agreement.pdf and exhibits/Exhibit-B-Disclosure-Schedule.pdf",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "exhibits/Exhibit-B-Disclosure-Schedule.pdf",
                "artifactContains": "Exhibit B - Disclosure Schedule",
            },
            {
                "artifactSuffix": "exhibits/exhibit-index.csv",
                "artifactContains": "B,Disclosure Schedule,Exhibit-B-Disclosure-Schedule.pdf",
            },
        ],
    },
    30: {
        "toolName": "host.shell.run",
        "artifactSuffix": "amex_q3-categorized.csv",
        "artifactContains": "2026-07-18,Adobe,79.99,Software,6100",
        "answerContains": "wrote amex_q3-categorized.csv and amex_q3-review.csv",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "amex_q3-review.csv",
                "artifactContains": "2026-07-22,Unknown Vendor,312.00,needs_review",
            },
        ],
    },
    31: {
        "toolName": "host.shell.run",
        "artifactSuffix": "june-variance-pack.csv",
        "artifactContains": "Support,42000,36500,15.1%,over,billing backlog temporary contractors",
        "answerContains": "wrote june-variance-pack.csv",
    },
    32: {
        "toolName": "host.shell.run",
        "artifactSuffix": "downloads-organization-report.md",
        "artifactContains": "Junk pile: Downloads/Junk/installer.tmp",
        "answerContains": "wrote downloads-organization-report.md",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "Downloads/Receipts/receipt-1042.pdf",
                "artifactContains": "Receipt 1042",
            },
            {
                "artifactSuffix": "Downloads/Screenshots/screenshot-launch.png",
                "artifactContains": "Screenshot launch",
            },
        ],
    },
    33: {
        "toolName": "host.shell.run",
        "artifactSuffix": "prospect-followups/ada-day-1.md",
        "artifactContains": "Great talking about the warehouse pilot",
        "answerContains": "wrote prospect-followups/ada-day-1.md, prospect-followups/ada-day-3.md, and prospect-followups/ada-day-7.md",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "prospect-followups/ada-day-3.md",
                "artifactContains": "bring the warehouse checklist",
            },
            {
                "artifactSuffix": "prospect-followups/ben-day-1.md",
                "artifactContains": "pricing analytics dashboard",
            },
        ],
    },
    34: {
        "toolName": "host.shell.run",
        "artifactSuffix": "forecast-review.md",
        "artifactContains": "Flag: Q3 Upside assumes 42 pct close rate",
        "answerContains": "wrote forecast-review.md",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "pipeline-forecast.xlsx",
                "artifactContains": "Q3 Upside,1200000,42 pct",
            },
        ],
    },
    35: {
        "toolName": "host.shell.run",
        "artifactSuffix": "q2-funnel-summary.md",
        "artifactContains": "Biggest drop-off: Demo to Proposal",
        "answerContains": "wrote q2-funnel-summary.md",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "q2-funnel-conversions.csv",
                "artifactContains": "Demo to Proposal,40 pct,14",
            },
        ],
    },
    36: {
        "toolName": "host.shell.run",
        "artifactSuffix": "vendor-name-mapping.csv",
        "artifactContains": "ACME, Inc.,Acme",
        "answerContains": "wrote vendor-name-mapping.csv and ap-vendors-standardized.csv",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "ap-vendors-standardized.csv",
                "artifactContains": "Acme,3,merged",
            },
        ],
    },
    37: {
        "toolName": "host.shell.run",
        "artifactSuffix": "senior-csm-job-description.md",
        "artifactContains": "Senior Customer Success Manager",
        "answerContains": "wrote senior-csm-job-description.md",
        "secondaryArtifacts": [
            {
                "artifactSuffix": "senior-csm-screening-questions.md",
                "artifactContains": "at-risk account",
            },
        ],
    },
    40: {
        "toolName": "host.shell.run",
        "artifactSuffix": "finance-kpi-dashboard.html",
        "artifactContains": "Finance KPI Dashboard",
        "answerContains": "wrote finance-kpi-dashboard.html",
    },
    43: {
        "toolName": "host.shell.run",
        "artifactSuffix": "q3-content-calendar.csv",
        "artifactContains": "2026-Q3-W01,Migration,webinar,Modernize legacy data,Ben",
        "answerContains": "wrote q3-content-calendar.csv",
    },
    48: {
        "toolName": "host.shell.run",
        "artifactSuffix": "sales-pivot-summary.csv",
        "artifactContains": "top_deal,Ada,West,Q2,92000",
        "answerContains": "wrote sales-pivot-summary.csv",
    },
    52: {
        "toolName": "host.shell.run",
        "artifactSuffix": "release-notes-2026-08.md",
        "artifactContains": "## Collaboration",
        "answerContains": "wrote release-notes-2026-08.md",
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
        expected_secondary = expected.get("secondaryArtifacts", [])
        secondary_artifacts = case.get("secondaryArtifacts", [])
        require(
            isinstance(secondary_artifacts, list),
            f"{label} task {task_id} secondary artifacts were malformed: {secondary_artifacts!r}",
        )
        require(
            len(secondary_artifacts) == len(expected_secondary),
            f"{label} task {task_id} secondary artifact count was {len(secondary_artifacts)}, "
            f"expected {len(expected_secondary)}",
        )
        for index, expected_artifact in enumerate(expected_secondary):
            artifact = secondary_artifacts[index]
            require(isinstance(artifact, dict), f"{label} task {task_id} secondary artifact {index} was malformed")
            artifact_path = artifact.get("artifactPath")
            require(
                isinstance(artifact_path, str) and artifact_path.endswith(expected_artifact["artifactSuffix"]),
                f"{label} task {task_id} secondary artifact {index} path was malformed: {artifact_path!r}",
            )
            require(
                artifact.get("artifactContains") == expected_artifact["artifactContains"],
                f"{label} task {task_id} secondary artifact {index} assertion was "
                f"{artifact.get('artifactContains')!r}",
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
        "secondaryArtifacts": [
            [
                {
                    "artifactSuffix": expected_artifact["artifactSuffix"],
                    "artifactContains": artifact["artifactContains"],
                }
                for artifact, expected_artifact in zip(
                    case.get("secondaryArtifacts", []),
                    EXPECTED_CASES[case["taskID"]].get("secondaryArtifacts", []),
                )
            ]
            for case in cases
        ],
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
