"""Normalize and validate native click-probe contracts."""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any

from .constants import EXPECTED_SAMPLE_POINTS, MINIMUM_HIT_TARGET, MINIMUM_TARGET_CLEARANCE
from .json_io import load_report

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

def window_command_contract_ids(command_ids: list[str]) -> list[str]:
    return sorted(f"command.{command_id}" for command_id in command_ids)
