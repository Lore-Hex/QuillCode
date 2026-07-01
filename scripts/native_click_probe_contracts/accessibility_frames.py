"""Validate live Accessibility frame samples from packaged window smoke reports."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .constants import (
    EXPECTED_SAMPLE_POINTS,
    MINIMUM_HIT_TARGET,
    MINIMUM_TARGET_CLEARANCE,
    REQUIRED_LIVE_ACCESSIBILITY_CONTRACT_IDS,
)
from .accessibility_frame_samples import (
    accessibility_frame_spacing_issues,
    validated_accessibility_frame_sample,
)
from .accessibility_activation import validated_accessibility_activation_report
from .json_io import load_report, relative_manifest_path, string_list
from .packaged_window import validate_packaged_window_report, validated_comparison_manifest
from .probe_contracts import window_command_contract_ids


def validated_accessibility_frame_samples(
    report_path: Path,
    screenshot_path: Path,
    click_probe_manifest_path: Path | None,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any] | None]:
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
    activation_report = validated_accessibility_activation_report(report_path, report)
    return report, normalized_samples_report, activation_report, click_probe_manifest

def write_accessibility_frames_manifest(
    report_path: Path,
    screenshot_path: Path,
    click_probe_manifest_path: Path | None,
    manifest_path: Path,
) -> None:
    manifest_directory = manifest_path.parent
    report, samples_report, activation_report, click_probe_manifest = validated_accessibility_frame_samples(
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
        "liveAccessibilityActivation": activation_report["liveAccessibilityActivation"],
        "activationRequiredContractIDs": activation_report["requiredContractIDs"],
        "activatedContractIDs": activation_report["activatedContractIDs"],
        "activationCheckCount": activation_report["checkCount"],
        "activationCheckSummaries": activation_report["checkSummaries"],
        "windowSurface": report.get("surface"),
        "image": report.get("image"),
        "validationIssues": samples_report["validationIssues"],
        "activationValidationIssues": activation_report["validationIssues"],
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
