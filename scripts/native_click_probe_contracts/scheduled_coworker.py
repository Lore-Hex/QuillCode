"""Validate packaged scheduled-coworker smoke evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, require

EXPECTED_SCHEDULED_COWORKER = {
    "automationTitle": "Scheduled task: check competitor pricing pages and notify me with a diff",
    "taskText": "check competitor pricing pages and notify me with a diff",
    "scheduleDescription": "Every Monday at 8:00 AM",
    "reportTitle": "QuillCode scheduled task ready",
    "notificationCount": 1,
    "automationsVisible": True,
    "lastRunRecorded": True,
    "nextRunRecorded": True,
}

REQUIRED_PROMPT_SNIPPETS = (
    "Run the scheduled coworker task for ",
    "Task: check competitor pricing pages and notify me with a diff",
    "Report what changed, whether action is needed, and the next concrete step.",
)


def validated_scheduled_coworker(report: dict[str, Any], label: str) -> dict[str, Any]:
    smoke = report.get("scheduledCoworkerSmoke")
    require(isinstance(smoke, dict), f"{label} report is missing scheduledCoworkerSmoke")

    for field, expected in EXPECTED_SCHEDULED_COWORKER.items():
        actual = smoke.get(field)
        require(
            actual == expected,
            f"{label} scheduled coworker field {field} was {actual!r}, expected {expected!r}",
        )

    report_body = smoke.get("reportBody")
    require(
        isinstance(report_body, str) and EXPECTED_SCHEDULED_COWORKER["taskText"] in report_body,
        f"{label} scheduled coworker report body missed the original task: {report_body!r}",
    )

    thread_title = smoke.get("followUpThreadTitle")
    require(
        isinstance(thread_title, str) and thread_title.startswith("Scheduled check: "),
        f"{label} scheduled coworker follow-up thread title was malformed: {thread_title!r}",
    )

    follow_up_prompt = smoke.get("followUpPrompt")
    require(
        isinstance(follow_up_prompt, str),
        f"{label} scheduled coworker follow-up prompt was malformed",
    )
    for snippet in REQUIRED_PROMPT_SNIPPETS:
        require(
            snippet in follow_up_prompt,
            f"{label} scheduled coworker follow-up prompt missed {snippet!r}: {follow_up_prompt!r}",
        )

    return smoke


def write_scheduled_coworker_manifest(
    direct_report_path: Path,
    launch_services_report_path: Path,
    manifest_path: Path,
) -> None:
    direct = validated_scheduled_coworker(load_report(direct_report_path), "direct executable")
    launch_services = validated_scheduled_coworker(
        load_report(launch_services_report_path),
        "Launch Services",
    )
    require(
        direct == launch_services,
        "Packaged app Launch Services scheduled coworker smoke drifted from direct executable smoke",
    )

    manifest = {
        "ok": True,
        "directReport": "direct-executable/report.json",
        "launchServicesReport": "launch-services/report.json",
        "launchServicesMatchesDirect": True,
        "scheduledCoworkerMatchesDirect": True,
        "automationTitle": direct["automationTitle"],
        "taskText": direct["taskText"],
        "scheduleDescription": direct["scheduleDescription"],
        "reportTitle": direct["reportTitle"],
        "notificationCount": direct["notificationCount"],
        "automationsVisible": direct["automationsVisible"],
        "lastRunRecorded": direct["lastRunRecorded"],
        "nextRunRecorded": direct["nextRunRecorded"],
        "followUpThreadTitle": direct["followUpThreadTitle"],
        "requiredPromptSnippets": list(REQUIRED_PROMPT_SNIPPETS),
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
