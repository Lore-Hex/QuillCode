"""Validate packaged browser coworker workflow smoke evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, require

BROWSER_WORKFLOW_EXPECTATIONS = {
    "browserWorkflowSmoke": {
        "typedSelector": "input[name='status']",
        "typedText": "Qualified",
        "clickedSelector": "button[data-action='save']",
        "heading": "H1: CRM Workflow Smoke",
        "scriptState": "saved=true",
        "textState": "Saved",
        "previewPathSuffix": "browser-crm-smoke.html",
        "manifestPrefix": "crm",
    },
    "browserSpreadsheetWorkflowSmoke": {
        "typedSelector": "[data-cell='launch-date']",
        "typedText": "2026-09-15",
        "clickedSelector": "button[data-action='mark-done']",
        "heading": "H1: Shared Sheet Workflow Smoke",
        "scriptState": "done=true",
        "textState": "Done",
        "previewPathSuffix": "browser-sheet-smoke.html",
        "manifestPrefix": "spreadsheet",
    },
}

EXPECTED_TOOL_FIELDS = {
    "typeToolName": "host.browser.type",
    "clickToolName": "host.browser.click",
    "scriptToolName": "host.browser.script",
    "inspectToolName": "host.browser.inspect",
    "inspectionDepth": "Live DOM snapshot",
    "sourceLabel": "Local HTML",
}


def validated_browser_workflow(report: dict[str, Any], key: str, label: str) -> dict[str, Any]:
    smoke = report.get(key)
    require(isinstance(smoke, dict), f"{label} report is missing {key}")

    expected = BROWSER_WORKFLOW_EXPECTATIONS[key]
    for field, value in EXPECTED_TOOL_FIELDS.items():
        actual = smoke.get(field)
        require(actual == value, f"{label} {key} field {field} was {actual!r}, expected {value!r}")
    for field in ("typedSelector", "typedText", "clickedSelector"):
        actual = smoke.get(field)
        value = expected[field]
        require(actual == value, f"{label} {key} field {field} was {actual!r}, expected {value!r}")

    preview_path = smoke.get("previewPath")
    require(
        isinstance(preview_path, str) and preview_path.endswith(expected["previewPathSuffix"]),
        f"{label} {key} previewPath was malformed: {preview_path!r}",
    )
    url = smoke.get("url")
    require(
        isinstance(url, str) and url.endswith(expected["previewPathSuffix"]),
        f"{label} {key} url was malformed: {url!r}",
    )
    outline = smoke.get("outline")
    require(
        isinstance(outline, list) and expected["heading"] in outline,
        f"{label} {key} outline missed {expected['heading']!r}: {outline!r}",
    )
    script_value = smoke.get("scriptValue")
    require(
        isinstance(script_value, str)
        and expected["typedText"] in script_value
        and expected["scriptState"] in script_value,
        f"{label} {key} scriptValue did not prove the edited state: {script_value!r}",
    )
    text_snippet = smoke.get("textSnippet")
    require(
        isinstance(text_snippet, str)
        and expected["typedText"] in text_snippet
        and expected["textState"] in text_snippet,
        f"{label} {key} textSnippet did not prove the edited state: {text_snippet!r}",
    )
    return smoke


def semantic_browser_workflow(smoke: dict[str, Any], key: str) -> dict[str, Any]:
    expected = BROWSER_WORKFLOW_EXPECTATIONS[key]
    return {
        "previewPathSuffix": expected["previewPathSuffix"],
        "urlSuffix": expected["previewPathSuffix"],
        "typedSelector": smoke["typedSelector"],
        "typedText": smoke["typedText"],
        "clickedSelector": smoke["clickedSelector"],
        "typeToolName": smoke["typeToolName"],
        "clickToolName": smoke["clickToolName"],
        "scriptToolName": smoke["scriptToolName"],
        "inspectToolName": smoke["inspectToolName"],
        "scriptValue": smoke["scriptValue"],
        "inspectionDepth": smoke["inspectionDepth"],
        "sourceLabel": smoke["sourceLabel"],
        "heading": expected["heading"],
        "textState": expected["textState"],
    }


def write_browser_workflow_manifest(
    direct_report_path: Path,
    launch_services_report_path: Path,
    manifest_path: Path,
) -> None:
    direct_report = load_report(direct_report_path)
    launch_services_report = load_report(launch_services_report_path)

    manifest: dict[str, Any] = {
        "ok": True,
        "directReport": "direct-executable/report.json",
        "launchServicesReport": "launch-services/report.json",
        "launchServicesMatchesDirect": True,
        "browserWorkflowMatchesDirect": True,
    }
    for key, expected in BROWSER_WORKFLOW_EXPECTATIONS.items():
        direct = validated_browser_workflow(direct_report, key, "direct executable")
        launch_services = validated_browser_workflow(launch_services_report, key, "Launch Services")
        direct_semantic = semantic_browser_workflow(direct, key)
        launch_services_semantic = semantic_browser_workflow(launch_services, key)
        require(
            direct_semantic == launch_services_semantic,
            f"Packaged app Launch Services {key} drifted from direct executable smoke",
        )
        prefix = expected["manifestPrefix"]
        for field, value in direct_semantic.items():
            manifest[f"{prefix}{field[0].upper()}{field[1:]}"] = value

    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
