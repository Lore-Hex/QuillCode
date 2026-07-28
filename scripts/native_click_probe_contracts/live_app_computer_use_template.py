"""Write a row-linked local-app Computer Use evidence template."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import require
from .live_saas import CATALOG_SPREADSHEET_URL, require_catalog_task_ids


def _optional_string(value: str | None, fallback: str) -> str:
    if value is None or not value.strip():
        return fallback
    return value.strip()


def build_live_app_computer_use_template(
    catalog_task_ids: list[int],
    *,
    app_name: str | None = None,
    task_name: str | None = None,
) -> dict[str, Any]:
    validated_task_ids = require_catalog_task_ids(catalog_task_ids)
    resolved_app_name = _optional_string(app_name, "TODO: foreground local app name, for example Numbers")
    return {
        "ok": True,
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "catalogTaskIDs": validated_task_ids,
        "appName": resolved_app_name,
        "taskName": _optional_string(task_name, "TODO: exact coworker task proven by this capture"),
        "foregroundApplication": resolved_app_name,
        "taskCompleted": True,
        "toolSequence": [
            "host.computer.screenshot",
            "host.computer.click",
            "host.computer.type",
        ],
        "beforeStateEvidence": "TODO: visible app state before QuillCode acts",
        "afterStateEvidence": "TODO: visible app state after QuillCode acts",
        "resultStateEvidence": "TODO: completed result text/state visible after action",
        "screenshotArtifact": "TODO: relative/path/to/screenshot-or-appshot.png",
        "screenshotArtifactExists": True,
        "observedElements": [
            resolved_app_name,
            "TODO: before visible element",
            "TODO: completed result visible element",
        ],
        "captureChecklist": [
            "Replace every TODO before running scripts/live-app-computer-use-smoke.sh.",
            "Keep catalogTaskIDs limited to the exact spreadsheet rows this capture proves.",
            "Use a real foreground local app, not a mock page or browser-only capture.",
            "Include host.computer.screenshot and at least one click/type/scroll/move/key action.",
            "Make beforeStateEvidence and afterStateEvidence prove the visible app state changed.",
            "Ensure resultStateEvidence appears in afterStateEvidence or observedElements.",
            "Never paste passwords, API keys, session tokens, private keys, cookies, or raw auth headers.",
        ],
        "validationCommand": (
            "scripts/live-app-computer-use-smoke.sh "
            "path/to/this-evidence.json path/to/live-app-computer-use-manifest.json"
        ),
    }


def write_live_app_computer_use_template(
    catalog_task_ids: list[int],
    output_path: Path,
    *,
    app_name: str | None = None,
    task_name: str | None = None,
) -> None:
    require(output_path.name.endswith(".json"), "live app Computer Use evidence template output must be a .json file")
    template = build_live_app_computer_use_template(
        catalog_task_ids,
        app_name=app_name,
        task_name=task_name,
    )
    with output_path.open("w", encoding="utf-8") as output_file:
        json.dump(template, output_file, indent=2, sort_keys=True)
        output_file.write("\n")
