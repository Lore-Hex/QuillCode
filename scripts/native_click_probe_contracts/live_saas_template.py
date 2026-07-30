"""Write a row-linked live SaaS evidence template for manual coworker validation."""

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


def build_live_saas_template(
    catalog_task_ids: list[int],
    *,
    service_name: str | None = None,
    task_name: str | None = None,
    url: str | None = None,
) -> dict[str, Any]:
    validated_task_ids = require_catalog_task_ids(catalog_task_ids)
    return {
        "ok": True,
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "catalogTaskIDs": validated_task_ids,
        "serviceName": _optional_string(service_name, "TODO: SaaS service name, for example Salesforce"),
        "taskName": _optional_string(task_name, "TODO: exact coworker task proven by this capture"),
        "url": _optional_string(url, "https://TODO.example.com/path/to/signed-in/task"),
        "accountState": "signed-in",
        "toolSequence": [
            "host.browser.open",
            "host.browser.inspect",
            "host.browser.type",
            "host.browser.click",
        ],
        "browser": {
            "inspectionDepth": "Live DOM snapshot",
            "signedInIndicator": "TODO: signed-in workspace/user/account text visible in capture",
            "beforeText": "TODO: relevant signed-in page text before QuillCode acts",
            "afterText": "TODO: relevant signed-in page text after QuillCode acts",
            "resultText": "TODO: saved/updated/downloaded result text visible after action",
            "actionSelector": "TODO: stable selector or accessibility target QuillCode acted on",
        },
        "computerUse": {
            "actions": [
                "host.computer.screenshot",
                "host.computer.click",
            ],
            "foregroundApplication": "TODO: foreground app name from screenshot evidence",
            "screenshotArtifactExists": True,
        },
        "captureChecklist": [
            "Replace every TODO before running scripts/live-saas-smoke.sh.",
            "Keep catalogTaskIDs limited to the exact spreadsheet rows this capture proves.",
            "Use an HTTPS signed-in SaaS URL.",
            "Include host.browser.open and host.browser.inspect plus at least one browser or Computer Use action.",
            "Make beforeText and afterText/resultText prove the user-visible state changed.",
            "Remove the computerUse object if this capture used browser tools only.",
            "Never paste passwords, API keys, session tokens, private keys, cookies, or raw auth headers.",
        ],
        "validationCommand": "scripts/live-saas-smoke.sh path/to/this-evidence.json path/to/live-saas-manifest.json",
    }


def write_live_saas_template(
    catalog_task_ids: list[int],
    output_path: Path,
    *,
    service_name: str | None = None,
    task_name: str | None = None,
    url: str | None = None,
) -> None:
    require(output_path.name.endswith(".json"), "live SaaS evidence template output must be a .json file")
    template = build_live_saas_template(
        catalog_task_ids,
        service_name=service_name,
        task_name=task_name,
        url=url,
    )
    with output_path.open("w", encoding="utf-8") as output_file:
        json.dump(template, output_file, indent=2, sort_keys=True)
        output_file.write("\n")
