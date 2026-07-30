"""Validate optional packaged native notification observation evidence."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .json_io import load_json_object, require, required_string
from .live_saas import CATALOG_SPREADSHEET_URL, require_catalog_task_ids

EXPECTED_TASK_TEXT = "check competitor pricing pages and notify me with a diff"
EXPECTED_TITLE = "QuillCode scheduled task ready"
EXPECTED_APP_NAME = "QuillCode"
EXPECTED_ACTION = "open-follow-up-thread"

RAW_FIELD_NAMES = {
    "prompt",
    "rawPrompt",
    "rawResponse",
    "messages",
    "recentMessages",
    "authorization",
    "cookie",
    "password",
    "token",
    "secret",
    "apiKey",
    "api_key",
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
            require(
                pattern.search(value) is None,
                f"{path} appears to contain a secret and must be redacted",
            )


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


def _validate_observation(evidence: dict[str, Any]) -> dict[str, Any]:
    _require_no_raw_or_secret(evidence)
    require(evidence.get("ok") is True, "notification observation evidence must set ok=true")

    packaged_manifest = evidence.get("packagedScheduledCoworkerManifest")
    require(
        isinstance(packaged_manifest, dict),
        "packagedScheduledCoworkerManifest must be present",
    )
    require(
        packaged_manifest.get("ok") is True
        and packaged_manifest.get("scheduledCoworkerMatchesDirect") is True
        and packaged_manifest.get("notificationCount") == 1
        and packaged_manifest.get("taskText") == EXPECTED_TASK_TEXT,
        "packagedScheduledCoworkerManifest must reference the validated scheduled coworker smoke",
    )

    captured_at = required_string(evidence.get("capturedAt"), "capturedAt")
    catalog_task_ids = require_catalog_task_ids(evidence.get("catalogTaskIDs"))
    app_name = required_string(evidence.get("appName"), "appName")
    observation_method = required_string(evidence.get("observationMethod"), "observationMethod")
    title = required_string(evidence.get("notificationTitle"), "notificationTitle")
    body = required_string(evidence.get("notificationBody"), "notificationBody")
    thread_title = required_string(evidence.get("followUpThreadTitle"), "followUpThreadTitle")
    action = required_string(evidence.get("activationAction"), "activationAction")
    screenshot_artifact = required_string(evidence.get("screenshotArtifact"), "screenshotArtifact")
    observed_elements = _required_string_list(evidence.get("observedElements"), "observedElements")

    require(app_name == EXPECTED_APP_NAME, f"appName must be {EXPECTED_APP_NAME!r}")
    require(title == EXPECTED_TITLE, f"notificationTitle must be {EXPECTED_TITLE!r}")
    require(EXPECTED_TASK_TEXT in body, "notificationBody must include the original scheduled task")
    require(
        thread_title == packaged_manifest.get("followUpThreadTitle"),
        "followUpThreadTitle must match the packaged scheduled coworker manifest",
    )
    require(action == EXPECTED_ACTION, f"activationAction must be {EXPECTED_ACTION!r}")
    require(
        observation_method in {"accessibility", "computer-use", "manual-screenshot"},
        "observationMethod must be accessibility, computer-use, or manual-screenshot",
    )
    require(
        screenshot_artifact.endswith((".png", ".jpg", ".jpeg", ".heic")),
        "screenshotArtifact must point to an image capture",
    )
    require(
        _required_bool(evidence.get("screenshotArtifactExists"), "screenshotArtifactExists"),
        "screenshotArtifactExists must be true",
    )
    require(
        _required_bool(evidence.get("notificationVisible"), "notificationVisible"),
        "notificationVisible must be true",
    )
    require(
        _required_bool(evidence.get("activationOpenedFollowUp"), "activationOpenedFollowUp"),
        "activationOpenedFollowUp must be true",
    )
    for required_element in (
        "QuillCode scheduled task ready",
        "check competitor pricing pages",
        "Open follow-up thread",
    ):
        require(
            any(required_element in element for element in observed_elements),
            f"observedElements must include {required_element!r}",
        )

    return {
        "capturedAt": captured_at,
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "catalogTaskIDs": catalog_task_ids,
        "appName": app_name,
        "observationMethod": observation_method,
        "notificationTitle": title,
        "notificationBodyContainsTask": True,
        "followUpThreadTitle": thread_title,
        "activationAction": action,
        "notificationVisible": True,
        "activationOpenedFollowUp": True,
        "screenshotArtifact": screenshot_artifact,
        "observedElements": observed_elements,
    }


def write_scheduled_notification_observation_manifest(
    evidence_path: Path,
    manifest_path: Path,
) -> None:
    observation = _validate_observation(
        load_json_object(evidence_path, "scheduled notification observation evidence")
    )
    manifest = {
        "ok": True,
        "scheduledNotificationObservationValidated": True,
        "evidencePath": str(evidence_path),
        **observation,
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
