"""Validate packaged macOS window reports and write packaged probe manifests."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .constants import (
    EXPECTED_SAMPLE_POINTS,
    MINIMUM_HIT_TARGET,
    MINIMUM_TARGET_CLEARANCE,
    MINIMUM_WINDOW_SCREENSHOT_BYTES,
    REQUIRED_WINDOW_COMMAND_IDS,
    REQUIRED_WINDOW_STARTER_ACTION_IDS,
)
from .json_io import load_json_object, load_report, relative_manifest_path, require
from .probe_contracts import normalized_probe_contracts, window_command_contract_ids

def validate_packaged_window_report(report_path: Path, screenshot_path: Path) -> None:
    report = load_report(report_path)
    require(report.get("ok") is True, f"{report_path} does not report ok=true")
    require(report.get("appName") == "QuillCode", f"{report_path} does not report the QuillCode app identity")
    require(report.get("windowTitle") == "QuillCode", f"{report_path} does not report the QuillCode window title")

    probe_contracts = normalized_probe_contracts(report, "packaged live-window")

    surface = report.get("surface")
    require(isinstance(surface, dict), f"{report_path} is missing workspace surface semantics")
    require(surface.get("appName") == "QuillCode", f"{report_path} surface appName is not QuillCode")
    require(isinstance(surface.get("primaryTitle"), str) and surface["primaryTitle"].strip(), f"{report_path} surface primaryTitle is empty")
    require(isinstance(surface.get("modelLabel"), str) and surface["modelLabel"].strip(), f"{report_path} surface modelLabel is empty")
    require(isinstance(surface.get("modeLabel"), str) and surface["modeLabel"].strip(), f"{report_path} surface modeLabel is empty")
    require(isinstance(surface.get("agentStatus"), str) and surface["agentStatus"].strip(), f"{report_path} surface agentStatus is empty")
    require(isinstance(surface.get("composerPlaceholder"), str) and surface["composerPlaceholder"].strip(), f"{report_path} surface composerPlaceholder is empty")
    require(surface.get("composerCanSend") is False, f"{report_path} does not prove the empty composer is disabled")
    require(surface.get("sidebarTitle") == "Chats", f"{report_path} does not prove the Chats sidebar is present")

    command_ids = surface.get("commandIDs")
    require(isinstance(command_ids, list), f"{report_path} surface commandIDs is not a list")
    command_ids = [value for value in command_ids if isinstance(value, str) and value.strip()]
    missing_commands = sorted(set(REQUIRED_WINDOW_COMMAND_IDS) - set(command_ids))
    require(not missing_commands, f"{report_path} surface is missing commands: {', '.join(missing_commands)}")
    command_contract_ids = window_command_contract_ids(command_ids)
    probed_contract_ids = {probe["contractID"] for probe in probe_contracts}
    missing_command_contracts = sorted(set(command_contract_ids) - probed_contract_ids)
    require(
        not missing_command_contracts,
        f"{report_path} native hit-target report is missing command contracts: "
        f"{', '.join(missing_command_contracts)}",
    )

    starter_action_ids = surface.get("starterActionIDs")
    require(isinstance(starter_action_ids, list), f"{report_path} surface starterActionIDs is not a list")
    missing_starter_actions = sorted(
        set(REQUIRED_WINDOW_STARTER_ACTION_IDS) - {value for value in starter_action_ids if isinstance(value, str)}
    )
    require(not missing_starter_actions, f"{report_path} surface is missing starter actions: {', '.join(missing_starter_actions)}")

    image = report.get("image")
    require(isinstance(image, dict), f"{report_path} does not include image diagnostics")
    width = image.get("width")
    height = image.get("height")
    distinct_color_buckets = image.get("distinctColorBuckets")
    require(isinstance(width, int) and width > 0, f"{report_path} image width is invalid: {width!r}")
    require(isinstance(height, int) and height > 0, f"{report_path} image height is invalid: {height!r}")
    require(
        isinstance(distinct_color_buckets, int) and distinct_color_buckets >= 10,
        f"{report_path} image distinctColorBuckets is suspicious: {distinct_color_buckets!r}",
    )

    require(screenshot_path.is_file(), f"packaged live-window screenshot is missing: {screenshot_path}")
    screenshot_bytes = screenshot_path.stat().st_size
    require(
        screenshot_bytes >= MINIMUM_WINDOW_SCREENSHOT_BYTES,
        f"packaged live-window screenshot is suspiciously small: {screenshot_bytes} bytes",
    )

def write_comparison_manifest(
    direct_report_path: Path,
    launch_services_report_path: Path,
    manifest_path: Path,
) -> None:
    direct_probe_contracts = normalized_probe_contracts(load_report(direct_report_path), "direct executable")
    launch_services_probe_contracts = normalized_probe_contracts(load_report(launch_services_report_path), "Launch Services")

    if direct_probe_contracts != launch_services_probe_contracts:
        direct_by_contract_id = {probe["contractID"]: probe for probe in direct_probe_contracts}
        launch_services_by_contract_id = {probe["contractID"]: probe for probe in launch_services_probe_contracts}
        direct_contract_ids = set(direct_by_contract_id)
        launch_services_contract_ids = set(launch_services_by_contract_id)
        missing_from_launch = sorted(direct_contract_ids - launch_services_contract_ids)
        missing_from_direct = sorted(launch_services_contract_ids - direct_contract_ids)
        drifting_contracts = sorted(
            contract_id
            for contract_id in direct_contract_ids & launch_services_contract_ids
            if direct_by_contract_id[contract_id] != launch_services_by_contract_id[contract_id]
        )
        raise SystemExit(
            "Packaged app Launch Services click probes drifted from direct executable probes "
            f"(missingFromLaunch={missing_from_launch}, missingFromDirect={missing_from_direct}, "
            f"driftingContracts={drifting_contracts})"
        )

    manifest = {
        "ok": True,
        "directReport": "direct-executable/report.json",
        "launchServicesReport": "launch-services/report.json",
        "launchServicesMatchesDirect": True,
        "clickProbeCount": len(direct_probe_contracts),
        "minimumTargetClearance": MINIMUM_TARGET_CLEARANCE,
        "contractIDs": [probe["contractID"] for probe in direct_probe_contracts],
        "clickProbePolicies": [
            {
                "contractID": probe["contractID"],
                "collisionScope": probe["collisionScope"],
                "allowsNestedInteractiveChildren": probe["allowsNestedInteractiveChildren"],
                "requiresUnblockedInterior": probe["requiresUnblockedInterior"],
                "requiresTactileFeedback": probe["requiresTactileFeedback"],
                "allowsTextSelection": probe["allowsTextSelection"],
                "requiredPeerClearance": probe["requiredPeerClearance"],
            }
            for probe in direct_probe_contracts
        ],
        "collisionScopes": sorted({probe["collisionScope"] for probe in direct_probe_contracts}),
        "samplePointNames": sorted({
            point["name"]
            for probe in direct_probe_contracts
            for point in probe["samplePoints"]
        }),
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")

def validated_comparison_manifest(path: Path) -> dict[str, Any]:
    manifest = load_json_object(path, "packaged click probe manifest")
    if manifest.get("ok") is not True:
        raise SystemExit(f"{path} does not record a passing packaged click-probe comparison")
    if manifest.get("launchServicesMatchesDirect") is not True:
        raise SystemExit(f"{path} does not prove Launch Services probes match direct executable probes")

    for key in ("directReport", "launchServicesReport"):
        if not isinstance(manifest.get(key), str) or not manifest[key].strip():
            raise SystemExit(f"{path} is missing {key}")
    if not isinstance(manifest.get("contractIDs"), list) or not all(isinstance(value, str) for value in manifest["contractIDs"]):
        raise SystemExit(f"{path} has malformed contractIDs")
    policies = manifest.get("clickProbePolicies")
    if not isinstance(policies, list) or len(policies) != len(manifest["contractIDs"]):
        raise SystemExit(f"{path} has malformed clickProbePolicies")
    for policy in policies:
        if not isinstance(policy, dict):
            raise SystemExit(f"{path} has a malformed click-probe policy entry: {policy!r}")
        if policy.get("contractID") not in manifest["contractIDs"]:
            raise SystemExit(f"{path} has a click-probe policy for an unknown contract: {policy!r}")
        if not isinstance(policy.get("allowsNestedInteractiveChildren"), bool):
            raise SystemExit(f"{path} has a malformed nested-child policy entry: {policy!r}")
        if not isinstance(policy.get("requiresUnblockedInterior"), bool):
            raise SystemExit(f"{path} has a malformed interior-blocking policy entry: {policy!r}")
        if not isinstance(policy.get("requiresTactileFeedback"), bool):
            raise SystemExit(f"{path} has a malformed tactile-feedback policy entry: {policy!r}")
        if not isinstance(policy.get("allowsTextSelection"), bool):
            raise SystemExit(f"{path} has a malformed text-selection policy entry: {policy!r}")
    if not isinstance(manifest.get("samplePointNames"), list) or sorted(manifest["samplePointNames"]) != sorted(EXPECTED_SAMPLE_POINTS):
        raise SystemExit(f"{path} does not list the required click-probe sample points")
    if manifest.get("clickProbeCount") != len(manifest["contractIDs"]):
        raise SystemExit(f"{path} clickProbeCount does not match contractIDs")
    if manifest.get("minimumTargetClearance") != MINIMUM_TARGET_CLEARANCE:
        raise SystemExit(f"{path} minimumTargetClearance drifted from {MINIMUM_TARGET_CLEARANCE}")
    return manifest

def write_accessibility_readiness_manifest(artifact_root: Path, manifest_path: Path) -> None:
    click_probe_manifest_path = artifact_root / "packaged-click-probes.json"
    packaged_manifest = validated_comparison_manifest(click_probe_manifest_path)

    direct_report_path = artifact_root / packaged_manifest["directReport"]
    launch_services_report_path = artifact_root / packaged_manifest["launchServicesReport"]
    direct_probe_contracts = normalized_probe_contracts(load_report(direct_report_path), "direct executable")
    launch_services_probe_contracts = normalized_probe_contracts(load_report(launch_services_report_path), "Launch Services")
    if direct_probe_contracts != launch_services_probe_contracts:
        raise SystemExit("Packaged readiness cannot proceed because Launch Services click probes drifted from direct executable probes")

    contract_ids = [probe["contractID"] for probe in direct_probe_contracts]
    if sorted(contract_ids) != sorted(packaged_manifest["contractIDs"]):
        raise SystemExit("Packaged readiness cannot proceed because packaged manifest contract IDs drift from report probes")

    readiness = {
        "ok": True,
        "stage": "report-ready-for-accessibility-frame-sampling",
        "artifactRoot": ".",
        "clickProbeManifest": "packaged-click-probes.json",
        "directReport": packaged_manifest["directReport"],
        "launchServicesReport": packaged_manifest["launchServicesReport"],
        "launchServicesMatchesDirect": True,
        "clickProbeCount": len(direct_probe_contracts),
        "contractIDs": contract_ids,
        "clickProbePolicies": packaged_manifest["clickProbePolicies"],
        "requiredSamplePointNames": sorted(EXPECTED_SAMPLE_POINTS),
        "minimumHitTarget": MINIMUM_HIT_TARGET,
        "minimumTargetClearance": MINIMUM_TARGET_CLEARANCE,
        "liveAccessibilitySampling": "not-run",
        "nextLayer": "resolve selectors to live packaged-window accessibility frames and click center plus interior samples",
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(readiness, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
