"""Write a row-linked scheduled notification observation evidence template."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import require
from .live_saas import require_catalog_task_ids
from .scheduled_notification_observation import (
    EXPECTED_ACTION,
    EXPECTED_APP_NAME,
    EXPECTED_TASK_TEXT,
    EXPECTED_TITLE,
)


def build_scheduled_notification_observation_template(catalog_task_ids: list[int]) -> dict[str, Any]:
    validated_task_ids = require_catalog_task_ids(catalog_task_ids)
    return {
        "ok": True,
        "catalogTaskIDs": validated_task_ids,
        "capturedAt": "TODO: ISO-8601 capture timestamp",
        "appName": EXPECTED_APP_NAME,
        "observationMethod": "TODO: accessibility, computer-use, or manual-screenshot",
        "notificationTitle": EXPECTED_TITLE,
        "notificationBody": EXPECTED_TASK_TEXT,
        "notificationVisible": True,
        "activationAction": EXPECTED_ACTION,
        "activationOpenedFollowUp": True,
        "followUpThreadTitle": "TODO: exact Scheduled check: ... thread title opened by the notification",
        "screenshotArtifact": "TODO: path/to/scheduled-notification.png",
        "screenshotArtifactExists": True,
        "observedElements": [
            EXPECTED_TITLE,
            EXPECTED_TASK_TEXT,
            "Open follow-up thread",
            "TODO: additional visible native notification or opened-thread text",
        ],
        "packagedScheduledCoworkerManifest": {
            "ok": True,
            "scheduledCoworkerMatchesDirect": True,
            "notificationCount": 1,
            "taskText": EXPECTED_TASK_TEXT,
            "followUpThreadTitle": "TODO: same follow-up thread title as above",
        },
        "captureChecklist": [
            "Replace every TODO before running scripts/scheduled-notification-observation-smoke.sh.",
            "Keep catalogTaskIDs limited to the exact spreadsheet rows this notification observation proves.",
            "Use the packaged-scheduled-coworker.json manifest from the same release artifact set.",
            "Capture a real OS notification banner or notification-center item through Accessibility, Computer Use, or screenshot evidence.",
            "Prove the Open follow-up action opened the scheduled follow-up thread.",
            "Never paste passwords, API keys, session tokens, private keys, cookies, raw auth headers, raw prompts, or model responses.",
        ],
        "validationCommand": (
            "scripts/scheduled-notification-observation-smoke.sh "
            "path/to/this-evidence.json path/to/scheduled-notification-observation-manifest.json"
        ),
    }


def write_scheduled_notification_observation_template(
    catalog_task_ids: list[int],
    output_path: Path,
) -> None:
    require(
        output_path.name.endswith(".json"),
        "scheduled notification observation template output must be a .json file",
    )
    template = build_scheduled_notification_observation_template(catalog_task_ids)
    with output_path.open("w", encoding="utf-8") as output_file:
        json.dump(template, output_file, indent=2, sort_keys=True)
        output_file.write("\n")
