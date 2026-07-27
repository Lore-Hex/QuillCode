"""Validate packaged Computer Use release evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, relative_manifest_path, require, string_list
from .probe_contracts import window_command_contract_ids

COMPUTER_USE_COMMAND_IDS = [
    "computer-use-setup",
    "computer-use-open-screen-recording",
    "computer-use-open-accessibility",
    "computer-use-refresh",
]


def _validated_computer_use_chrome(report_path: Path, label: str) -> dict[str, Any]:
    report = load_report(report_path)
    chrome = report.get("chrome")
    require(isinstance(chrome, dict), f"{label} report is missing chrome")
    label_text = chrome.get("computerUseLabel")
    require(
        isinstance(label_text, str) and label_text.strip(),
        f"{label} report has empty Computer Use top-bar label",
    )
    known_fragments = ("Computer Use", "Screen Recording", "Accessibility")
    require(
        any(fragment in label_text for fragment in known_fragments),
        f"{label} report has unrecognized Computer Use top-bar label: {label_text!r}",
    )
    return {"computerUseLabel": label_text}


def _validated_window_commands(report_path: Path) -> dict[str, Any]:
    report = load_report(report_path)
    surface = report.get("surface")
    require(isinstance(surface, dict), f"{report_path} is missing window surface")
    command_ids = string_list(surface.get("commandIDs"), f"{report_path} surface.commandIDs")
    missing = sorted(set(COMPUTER_USE_COMMAND_IDS) - set(command_ids))
    require(not missing, f"{report_path} surface missed Computer Use commands: {', '.join(missing)}")
    return {
        "windowSurfaceCommandIDs": command_ids,
        "computerUseCommandIDs": COMPUTER_USE_COMMAND_IDS,
    }


def _validated_click_contracts(manifest_path: Path) -> dict[str, Any]:
    manifest = load_report(manifest_path)
    contract_ids = string_list(manifest.get("contractIDs"), f"{manifest_path} contractIDs")
    required_contracts = window_command_contract_ids(COMPUTER_USE_COMMAND_IDS)
    missing = sorted(set(required_contracts) - set(contract_ids))
    require(
        not missing,
        f"{manifest_path} missed Computer Use command click contracts: {', '.join(missing)}",
    )
    return {
        "clickProbeManifest": manifest,
        "computerUseCommandContractIDs": required_contracts,
    }


def _validated_accessibility_frames(manifest_path: Path) -> dict[str, Any]:
    manifest = load_report(manifest_path)
    command_contract_ids = string_list(
        manifest.get("windowCommandContractIDs"),
        f"{manifest_path} windowCommandContractIDs",
    )
    required_contracts = window_command_contract_ids(COMPUTER_USE_COMMAND_IDS)
    missing = sorted(set(required_contracts) - set(command_contract_ids))
    require(
        not missing,
        f"{manifest_path} missed Computer Use command contracts: {', '.join(missing)}",
    )
    return {
        "accessibilityFramesManifest": manifest,
        "windowCommandContractCount": manifest.get("windowCommandContractCount"),
    }


def write_computer_use_manifest(
    direct_report_path: Path,
    launch_services_report_path: Path,
    window_report_path: Path,
    click_probe_manifest_path: Path,
    accessibility_frames_manifest_path: Path,
    manifest_path: Path,
) -> None:
    direct = _validated_computer_use_chrome(direct_report_path, "direct executable")
    launch_services = _validated_computer_use_chrome(launch_services_report_path, "Launch Services")
    window_commands = _validated_window_commands(window_report_path)
    click_contracts = _validated_click_contracts(click_probe_manifest_path)
    accessibility_frames = _validated_accessibility_frames(accessibility_frames_manifest_path)

    manifest_directory = manifest_path.parent
    manifest = {
        "ok": True,
        "directReport": relative_manifest_path(direct_report_path, manifest_directory),
        "launchServicesReport": relative_manifest_path(launch_services_report_path, manifest_directory),
        "windowReport": relative_manifest_path(window_report_path, manifest_directory),
        "clickProbeManifest": relative_manifest_path(click_probe_manifest_path, manifest_directory),
        "accessibilityFramesManifest": relative_manifest_path(
            accessibility_frames_manifest_path,
            manifest_directory,
        ),
        "launchServicesCommandContractsMatchDirect": True,
        "directComputerUseTopBarLabel": direct["computerUseLabel"],
        "launchServicesComputerUseTopBarLabel": launch_services["computerUseLabel"],
        "computerUseCommandIDs": window_commands["computerUseCommandIDs"],
        "computerUseCommandContractIDs": click_contracts["computerUseCommandContractIDs"],
        "windowCommandContractCount": accessibility_frames["windowCommandContractCount"],
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
