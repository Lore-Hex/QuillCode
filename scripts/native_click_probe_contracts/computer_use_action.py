"""Validate packaged Computer Use action smoke evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, require, string_list

EXPECTED_TOOLS = [
    "host.computer.screenshot",
    "host.computer.click",
    "host.computer.type",
    "host.computer.scroll",
    "host.computer.move",
    "host.computer.key",
]

EXPECTED_ACTIONS = [
    "screenshot",
    "leftClick:42,84",
    "type:QuillCode smoke",
    "scroll:0,-120",
    "move:64,96",
    "key:return",
]

EXPECTED_ARGUMENTS = [
    "{}",
    '{"x":42,"y":84}',
    '{"text":"QuillCode smoke"}',
    '{"dx":0,"dy":-120}',
    '{"x":64,"y":96}',
    '{"key":"return"}',
]


def _validated_action_smoke(report_path: Path, label: str) -> dict[str, Any]:
    report = load_report(report_path)
    smoke = report.get("computerUseActionSmoke")
    require(isinstance(smoke, dict), f"{label} report is missing computerUseActionSmoke")

    tool_sequence = string_list(smoke.get("toolSequence"), f"{label} computerUseActionSmoke.toolSequence")
    action_sequence = string_list(smoke.get("actionSequence"), f"{label} computerUseActionSmoke.actionSequence")
    argument_json = string_list(smoke.get("argumentJSON"), f"{label} computerUseActionSmoke.argumentJSON")
    output_summaries = string_list(smoke.get("outputSummaries"), f"{label} computerUseActionSmoke.outputSummaries")
    require(tool_sequence == EXPECTED_TOOLS, f"{label} Computer Use tool sequence drifted: {tool_sequence!r}")
    require(action_sequence == EXPECTED_ACTIONS, f"{label} Computer Use action sequence drifted: {action_sequence!r}")
    require(argument_json == EXPECTED_ARGUMENTS, f"{label} Computer Use arguments drifted: {argument_json!r}")
    require(
        len(output_summaries) == len(EXPECTED_TOOLS) and all(summary.strip() for summary in output_summaries),
        f"{label} Computer Use output summaries were incomplete: {output_summaries!r}",
    )
    require(
        smoke.get("screenshotArtifactExists") is True,
        f"{label} Computer Use smoke did not prove screenshot artifact creation",
    )
    screenshot_path = smoke.get("screenshotPath")
    require(
        isinstance(screenshot_path, str) and screenshot_path.endswith(".png"),
        f"{label} Computer Use screenshot path was malformed: {screenshot_path!r}",
    )
    foreground_application = smoke.get("foregroundApplication")
    require(
        foreground_application == "QuillCode Smoke Target",
        f"{label} Computer Use foreground app was {foreground_application!r}",
    )
    accessibility_summary = smoke.get("accessibilitySummary")
    require(
        isinstance(accessibility_summary, str)
        and "Window: QuillCode Smoke Target" in accessibility_summary
        and "TextField: Prompt (Ready)" in accessibility_summary,
        f"{label} Computer Use accessibility summary was incomplete: {accessibility_summary!r}",
    )
    return {
        "toolSequence": tool_sequence,
        "actionSequence": action_sequence,
        "argumentJSON": argument_json,
        "outputSummaries": output_summaries,
        "screenshotPath": screenshot_path,
        "foregroundApplication": foreground_application,
        "accessibilitySummary": accessibility_summary,
    }


def write_computer_use_action_manifest(
    direct_report_path: Path,
    launch_services_report_path: Path,
    manifest_path: Path,
) -> None:
    direct = _validated_action_smoke(direct_report_path, "direct executable")
    launch_services = _validated_action_smoke(launch_services_report_path, "Launch Services")
    direct_semantic = {key: value for key, value in direct.items() if key != "screenshotPath"}
    launch_services_semantic = {
        key: value for key, value in launch_services.items() if key != "screenshotPath"
    }
    require(
        direct_semantic == launch_services_semantic,
        "Packaged app Launch Services Computer Use action smoke drifted from direct executable smoke",
    )

    manifest = {
        "ok": True,
        "directReport": "direct-executable/report.json",
        "launchServicesReport": "launch-services/report.json",
        "computerUseActionMatchesDirect": True,
        "directScreenshotPath": direct["screenshotPath"],
        "launchServicesScreenshotPath": launch_services["screenshotPath"],
        **direct_semantic,
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
