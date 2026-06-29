#!/usr/bin/env python3
"""Validate QuillCode native click-probe contracts emitted by smoke reports."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

MINIMUM_HIT_TARGET = 44
EXPECTED_SAMPLE_POINTS = {
    "center": (0.5, 0.5),
    "leading-interior": (0.18, 0.5),
    "trailing-interior": (0.82, 0.5),
    "top-interior": (0.5, 0.18),
    "bottom-interior": (0.5, 0.82),
}


def load_report(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as report_file:
        report = json.load(report_file)
    if not isinstance(report, dict):
        raise SystemExit(f"{path} did not contain a JSON object")
    return report


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
        required_min_width = probe.get("requiredMinWidth")
        required_min_height = probe.get("requiredMinHeight")
        if not all(isinstance(value, str) and value.strip() for value in (contract_id, selector_kind, selector, kind, action)):
            raise SystemExit(f"{label} report has an incomplete click probe identity: {probe!r}")
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
        "samplePointNames": sorted({
            point["name"]
            for probe in direct_probe_contracts
            for point in probe["samplePoints"]
        }),
    }
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

    args = parser.parse_args()
    if args.command == "validate":
        validate_report(args.report, args.label)
    elif args.command == "compare":
        write_comparison_manifest(args.direct_report, args.launch_services_report, args.manifest)


if __name__ == "__main__":
    main()
