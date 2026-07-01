"""Validate individual live Accessibility frame samples."""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any

from .constants import EXPECTED_SAMPLE_POINTS, MINIMUM_TARGET_CLEARANCE
from .json_io import numeric_value, required_string


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
            raise SystemExit(
                f"{report_path} has malformed sample point for {contract_id}: {point!r}"
            )
        name = point.get("name")
        if not isinstance(name, str) or name in points_by_name:
            raise SystemExit(
                f"{report_path} has malformed or duplicate sample point for {contract_id}: {point!r}"
            )
        points_by_name[name] = point

    missing_points = sorted(set(EXPECTED_SAMPLE_POINTS) - set(points_by_name))
    if missing_points:
        raise SystemExit(
            f"{report_path} Accessibility sample for {contract_id} is missing: "
            f"{', '.join(missing_points)}"
        )

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
            raise SystemExit(
                f"{report_path} Accessibility sample point is missing hitTestAvailable "
                f"for {contract_id}.{name}"
            )
        if not isinstance(hit_test_error, str):
            raise SystemExit(
                f"{report_path} Accessibility sample point is missing hitTestError "
                f"for {contract_id}.{name}"
            )
        if not isinstance(hit_test_identifier, str):
            raise SystemExit(
                f"{report_path} Accessibility sample point is missing hitTestIdentifier "
                f"for {contract_id}.{name}"
            )
        if not isinstance(hit_test_role, str):
            raise SystemExit(
                f"{report_path} Accessibility sample point is missing hitTestRole "
                f"for {contract_id}.{name}"
            )
        if not isinstance(hit_test_label, str):
            raise SystemExit(
                f"{report_path} Accessibility sample point is missing hitTestLabel "
                f"for {contract_id}.{name}"
            )
        if (
            not isinstance(hit_test_ancestor_identifiers, list)
            or not all(isinstance(value, str) for value in hit_test_ancestor_identifiers)
        ):
            raise SystemExit(
                f"{report_path} Accessibility sample point has malformed "
                f"hitTestAncestorIdentifiers for {contract_id}.{name}"
            )
        if not isinstance(hit_test_matches_target, bool):
            raise SystemExit(
                f"{report_path} Accessibility sample point is missing hitTestMatchesTarget "
                f"for {contract_id}.{name}"
            )
        if requires_unblocked_interior and hit_test_available and not hit_test_matches_target:
            raise SystemExit(
                f"{report_path} Accessibility sample point {contract_id}.{name} "
                f"hit {hit_test_identifier!r} instead of the target"
            )
        expected_x = frame["x"] + frame["width"] * normalized_point[0]
        expected_y = frame["y"] + frame["height"] * normalized_point[1]
        if not math.isclose(x, expected_x, rel_tol=0.0, abs_tol=1e-6) or not math.isclose(
            y,
            expected_y,
            rel_tol=0.0,
            abs_tol=1e-6,
        ):
            raise SystemExit(
                f"{report_path} Accessibility sample point drifted for {contract_id}.{name}"
            )

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
    required_peer_clearance = numeric_value(
        sample.get("requiredPeerClearance"),
        f"{contract_id}.requiredPeerClearance",
    )
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
                issues.extend(accessibility_frame_pair_spacing_issues(collision_scope, lhs, rhs))
    return sorted(issues)


def accessibility_frame_pair_spacing_issues(
    collision_scope: str,
    lhs: dict[str, Any],
    rhs: dict[str, Any],
) -> list[str]:
    if lhs["resolvedIdentifier"] == rhs["resolvedIdentifier"]:
        return []

    lhs_frame = lhs["frame"]
    rhs_frame = rhs["frame"]
    overlap_width = frame_overlap(lhs_frame, rhs_frame, axis="x")
    overlap_height = frame_overlap(lhs_frame, rhs_frame, axis="y")
    if overlap_width > 1 and overlap_height > 1:
        return [
            f"{lhs['contractID']} overlaps {rhs['contractID']} in {collision_scope} "
            f"by {overlap_width:.1f}x{overlap_height:.1f}"
        ]

    issues: list[str] = []
    vertical_overlap = overlap_height
    horizontal_overlap = overlap_width
    horizontal_gap = frame_gap(lhs_frame, rhs_frame, axis="x")
    vertical_gap = frame_gap(lhs_frame, rhs_frame, axis="y")
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
    return issues


def frame_overlap(lhs_frame: dict[str, float], rhs_frame: dict[str, float], *, axis: str) -> float:
    origin_key = axis
    size_key = "width" if axis == "x" else "height"
    return min(
        lhs_frame[origin_key] + lhs_frame[size_key],
        rhs_frame[origin_key] + rhs_frame[size_key],
    ) - max(lhs_frame[origin_key], rhs_frame[origin_key])


def frame_gap(lhs_frame: dict[str, float], rhs_frame: dict[str, float], *, axis: str) -> float:
    origin_key = axis
    size_key = "width" if axis == "x" else "height"
    return max(lhs_frame[origin_key], rhs_frame[origin_key]) - min(
        lhs_frame[origin_key] + lhs_frame[size_key],
        rhs_frame[origin_key] + rhs_frame[size_key],
    )


def allows_tight_accessibility_clearance(lhs: dict[str, Any], rhs: dict[str, Any], *, axis: str) -> bool:
    if lhs["kind"] == "segmentedControl" or rhs["kind"] == "segmentedControl":
        return True
    if axis == "y":
        return lhs["kind"] in {"fullRow", "switchRow"} and rhs["kind"] in {"fullRow", "switchRow"}
    return False
