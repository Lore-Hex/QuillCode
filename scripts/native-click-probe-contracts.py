#!/usr/bin/env python3
"""Validate QuillCode native click-probe contracts emitted by smoke reports."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

MINIMUM_HIT_TARGET = 44
MINIMUM_TARGET_CLEARANCE = 8
MINIMUM_WINDOW_SCREENSHOT_BYTES = 4096
REQUIRED_WINDOW_COMMAND_IDS = [
    "new-chat",
    "command-palette",
    "keyboard-shortcuts",
    "settings",
    "toggle-terminal",
    "toggle-browser",
    "stop-all",
    "disconnect-all",
]
REQUIRED_WINDOW_STARTER_ACTION_IDS = [
    "review-changes",
    "run-tests",
    "explain-project",
]
REQUIRED_LIVE_ACCESSIBILITY_CONTRACT_IDS = [
    "command.new-chat",
    "command.search",
    "command.settings",
    "command.toggle-automations",
    "command.toggle-extensions",
    "composer.input",
    "composer.mode-picker",
    "composer.model-picker",
    "composer.send",
    "sidebar.tools-menu",
    "top-bar.overflow",
]
EXPECTED_SAMPLE_POINTS = {
    "center": (0.5, 0.5),
    "leading-edge": (0.08, 0.5),
    "leading-interior": (0.18, 0.5),
    "trailing-edge": (0.92, 0.5),
    "trailing-interior": (0.82, 0.5),
    "top-edge": (0.5, 0.08),
    "top-interior": (0.5, 0.18),
    "bottom-edge": (0.5, 0.92),
    "bottom-interior": (0.5, 0.82),
}


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as json_file:
        value = json.load(json_file)
    if not isinstance(value, dict):
        raise SystemExit(f"{label} at {path} did not contain a JSON object")
    return value


def load_report(path: Path) -> dict[str, Any]:
    return load_json_object(path, "native smoke report")


def native_targets(report: dict[str, Any], label: str) -> dict[str, Any]:
    targets = report.get("nativeHitTargets")
    if not isinstance(targets, dict):
        raise SystemExit(f"{label} report is missing nativeHitTargets")
    return targets


def expected_selector(contract: dict[str, Any], selector_kind: str) -> Any:
    if selector_kind == "test-id":
        return contract.get("testID")
    if selector_kind == "command-id":
        return contract.get("commandID")
    if selector_kind == "focus-target":
        return contract.get("focusTarget")
    raise SystemExit(f"unknown click probe selectorKind: {selector_kind}")


def normalize_sample_points(
    sample_points: Any,
    *,
    label: str,
    contract_id: str,
) -> list[dict[str, Any]]:
    if not isinstance(sample_points, list) or len(sample_points) < len(EXPECTED_SAMPLE_POINTS):
        raise SystemExit(f"{label} report has insufficient click probe sample points for {contract_id}")

    normalized: list[dict[str, Any]] = []
    sample_names: set[str] = set()
    for point in sample_points:
        if not isinstance(point, dict):
            raise SystemExit(f"{label} report has a malformed sample point for {contract_id}: {point!r}")
        name = point.get("name")
        x = point.get("x")
        y = point.get("y")
        if not isinstance(name, str) or not name:
            raise SystemExit(f"{label} report has an unnamed click probe point for {contract_id}: {point!r}")
        if not isinstance(x, (int, float)) or not isinstance(y, (int, float)) or not (0 < x < 1) or not (0 < y < 1):
            raise SystemExit(f"{label} report has an out-of-bounds click probe point for {contract_id}: {point!r}")

        expected_point = EXPECTED_SAMPLE_POINTS.get(name)
        if expected_point is None:
            raise SystemExit(f"{label} report has an unknown click probe point for {contract_id}: {point!r}")
        if not math.isclose(x, expected_point[0], rel_tol=0.0, abs_tol=1e-9) or not math.isclose(y, expected_point[1], rel_tol=0.0, abs_tol=1e-9):
            raise SystemExit(f"{label} report has unexpected click probe point coordinates for {contract_id}: {point!r}")

        sample_names.add(name)
        normalized.append({"name": name, "x": float(x), "y": float(y)})

    missing_samples = sorted(set(EXPECTED_SAMPLE_POINTS) - sample_names)
    if missing_samples:
        raise SystemExit(f"{label} report click probe for {contract_id} is missing samples: {', '.join(missing_samples)}")

    return sorted(normalized, key=lambda point: point["name"])


def normalized_probe_contracts(report: dict[str, Any], label: str) -> list[dict[str, Any]]:
    targets = native_targets(report, label)
    if targets.get("missingClickProbeContractIDs") != []:
        raise SystemExit(f"{label} report has missing click probes: {targets.get('missingClickProbeContractIDs')}")
    if targets.get("clickProbeValidationIssues") != []:
        raise SystemExit(f"{label} report has invalid click probes: {targets.get('clickProbeValidationIssues')}")

    surface_contracts = targets.get("surfaceContracts")
    if not isinstance(surface_contracts, list):
        raise SystemExit(f"{label} report is missing surfaceContracts")

    click_probes = targets.get("clickProbes")
    if not isinstance(click_probes, list) or not click_probes:
        raise SystemExit(f"{label} report is missing clickProbes")

    contracts_by_id: dict[str, dict[str, Any]] = {}
    for contract in surface_contracts:
        if isinstance(contract, dict):
            contract_id = contract.get("id")
            if isinstance(contract_id, str) and contract_id:
                contracts_by_id[contract_id] = contract

    normalized: list[dict[str, Any]] = []
    probes_by_contract: dict[str, dict[str, Any]] = {}
    for probe in click_probes:
        if not isinstance(probe, dict):
            raise SystemExit(f"{label} report has a malformed click probe: {probe!r}")

        contract_id = probe.get("contractID")
        selector_kind = probe.get("selectorKind")
        selector = probe.get("selector")
        collision_scope = probe.get("collisionScope")
        kind = probe.get("kind")
        action = probe.get("action")
        allows_nested_interactive_children = probe.get("allowsNestedInteractiveChildren")
        requires_unblocked_interior = probe.get("requiresUnblockedInterior")
        requires_tactile_feedback = probe.get("requiresTactileFeedback")
        allows_text_selection = probe.get("allowsTextSelection")
        required_min_width = probe.get("requiredMinWidth")
        required_min_height = probe.get("requiredMinHeight")
        required_peer_clearance = probe.get("requiredPeerClearance")
        if not all(isinstance(value, str) and value.strip() for value in (contract_id, selector_kind, selector, collision_scope, kind, action)):
            raise SystemExit(f"{label} report has an incomplete click probe identity: {probe!r}")
        if not isinstance(allows_nested_interactive_children, bool):
            raise SystemExit(f"{label} report has malformed click probe nested-child policy for {contract_id}: {probe!r}")
        if not isinstance(requires_unblocked_interior, bool):
            raise SystemExit(f"{label} report has malformed click probe interior-blocking policy for {contract_id}: {probe!r}")
        if not isinstance(requires_tactile_feedback, bool):
            raise SystemExit(f"{label} report has malformed click probe tactile-feedback policy for {contract_id}: {probe!r}")
        if not isinstance(allows_text_selection, bool):
            raise SystemExit(f"{label} report has malformed click probe text-selection policy for {contract_id}: {probe!r}")
        if contract_id in probes_by_contract:
            raise SystemExit(f"{label} report has a duplicate click probe for {contract_id}")
        probes_by_contract[contract_id] = probe

        contract = contracts_by_id.get(contract_id)
        if not contract:
            raise SystemExit(f"{label} report has a click probe for unknown contract {contract_id}")
        if expected_selector(contract, selector_kind) != selector:
            raise SystemExit(f"{label} report has click probe selector drift for {contract_id}: {probe!r}")
        if probe.get("kind") != contract.get("kind") or probe.get("action") != contract.get("action"):
            raise SystemExit(f"{label} report has click probe semantic drift for {contract_id}: {probe!r}")
        if collision_scope != contract.get("collisionScope"):
            raise SystemExit(f"{label} report has click probe collision-scope drift for {contract_id}: {probe!r}")
        if allows_nested_interactive_children != contract.get("allowsNestedInteractiveChildren"):
            raise SystemExit(f"{label} report has click probe nested-child policy drift for {contract_id}: {probe!r}")
        if requires_unblocked_interior != contract.get("requiresUnblockedInterior"):
            raise SystemExit(f"{label} report has click probe interior-blocking policy drift for {contract_id}: {probe!r}")
        if requires_tactile_feedback != contract.get("requiresTactileFeedback"):
            raise SystemExit(f"{label} report has click probe tactile-feedback policy drift for {contract_id}: {probe!r}")
        if allows_text_selection != contract.get("allowsTextSelection"):
            raise SystemExit(f"{label} report has click probe text-selection policy drift for {contract_id}: {probe!r}")
        if not isinstance(required_min_width, (int, float)) or required_min_width < MINIMUM_HIT_TARGET:
            raise SystemExit(f"{label} report has undersized click probe requiredMinWidth for {contract_id}: {probe!r}")
        if not isinstance(required_min_height, (int, float)) or required_min_height < MINIMUM_HIT_TARGET:
            raise SystemExit(f"{label} report has undersized click probe requiredMinHeight for {contract_id}: {probe!r}")
        if not isinstance(required_peer_clearance, (int, float)) or required_peer_clearance < MINIMUM_TARGET_CLEARANCE:
            raise SystemExit(f"{label} report has too little click probe requiredPeerClearance for {contract_id}: {probe!r}")

        normalized.append({
            "contractID": contract_id,
            "selectorKind": selector_kind,
            "selector": selector,
            "collisionScope": collision_scope,
            "kind": kind,
            "action": action,
            "allowsNestedInteractiveChildren": allows_nested_interactive_children,
            "requiresUnblockedInterior": requires_unblocked_interior,
            "requiresTactileFeedback": requires_tactile_feedback,
            "allowsTextSelection": allows_text_selection,
            "requiredMinWidth": float(required_min_width),
            "requiredMinHeight": float(required_min_height),
            "requiredPeerClearance": float(required_peer_clearance),
            "samplePoints": normalize_sample_points(probe.get("samplePoints"), label=label, contract_id=contract_id),
        })

    missing_probe_contracts = sorted(set(contracts_by_id) - set(probes_by_contract))
    if missing_probe_contracts:
        raise SystemExit(f"{label} report surface contracts are missing click probes: {', '.join(missing_probe_contracts)}")

    return sorted(normalized, key=lambda probe: probe["contractID"])


def validate_report(report_path: Path, label: str) -> None:
    normalized_probe_contracts(load_report(report_path), label)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


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


def window_command_contract_ids(command_ids: list[str]) -> list[str]:
    return sorted(f"command.{command_id}" for command_id in command_ids)


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


def relative_manifest_path(path: Path, base_directory: Path) -> str:
    try:
        return str(path.resolve().relative_to(base_directory.resolve()))
    except ValueError:
        return str(path)


def numeric_value(value: Any, label: str) -> float:
    if not isinstance(value, (int, float)):
        raise SystemExit(f"{label} is not numeric: {value!r}")
    return float(value)


def string_list(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise SystemExit(f"{label} is not a list of strings")
    return value


def required_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"{label} is not a nonempty string: {value!r}")
    return value


def validated_accessibility_sample_points(
    report_path: Path,
    contract_id: str,
    frame: dict[str, float],
    sample_points: Any,
    requires_unblocked_interior: bool,
) -> list[str]:
    if not isinstance(sample_points, list):
        raise SystemExit(f"{report_path} has malformed samplePoints for {contract_id}")

    points_by_name: dict[str, dict[str, Any]] = {}
    for point in sample_points:
        if not isinstance(point, dict):
            raise SystemExit(f"{report_path} has malformed sample point for {contract_id}: {point!r}")
        name = point.get("name")
        if not isinstance(name, str) or name in points_by_name:
            raise SystemExit(f"{report_path} has malformed or duplicate sample point for {contract_id}: {point!r}")
        points_by_name[name] = point

    missing_points = sorted(set(EXPECTED_SAMPLE_POINTS) - set(points_by_name))
    if missing_points:
        raise SystemExit(f"{report_path} Accessibility sample for {contract_id} is missing: {', '.join(missing_points)}")

    for name, normalized_point in EXPECTED_SAMPLE_POINTS.items():
        point = points_by_name[name]
        x = numeric_value(point.get("x"), f"{contract_id}.{name}.x")
        y = numeric_value(point.get("y"), f"{contract_id}.{name}.y")
        hit_test_available = point.get("hitTestAvailable")
        hit_test_error = point.get("hitTestError")
        hit_test_identifier = point.get("hitTestIdentifier")
        hit_test_role = point.get("hitTestRole")
        hit_test_label = point.get("hitTestLabel")
        hit_test_ancestor_identifiers = point.get("hitTestAncestorIdentifiers")
        hit_test_matches_target = point.get("hitTestMatchesTarget")
        if not isinstance(hit_test_available, bool):
            raise SystemExit(f"{report_path} Accessibility sample point is missing hitTestAvailable for {contract_id}.{name}")
        if not isinstance(hit_test_error, str):
            raise SystemExit(f"{report_path} Accessibility sample point is missing hitTestError for {contract_id}.{name}")
        if not isinstance(hit_test_identifier, str):
            raise SystemExit(f"{report_path} Accessibility sample point is missing hitTestIdentifier for {contract_id}.{name}")
        if not isinstance(hit_test_role, str):
            raise SystemExit(f"{report_path} Accessibility sample point is missing hitTestRole for {contract_id}.{name}")
        if not isinstance(hit_test_label, str):
            raise SystemExit(f"{report_path} Accessibility sample point is missing hitTestLabel for {contract_id}.{name}")
        if (
            not isinstance(hit_test_ancestor_identifiers, list)
            or not all(isinstance(value, str) for value in hit_test_ancestor_identifiers)
        ):
            raise SystemExit(
                f"{report_path} Accessibility sample point has malformed hitTestAncestorIdentifiers "
                f"for {contract_id}.{name}"
            )
        if not isinstance(hit_test_matches_target, bool):
            raise SystemExit(f"{report_path} Accessibility sample point is missing hitTestMatchesTarget for {contract_id}.{name}")
        if requires_unblocked_interior and hit_test_available and not hit_test_matches_target:
            raise SystemExit(
                f"{report_path} Accessibility sample point {contract_id}.{name} "
                f"hit {hit_test_identifier!r} instead of the target"
            )
        expected_x = frame["x"] + frame["width"] * normalized_point[0]
        expected_y = frame["y"] + frame["height"] * normalized_point[1]
        if not math.isclose(x, expected_x, rel_tol=0.0, abs_tol=1e-6) or not math.isclose(y, expected_y, rel_tol=0.0, abs_tol=1e-6):
            raise SystemExit(f"{report_path} Accessibility sample point drifted for {contract_id}.{name}")

    return sorted(points_by_name)


def validated_accessibility_frame_sample(
    report_path: Path,
    sample: Any,
) -> tuple[str, dict[str, Any]]:
    if not isinstance(sample, dict):
        raise SystemExit(f"{report_path} has a malformed Accessibility frame sample: {sample!r}")

    contract_id = required_string(sample.get("contractID"), "accessibility sample contractID")
    selector_kind = required_string(sample.get("selectorKind"), f"{contract_id}.selectorKind")
    selector = required_string(sample.get("selector"), f"{contract_id}.selector")
    collision_scope = required_string(sample.get("collisionScope"), f"{contract_id}.collisionScope")
    kind = required_string(sample.get("kind"), f"{contract_id}.kind")
    action = required_string(sample.get("action"), f"{contract_id}.action")
    resolved_identifier = required_string(sample.get("resolvedIdentifier"), f"{contract_id}.resolvedIdentifier")
    role = required_string(sample.get("role"), f"{contract_id}.role")
    label = required_string(sample.get("label"), f"{contract_id}.label")

    raw_frame = sample.get("frame")
    if not isinstance(raw_frame, dict):
        raise SystemExit(f"{report_path} has malformed frame for {contract_id}: {sample!r}")
    frame = {
        "x": numeric_value(raw_frame.get("x"), f"{contract_id}.frame.x"),
        "y": numeric_value(raw_frame.get("y"), f"{contract_id}.frame.y"),
        "width": numeric_value(raw_frame.get("width"), f"{contract_id}.frame.width"),
        "height": numeric_value(raw_frame.get("height"), f"{contract_id}.frame.height"),
    }
    required_min_width = numeric_value(sample.get("requiredMinWidth"), f"{contract_id}.requiredMinWidth")
    required_min_height = numeric_value(sample.get("requiredMinHeight"), f"{contract_id}.requiredMinHeight")
    required_peer_clearance = numeric_value(sample.get("requiredPeerClearance"), f"{contract_id}.requiredPeerClearance")
    allows_nested_interactive_children = sample.get("allowsNestedInteractiveChildren")
    requires_unblocked_interior = sample.get("requiresUnblockedInterior")
    requires_tactile_feedback = sample.get("requiresTactileFeedback")
    allows_text_selection = sample.get("allowsTextSelection")
    if not isinstance(allows_nested_interactive_children, bool):
        raise SystemExit(f"{report_path} has malformed allowsNestedInteractiveChildren for {contract_id}")
    if not isinstance(requires_unblocked_interior, bool):
        raise SystemExit(f"{report_path} has malformed requiresUnblockedInterior for {contract_id}")
    if not isinstance(requires_tactile_feedback, bool):
        raise SystemExit(f"{report_path} has malformed requiresTactileFeedback for {contract_id}")
    if not isinstance(allows_text_selection, bool):
        raise SystemExit(f"{report_path} has malformed allowsTextSelection for {contract_id}")
    if frame["width"] < required_min_width or frame["height"] < required_min_height:
        raise SystemExit(f"{report_path} has undersized Accessibility frame sample for {contract_id}")
    if required_peer_clearance < MINIMUM_TARGET_CLEARANCE:
        raise SystemExit(f"{report_path} has too little Accessibility peer clearance for {contract_id}")

    sample_point_names = validated_accessibility_sample_points(
        report_path,
        contract_id,
        frame,
        sample.get("samplePoints"),
        requires_unblocked_interior,
    )

    return contract_id, {
        "contractID": contract_id,
        "selectorKind": selector_kind,
        "selector": selector,
        "collisionScope": collision_scope,
        "kind": kind,
        "action": action,
        "resolvedIdentifier": resolved_identifier,
        "role": role,
        "label": label,
        "allowsNestedInteractiveChildren": allows_nested_interactive_children,
        "requiresUnblockedInterior": requires_unblocked_interior,
        "requiresTactileFeedback": requires_tactile_feedback,
        "allowsTextSelection": allows_text_selection,
        "requiredPeerClearance": required_peer_clearance,
        "frame": frame,
        "samplePointNames": sample_point_names,
    }


def accessibility_frame_spacing_issues(samples: list[dict[str, Any]]) -> list[str]:
    issues: list[str] = []
    samples_by_collision_scope: dict[str, list[dict[str, Any]]] = {}
    for sample in samples:
        samples_by_collision_scope.setdefault(sample["collisionScope"], []).append(sample)

    for collision_scope, scoped_samples in samples_by_collision_scope.items():
        for index, lhs in enumerate(scoped_samples):
            for rhs in scoped_samples[index + 1:]:
                if lhs["resolvedIdentifier"] == rhs["resolvedIdentifier"]:
                    continue
                lhs_frame = lhs["frame"]
                rhs_frame = rhs["frame"]
                overlap_width = min(lhs_frame["x"] + lhs_frame["width"], rhs_frame["x"] + rhs_frame["width"]) - max(lhs_frame["x"], rhs_frame["x"])
                overlap_height = min(lhs_frame["y"] + lhs_frame["height"], rhs_frame["y"] + rhs_frame["height"]) - max(lhs_frame["y"], rhs_frame["y"])
                if overlap_width > 1 and overlap_height > 1:
                    issues.append(
                        f"{lhs['contractID']} overlaps {rhs['contractID']} in {collision_scope} "
                        f"by {overlap_width:.1f}x{overlap_height:.1f}"
                    )
                    continue

                vertical_overlap = min(lhs_frame["y"] + lhs_frame["height"], rhs_frame["y"] + rhs_frame["height"]) - max(lhs_frame["y"], rhs_frame["y"])
                horizontal_overlap = min(lhs_frame["x"] + lhs_frame["width"], rhs_frame["x"] + rhs_frame["width"]) - max(lhs_frame["x"], rhs_frame["x"])
                horizontal_gap = max(lhs_frame["x"], rhs_frame["x"]) - min(lhs_frame["x"] + lhs_frame["width"], rhs_frame["x"] + rhs_frame["width"])
                vertical_gap = max(lhs_frame["y"], rhs_frame["y"]) - min(lhs_frame["y"] + lhs_frame["height"], rhs_frame["y"] + rhs_frame["height"])
                required_clearance = max(lhs["requiredPeerClearance"], rhs["requiredPeerClearance"])
                if (
                    vertical_overlap > 1
                    and horizontal_gap >= 0
                    and horizontal_gap < required_clearance
                    and not allows_tight_accessibility_clearance(lhs, rhs, axis="x")
                ):
                    issues.append(
                        f"{lhs['contractID']} and {rhs['contractID']} have only {horizontal_gap:.1f} "
                        f"horizontal clearance in {collision_scope}; expected {required_clearance:.1f}"
                    )
                if (
                    horizontal_overlap > 1
                    and vertical_gap >= 0
                    and vertical_gap < required_clearance
                    and not allows_tight_accessibility_clearance(lhs, rhs, axis="y")
                ):
                    issues.append(
                        f"{lhs['contractID']} and {rhs['contractID']} have only {vertical_gap:.1f} "
                        f"vertical clearance in {collision_scope}; expected {required_clearance:.1f}"
                    )
    return sorted(issues)


def allows_tight_accessibility_clearance(lhs: dict[str, Any], rhs: dict[str, Any], *, axis: str) -> bool:
    if lhs["kind"] == "segmentedControl" or rhs["kind"] == "segmentedControl":
        return True
    if axis == "y":
        return lhs["kind"] in {"fullRow", "switchRow"} and rhs["kind"] in {"fullRow", "switchRow"}
    return False


def validated_accessibility_frame_samples(
    report_path: Path,
    screenshot_path: Path,
    click_probe_manifest_path: Path | None,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any] | None]:
    validate_packaged_window_report(report_path, screenshot_path)
    report = load_report(report_path)
    samples_report = report.get("accessibilityFrameSamples")
    if not isinstance(samples_report, dict):
        raise SystemExit(f"{report_path} does not contain accessibilityFrameSamples")
    if samples_report.get("ok") is not True:
        raise SystemExit(
            f"{report_path} Accessibility frame sampling failed: {samples_report.get('validationIssues')}"
        )
    if samples_report.get("liveAccessibilitySampling") != "frame-sampled":
        raise SystemExit(f"{report_path} did not run live Accessibility frame sampling")
    if samples_report.get("minimumHitTarget") != MINIMUM_HIT_TARGET:
        raise SystemExit(f"{report_path} Accessibility frame floor drifted from {MINIMUM_HIT_TARGET} pt")
    if samples_report.get("minimumTargetClearance") != MINIMUM_TARGET_CLEARANCE:
        raise SystemExit(f"{report_path} Accessibility clearance floor drifted from {MINIMUM_TARGET_CLEARANCE} pt")
    if samples_report.get("unresolvedRequiredContractIDs") != []:
        raise SystemExit(
            f"{report_path} missed required live Accessibility targets: "
            f"{samples_report.get('unresolvedRequiredContractIDs')}"
        )
    if samples_report.get("validationIssues") != []:
        raise SystemExit(f"{report_path} reported Accessibility frame validation issues")

    required_contract_ids = string_list(
        samples_report.get("requiredContractIDs"),
        f"{report_path} accessibilityFrameSamples.requiredContractIDs",
    )
    sampled_contract_ids = string_list(
        samples_report.get("sampledContractIDs"),
        f"{report_path} accessibilityFrameSamples.sampledContractIDs",
    )
    missing_required_contracts = sorted(set(REQUIRED_LIVE_ACCESSIBILITY_CONTRACT_IDS) - set(required_contract_ids))
    if missing_required_contracts:
        raise SystemExit(
            f"{report_path} live Accessibility gate no longer requires: {', '.join(missing_required_contracts)}"
        )
    missing_sampled_required_contracts = sorted(set(required_contract_ids) - set(sampled_contract_ids))
    if missing_sampled_required_contracts:
        raise SystemExit(
            f"{report_path} did not sample required Accessibility targets: "
            f"{', '.join(missing_sampled_required_contracts)}"
        )

    samples = samples_report.get("samples")
    if not isinstance(samples, list) or not samples:
        raise SystemExit(f"{report_path} has no Accessibility frame samples")
    sample_count = samples_report.get("sampleCount")
    if sample_count != len(samples) or sample_count < len(required_contract_ids):
        raise SystemExit(f"{report_path} Accessibility sampleCount is inconsistent")

    sample_ids: set[str] = set()
    sample_summaries: list[dict[str, Any]] = []
    for sample in samples:
        contract_id, sample_summary = validated_accessibility_frame_sample(report_path, sample)
        sample_ids.add(contract_id)
        sample_summaries.append(sample_summary)
    spacing_issues = accessibility_frame_spacing_issues(sample_summaries)
    if spacing_issues:
        raise SystemExit(f"{report_path} Accessibility frame samples have ambiguous spacing: {spacing_issues}")

    if sample_ids != set(sampled_contract_ids):
        raise SystemExit(f"{report_path} sampledContractIDs do not match sample entries")

    click_probe_manifest = None
    if click_probe_manifest_path is not None:
        click_probe_manifest = validated_comparison_manifest(click_probe_manifest_path)
        known_contract_ids = set(click_probe_manifest["contractIDs"])
        unknown_contract_ids = sorted(set(required_contract_ids).union(sample_ids) - known_contract_ids)
        if unknown_contract_ids:
            raise SystemExit(
                f"{report_path} Accessibility samples are not present in packaged click-probe manifest: "
                f"{', '.join(unknown_contract_ids)}"
            )
        surface = report.get("surface", {})
        command_ids = string_list(
            surface.get("commandIDs") if isinstance(surface, dict) else None,
            f"{report_path} surface.commandIDs",
        )
        missing_command_contracts = sorted(set(window_command_contract_ids(command_ids)) - known_contract_ids)
        if missing_command_contracts:
            raise SystemExit(
                f"{report_path} packaged click-probe manifest is missing window command contracts: "
                f"{', '.join(missing_command_contracts)}"
            )

    normalized_samples_report = dict(samples_report)
    normalized_samples_report["sampleSummaries"] = sorted(sample_summaries, key=lambda sample: sample["contractID"])
    return report, normalized_samples_report, click_probe_manifest


def write_accessibility_frames_manifest(
    report_path: Path,
    screenshot_path: Path,
    click_probe_manifest_path: Path | None,
    manifest_path: Path,
) -> None:
    manifest_directory = manifest_path.parent
    report, samples_report, click_probe_manifest = validated_accessibility_frame_samples(
        report_path,
        screenshot_path,
        click_probe_manifest_path,
    )

    manifest = {
        "ok": True,
        "stage": "live-accessibility-frame-sampled",
        "liveAccessibilitySampling": samples_report["liveAccessibilitySampling"],
        "windowReport": relative_manifest_path(report_path, manifest_directory),
        "windowScreenshot": relative_manifest_path(screenshot_path, manifest_directory),
        "minimumHitTarget": samples_report["minimumHitTarget"],
        "minimumTargetClearance": samples_report["minimumTargetClearance"],
        "requiredSamplePointNames": sorted(EXPECTED_SAMPLE_POINTS),
        "requiredContractIDs": samples_report["requiredContractIDs"],
        "sampledContractIDs": samples_report["sampledContractIDs"],
        "unresolvedRequiredContractIDs": samples_report["unresolvedRequiredContractIDs"],
        "skippedContractIDs": samples_report["skippedContractIDs"],
        "sampleCount": samples_report["sampleCount"],
        "sampleSummaries": samples_report["sampleSummaries"],
        "windowSurface": report.get("surface"),
        "image": report.get("image"),
        "validationIssues": samples_report["validationIssues"],
    }
    surface = report.get("surface")
    if isinstance(surface, dict):
        command_ids = string_list(surface.get("commandIDs"), f"{report_path} surface.commandIDs")
        command_contract_ids = window_command_contract_ids(command_ids)
        manifest["windowCommandContractCount"] = len(command_contract_ids)
        manifest["windowCommandContractIDs"] = command_contract_ids
    if click_probe_manifest_path is not None:
        manifest["clickProbeManifest"] = relative_manifest_path(click_probe_manifest_path, manifest_directory)
    if click_probe_manifest is not None:
        manifest["clickProbeCount"] = click_probe_manifest["clickProbeCount"]
        manifest["launchServicesMatchesDirect"] = click_probe_manifest["launchServicesMatchesDirect"]

    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="validate one native smoke report's click probes")
    validate_parser.add_argument("report", type=Path)
    validate_parser.add_argument("--label", default="quill-code-desktop native smoke")

    compare_parser = subparsers.add_parser("compare", help="compare direct executable and Launch Services click probes")
    compare_parser.add_argument("direct_report", type=Path)
    compare_parser.add_argument("launch_services_report", type=Path)
    compare_parser.add_argument("--manifest", required=True, type=Path)

    readiness_parser = subparsers.add_parser("readiness", help="write packaged native Accessibility readiness evidence")
    readiness_parser.add_argument("artifact_root", type=Path)
    readiness_parser.add_argument("--manifest", required=True, type=Path)

    window_parser = subparsers.add_parser("window", help="validate packaged live-window smoke report and screenshot")
    window_parser.add_argument("report", type=Path)
    window_parser.add_argument("screenshot", type=Path)

    frames_parser = subparsers.add_parser("frames", help="write live packaged Accessibility frame evidence")
    frames_parser.add_argument("report", type=Path)
    frames_parser.add_argument("screenshot", type=Path)
    frames_parser.add_argument("--click-probe-manifest", type=Path)
    frames_parser.add_argument("--manifest", required=True, type=Path)

    args = parser.parse_args()
    if args.command == "validate":
        validate_report(args.report, args.label)
    elif args.command == "compare":
        write_comparison_manifest(args.direct_report, args.launch_services_report, args.manifest)
    elif args.command == "readiness":
        write_accessibility_readiness_manifest(args.artifact_root, args.manifest)
    elif args.command == "window":
        validate_packaged_window_report(args.report, args.screenshot)
    elif args.command == "frames":
        write_accessibility_frames_manifest(
            args.report,
            args.screenshot,
            args.click_probe_manifest,
            args.manifest,
        )


if __name__ == "__main__":
    main()
