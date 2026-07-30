"""Validate optional live local-app Computer Use coworker evidence.

CI cannot depend on a user's signed-in desktop apps. This contract lets a reviewer
capture a real local-app task with QuillCode Computer Use and convert it into
row-linked coworker catalog evidence only when the before/after proof is strong.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .json_io import load_json_object, require, required_string
from .live_saas import CATALOG_SPREADSHEET_URL, require_catalog_task_ids

COMPUTER_USE_TOOLS = {
    "host.computer.screenshot",
    "host.computer.click",
    "host.computer.type",
    "host.computer.scroll",
    "host.computer.move",
    "host.computer.key",
}
ACTION_TOOLS = COMPUTER_USE_TOOLS.difference({"host.computer.screenshot"})

RAW_FIELD_NAMES = {
    "authorization",
    "cookie",
    "password",
    "token",
    "secret",
    "apiKey",
    "api_key",
    "rawPrompt",
    "rawResponse",
    "messages",
    "recentMessages",
}

SECRET_PATTERNS = (
    re.compile(r"sk-(?:tr|qc)-v1-[A-Za-z0-9_-]{8,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\b(?:password|secret|token|api[_-]?key|authorization|cookie)\s*[:=]\s*\S+"),
)


def _require_no_raw_or_secret(value: Any, path: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            require(
                key not in RAW_FIELD_NAMES,
                f"{path}.{key} is a raw or secret-bearing field and must not be captured",
            )
            _require_no_raw_or_secret(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _require_no_raw_or_secret(child, f"{path}[{index}]")
    elif isinstance(value, str):
        for pattern in SECRET_PATTERNS:
            require(pattern.search(value) is None, f"{path} appears to contain a secret and must be redacted")


def _required_bool(value: Any, label: str) -> bool:
    require(isinstance(value, bool), f"{label} must be a boolean")
    return bool(value)


def _required_string_list(value: Any, label: str) -> list[str]:
    require(isinstance(value, list), f"{label} must be a list")
    strings: list[str] = []
    for index, item in enumerate(value):
        strings.append(required_string(item, f"{label}[{index}]"))
    require(strings, f"{label} must not be empty")
    return strings


def _validated_action_sequence(value: Any) -> list[str]:
    actions = _required_string_list(value, "toolSequence")
    unknown = [action for action in actions if action not in COMPUTER_USE_TOOLS]
    require(not unknown, f"toolSequence contains non-Computer Use tools: {unknown!r}")
    require("host.computer.screenshot" in actions, "toolSequence must include host.computer.screenshot")
    require(
        bool(ACTION_TOOLS.intersection(actions)),
        "toolSequence must include at least one Computer Use action after screenshot",
    )
    return actions


def _validated_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    _require_no_raw_or_secret(evidence)
    require(evidence.get("ok") is True, "live app Computer Use evidence must set ok=true")

    catalog_task_ids = require_catalog_task_ids(evidence.get("catalogTaskIDs"))
    app_name = required_string(evidence.get("appName"), "appName")
    task_name = required_string(evidence.get("taskName"), "taskName")
    foreground_application = required_string(
        evidence.get("foregroundApplication"),
        "foregroundApplication",
    )
    require(
        app_name == foreground_application,
        "appName must match foregroundApplication so the capture proves the acted-on app",
    )
    task_completed = _required_bool(evidence.get("taskCompleted"), "taskCompleted")
    require(task_completed, "taskCompleted must be true")
    tool_sequence = _validated_action_sequence(evidence.get("toolSequence"))
    before_state = required_string(evidence.get("beforeStateEvidence"), "beforeStateEvidence")
    after_state = required_string(evidence.get("afterStateEvidence"), "afterStateEvidence")
    result_state = required_string(evidence.get("resultStateEvidence"), "resultStateEvidence")
    screenshot_artifact = required_string(evidence.get("screenshotArtifact"), "screenshotArtifact")
    observed_elements = _required_string_list(evidence.get("observedElements"), "observedElements")

    require(before_state != after_state, "beforeStateEvidence and afterStateEvidence must prove a visible state change")
    require(
        result_state in after_state or after_state in result_state or result_state in " ".join(observed_elements),
        "resultStateEvidence must be visible in the after-state or observed elements",
    )
    require(
        screenshot_artifact.endswith((".png", ".jpg", ".jpeg", ".heic", ".appshot.json")),
        "screenshotArtifact must be an image capture or appshot",
    )
    require(
        _required_bool(evidence.get("screenshotArtifactExists"), "screenshotArtifactExists"),
        "screenshotArtifactExists must be true",
    )
    require(
        any(app_name in element or foreground_application in element for element in observed_elements),
        "observedElements must include the foreground app name",
    )
    require(
        any(result_state in element or element in result_state for element in observed_elements),
        "observedElements must include the completed result state",
    )

    return {
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "catalogTaskIDs": catalog_task_ids,
        "appName": app_name,
        "taskName": task_name,
        "foregroundApplication": foreground_application,
        "toolSequence": tool_sequence,
        "taskCompleted": True,
        "beforeStateEvidence": before_state,
        "afterStateEvidence": after_state,
        "resultStateEvidence": result_state,
        "screenshotArtifact": screenshot_artifact,
        "screenshotArtifactExists": True,
        "observedElements": observed_elements,
    }


def write_live_app_computer_use_manifest(evidence_path: Path, manifest_path: Path) -> None:
    evidence = _validated_evidence(load_json_object(evidence_path, "live app Computer Use evidence"))
    manifest = {
        "ok": True,
        "liveAppComputerUseValidated": True,
        "evidencePath": str(evidence_path),
        **evidence,
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
