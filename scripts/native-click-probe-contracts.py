#!/usr/bin/env python3
"""Validate QuillCode native click-probe contracts emitted by smoke reports."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

MINIMUM_HIT_TARGET = 44
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
EXPECTED_SAMPLE_POINTS = {
    "center": (0.5, 0.5),
    "leading-interior": (0.18, 0.5),
    "trailing-interior": (0.82, 0.5),
    "top-interior": (0.5, 0.18),
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
        kind = probe.get("kind")
        action = probe.get("action")
        allows_nested_interactive_children = probe.get("allowsNestedInteractiveChildren")
        requires_unblocked_interior = probe.get("requiresUnblockedInterior")
        required_min_width = probe.get("requiredMinWidth")
        required_min_height = probe.get("requiredMinHeight")
        if not all(isinstance(value, str) and value.strip() for value in (contract_id, selector_kind, selector, kind, action)):
            raise SystemExit(f"{label} report has an incomplete click probe identity: {probe!r}")
        if not isinstance(allows_nested_interactive_children, bool):
            raise SystemExit(f"{label} report has malformed click probe nested-child policy for {contract_id}: {probe!r}")
        if not isinstance(requires_unblocked_interior, bool):
            raise SystemExit(f"{label} report has malformed click probe interior-blocking policy for {contract_id}: {probe!r}")
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
        if allows_nested_interactive_children != contract.get("allowsNestedInteractiveChildren"):
            raise SystemExit(f"{label} report has click probe nested-child policy drift for {contract_id}: {probe!r}")
        if requires_unblocked_interior != contract.get("requiresUnblockedInterior"):
            raise SystemExit(f"{label} report has click probe interior-blocking policy drift for {contract_id}: {probe!r}")
        if not isinstance(required_min_width, (int, float)) or required_min_width < MINIMUM_HIT_TARGET:
            raise SystemExit(f"{label} report has undersized click probe requiredMinWidth for {contract_id}: {probe!r}")
        if not isinstance(required_min_height, (int, float)) or required_min_height < MINIMUM_HIT_TARGET:
            raise SystemExit(f"{label} report has undersized click probe requiredMinHeight for {contract_id}: {probe!r}")

        normalized.append({
            "contractID": contract_id,
            "selectorKind": selector_kind,
            "selector": selector,
            "kind": kind,
            "action": action,
            "allowsNestedInteractiveChildren": allows_nested_interactive_children,
            "requiresUnblockedInterior": requires_unblocked_interior,
            "requiredMinWidth": float(required_min_width),
            "requiredMinHeight": float(required_min_height),
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

    normalized_probe_contracts(report, "packaged live-window")

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
    missing_commands = sorted(set(REQUIRED_WINDOW_COMMAND_IDS) - {value for value in command_ids if isinstance(value, str)})
    require(not missing_commands, f"{report_path} surface is missing commands: {', '.join(missing_commands)}")

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
        "contractIDs": [probe["contractID"] for probe in direct_probe_contracts],
        "clickProbePolicies": [
            {
                "contractID": probe["contractID"],
                "allowsNestedInteractiveChildren": probe["allowsNestedInteractiveChildren"],
                "requiresUnblockedInterior": probe["requiresUnblockedInterior"],
            }
            for probe in direct_probe_contracts
        ],
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
    if not isinstance(manifest.get("samplePointNames"), list) or sorted(manifest["samplePointNames"]) != sorted(EXPECTED_SAMPLE_POINTS):
        raise SystemExit(f"{path} does not list the required click-probe sample points")
    if manifest.get("clickProbeCount") != len(manifest["contractIDs"]):
        raise SystemExit(f"{path} clickProbeCount does not match contractIDs")
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
        "liveAccessibilitySampling": "not-run",
        "nextLayer": "resolve selectors to live packaged-window accessibility frames and click center plus interior samples",
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(readiness, manifest_file, indent=2, sort_keys=True)
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

    args = parser.parse_args()
    if args.command == "validate":
        validate_report(args.report, args.label)
    elif args.command == "compare":
        write_comparison_manifest(args.direct_report, args.launch_services_report, args.manifest)
    elif args.command == "readiness":
        write_accessibility_readiness_manifest(args.artifact_root, args.manifest)
    elif args.command == "window":
        validate_packaged_window_report(args.report, args.screenshot)


if __name__ == "__main__":
    main()
