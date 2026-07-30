"""Validate optional live signed-in SaaS coworker evidence.

This validator is intentionally separate from deterministic packaged smoke. CI should not depend on
third-party accounts, but when a reviewer has a signed-in SaaS session they can capture evidence in
the same release-artifact style and fail closed if the evidence is too weak.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from .json_io import load_report, require

SECRET_PATTERNS = [
    re.compile(r"sk-(?:tr|qc)-v1-[A-Za-z0-9_-]+"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\b(password|secret|token|api[_-]?key)\s*[:=]\s*\S+"),
]

REQUIRED_BROWSER_TOOLS = {
    "host.browser.open",
    "host.browser.inspect",
}
ACTION_BROWSER_TOOLS = {
    "host.browser.click",
    "host.browser.type",
    "host.browser.script",
}
COMPUTER_USE_TOOLS = {
    "host.computer.screenshot",
    "host.computer.click",
    "host.computer.type",
    "host.computer.scroll",
    "host.computer.move",
    "host.computer.key",
}
CATALOG_SPREADSHEET_URL = (
    "https://docs.google.com/spreadsheets/d/"
    "1uq8uYGwoAxdwPcVn11nysjoozZjKY4acYZNVw-Hu5LM/edit?gid=0#gid=0"
)
CATALOG_TASK_ID_MIN = 1
CATALOG_TASK_ID_MAX = 206


def _require_string(value: Any, label: str, *, min_length: int = 1) -> str:
    require(isinstance(value, str) and len(value.strip()) >= min_length, f"{label} must be a non-empty string")
    return value.strip()


def _require_string_list(value: Any, label: str) -> list[str]:
    require(isinstance(value, list), f"{label} must be a list")
    strings = []
    for item in value:
        strings.append(_require_string(item, label))
    require(strings, f"{label} must not be empty")
    return strings


def require_catalog_task_ids(value: Any) -> list[int]:
    require(isinstance(value, list), "catalogTaskIDs must be a non-empty list")
    task_ids: list[int] = []
    for index, item in enumerate(value):
        require(isinstance(item, int) and not isinstance(item, bool), f"catalogTaskIDs[{index}] must be an integer")
        require(
            CATALOG_TASK_ID_MIN <= item <= CATALOG_TASK_ID_MAX,
            f"catalogTaskIDs[{index}] must be between {CATALOG_TASK_ID_MIN} and {CATALOG_TASK_ID_MAX}",
        )
        task_ids.append(item)
    require(task_ids, "catalogTaskIDs must be a non-empty list")
    deduplicated = sorted(set(task_ids))
    require(len(deduplicated) == len(task_ids), "catalogTaskIDs must not contain duplicates")
    return task_ids


def _scan_for_secrets(value: Any, path: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            _scan_for_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _scan_for_secrets(child, f"{path}[{index}]")
    elif isinstance(value, str):
        for pattern in SECRET_PATTERNS:
            require(pattern.search(value) is None, f"live SaaS evidence appears to contain a secret at {path}")


def _validate_https_url(value: str, label: str) -> str:
    parsed = urlparse(value)
    require(parsed.scheme == "https", f"{label} must be an https URL")
    require(bool(parsed.netloc), f"{label} must include a host")
    return value


def _validated_browser_evidence(browser: Any) -> dict[str, Any]:
    require(isinstance(browser, dict), "browser evidence must be an object")
    inspection_depth = _require_string(browser.get("inspectionDepth"), "browser.inspectionDepth")
    require(inspection_depth == "Live DOM snapshot", "browser evidence must use Live DOM snapshot")
    signed_in_indicator = _require_string(browser.get("signedInIndicator"), "browser.signedInIndicator")
    before_text = _require_string(browser.get("beforeText"), "browser.beforeText")
    after_text = _require_string(browser.get("afterText"), "browser.afterText")
    result_text = _require_string(browser.get("resultText"), "browser.resultText")
    action_selector = _require_string(browser.get("actionSelector"), "browser.actionSelector")
    require(
        signed_in_indicator in before_text or signed_in_indicator in after_text or signed_in_indicator in result_text,
        "browser signed-in indicator must appear in captured page evidence",
    )
    require(before_text != after_text or result_text != before_text, "browser evidence must prove a changed result")
    return {
        "inspectionDepth": inspection_depth,
        "signedInIndicator": signed_in_indicator,
        "actionSelector": action_selector,
        "resultText": result_text,
    }


def _validated_computer_use_evidence(computer_use: Any) -> dict[str, Any] | None:
    if computer_use is None:
        return None
    require(isinstance(computer_use, dict), "computerUse evidence must be an object")
    actions = _require_string_list(computer_use.get("actions"), "computerUse.actions")
    require(
        all(action in COMPUTER_USE_TOOLS for action in actions),
        f"computerUse.actions contains non-Computer Use tools: {actions!r}",
    )
    require("host.computer.screenshot" in actions, "computerUse evidence must include host.computer.screenshot")
    require(
        computer_use.get("screenshotArtifactExists") is True,
        "computerUse evidence must prove the screenshot artifact exists",
    )
    foreground_application = _require_string(
        computer_use.get("foregroundApplication"),
        "computerUse.foregroundApplication",
    )
    return {
        "actions": actions,
        "foregroundApplication": foreground_application,
        "screenshotArtifactExists": True,
    }


def validated_live_saas_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    require(evidence.get("ok") is True, "live SaaS evidence ok must be true")
    _scan_for_secrets(evidence)

    catalog_task_ids = require_catalog_task_ids(evidence.get("catalogTaskIDs"))
    service_name = _require_string(evidence.get("serviceName"), "serviceName")
    task_name = _require_string(evidence.get("taskName"), "taskName")
    account_state = _require_string(evidence.get("accountState"), "accountState")
    require(account_state == "signed-in", "accountState must be signed-in")
    url = _validate_https_url(_require_string(evidence.get("url"), "url"), "url")
    tool_sequence = _require_string_list(evidence.get("toolSequence"), "toolSequence")
    tool_set = set(tool_sequence)
    require(
        REQUIRED_BROWSER_TOOLS.issubset(tool_set),
        f"toolSequence must include {sorted(REQUIRED_BROWSER_TOOLS)!r}",
    )
    require(
        bool(ACTION_BROWSER_TOOLS.intersection(tool_set) or COMPUTER_USE_TOOLS.intersection(tool_set)),
        "toolSequence must include at least one browser action or Computer Use action",
    )

    browser = _validated_browser_evidence(evidence.get("browser"))
    computer_use = _validated_computer_use_evidence(evidence.get("computerUse"))

    return {
        "serviceName": service_name,
        "taskName": task_name,
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "catalogTaskIDs": catalog_task_ids,
        "urlHost": urlparse(url).netloc,
        "accountState": account_state,
        "toolSequence": tool_sequence,
        "browserInspectionDepth": browser["inspectionDepth"],
        "browserSignedInIndicator": browser["signedInIndicator"],
        "browserActionSelector": browser["actionSelector"],
        "browserResultText": browser["resultText"],
        "computerUseActionCount": len(computer_use["actions"]) if computer_use else 0,
        "computerUseForegroundApplication": computer_use["foregroundApplication"] if computer_use else "",
    }


def write_live_saas_manifest(evidence_path: Path, manifest_path: Path) -> None:
    evidence = load_report(evidence_path)
    validated = validated_live_saas_evidence(evidence)
    manifest = {
        "ok": True,
        "liveSaaSValidated": True,
        "evidencePath": str(evidence_path),
        **validated,
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
