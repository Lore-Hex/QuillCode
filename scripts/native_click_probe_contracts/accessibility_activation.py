"""Validate live Accessibility activation samples from packaged window smoke reports."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .constants import (
    MAXIMUM_PRESENTED_RESIDENT_MEMORY_BYTES,
    MAXIMUM_PRESENTED_THREAD_COUNT,
    REQUIRED_LIVE_ACCESSIBILITY_ACTIVATION_CONTRACT_IDS,
)
from .json_io import string_list


def validated_accessibility_activation_report(report_path: Path, report: dict[str, Any]) -> dict[str, Any]:
    activation_report = report.get("accessibilityActivation")
    if not isinstance(activation_report, dict):
        raise SystemExit(f"{report_path} does not contain accessibilityActivation")
    if activation_report.get("ok") is not True:
        raise SystemExit(
            f"{report_path} Accessibility activation failed: {activation_report.get('validationIssues')}"
        )
    if activation_report.get("liveAccessibilityActivation") != "ax-press-sampled":
        raise SystemExit(f"{report_path} did not run live AXPress activation sampling")
    if activation_report.get("resourceMeasurement") != "physical-footprint":
        raise SystemExit(f"{report_path} did not measure live activation physical footprint")
    if activation_report.get("validationIssues") != []:
        raise SystemExit(f"{report_path} reported Accessibility activation validation issues")

    required_contract_ids = string_list(
        activation_report.get("requiredContractIDs"),
        f"{report_path} accessibilityActivation.requiredContractIDs",
    )
    activated_contract_ids = string_list(
        activation_report.get("activatedContractIDs"),
        f"{report_path} accessibilityActivation.activatedContractIDs",
    )
    missing_required_contracts = sorted(
        set(REQUIRED_LIVE_ACCESSIBILITY_ACTIVATION_CONTRACT_IDS) - set(required_contract_ids)
    )
    if missing_required_contracts:
        raise SystemExit(
            f"{report_path} live Accessibility activation gate no longer requires: "
            f"{', '.join(missing_required_contracts)}"
        )
    missing_activated_contracts = sorted(set(required_contract_ids) - set(activated_contract_ids))
    if missing_activated_contracts:
        raise SystemExit(
            f"{report_path} did not activate required Accessibility targets: "
            f"{', '.join(missing_activated_contracts)}"
        )

    checks = activation_report.get("checks")
    if not isinstance(checks, list) or not checks:
        raise SystemExit(f"{report_path} has no Accessibility activation checks")
    check_count = activation_report.get("checkCount")
    if check_count != len(checks) or check_count < len(required_contract_ids):
        raise SystemExit(f"{report_path} Accessibility activation checkCount is inconsistent")

    check_summaries = [_validated_accessibility_activation_check(report_path, check) for check in checks]
    check_ids = {summary["contractID"] for summary in check_summaries}
    if check_ids != set(activated_contract_ids):
        raise SystemExit(f"{report_path} activatedContractIDs do not match activation check entries")

    peak_memory = max(check["presentedResidentMemoryBytes"] for check in check_summaries)
    peak_contract_id = _required_string(
        activation_report,
        "peakPresentedContractID",
        report_path,
    )
    reported_peak_memory = _positive_integer(
        activation_report.get("peakPresentedResidentMemoryBytes"),
        "peakPresentedResidentMemoryBytes",
        report_path,
    )
    maximum_growth = _integer(
        activation_report.get("maximumPresentedResidentMemoryGrowthBytes"),
        "maximumPresentedResidentMemoryGrowthBytes",
        report_path,
    )
    peak_threads = _positive_integer(
        activation_report.get("peakPresentedThreadCount"),
        "peakPresentedThreadCount",
        report_path,
    )
    peak_contract_ids = {
        check["contractID"]
        for check in check_summaries
        if check["presentedResidentMemoryBytes"] == peak_memory
    }
    if peak_contract_id not in peak_contract_ids:
        raise SystemExit(f"{report_path} peak presented-memory contract is inconsistent")
    if reported_peak_memory != peak_memory:
        raise SystemExit(f"{report_path} peak presented-memory value is inconsistent")
    if maximum_growth != max(
        check["presentedResidentMemoryGrowthBytes"] for check in check_summaries
    ):
        raise SystemExit(f"{report_path} maximum presented-memory growth is inconsistent")
    if peak_threads != max(check["presentedThreadCount"] for check in check_summaries):
        raise SystemExit(f"{report_path} peak presented-thread count is inconsistent")

    normalized_report = dict(activation_report)
    normalized_report["checkSummaries"] = sorted(check_summaries, key=lambda check: check["contractID"])
    return normalized_report


def _validated_accessibility_activation_check(report_path: Path, check: Any) -> dict[str, Any]:
    if not isinstance(check, dict):
        raise SystemExit(f"{report_path} Accessibility activation check is not an object")
    contract_id = _required_string(check, "contractID", report_path)
    selector_kind = _required_string(check, "selectorKind", report_path)
    selector = _required_string(check, "selector", report_path)
    resolved_identifier = _required_string(check, "resolvedIdentifier", report_path)
    expected_outcome = _required_string(check, "expectedOutcome", report_path)
    before_value = _required_string(check, "beforeValue", report_path)
    after_value = _required_string(check, "afterValue", report_path)
    interaction_evidence = _required_string(check, "interactionEvidence", report_path)
    baseline_memory = _positive_integer(
        check.get("baselineResidentMemoryBytes"),
        f"{contract_id} baselineResidentMemoryBytes",
        report_path,
    )
    presented_memory = _positive_integer(
        check.get("presentedResidentMemoryBytes"),
        f"{contract_id} presentedResidentMemoryBytes",
        report_path,
    )
    presented_memory_growth = _integer(
        check.get("presentedResidentMemoryGrowthBytes"),
        f"{contract_id} presentedResidentMemoryGrowthBytes",
        report_path,
    )
    baseline_threads = _positive_integer(
        check.get("baselineThreadCount"),
        f"{contract_id} baselineThreadCount",
        report_path,
    )
    presented_threads = _positive_integer(
        check.get("presentedThreadCount"),
        f"{contract_id} presentedThreadCount",
        report_path,
    )

    if check.get("ok") is not True:
        raise SystemExit(f"{report_path} Accessibility activation check failed for {contract_id}")
    if check.get("activation") != "AXPress":
        raise SystemExit(f"{report_path} {contract_id} activation is not AXPress")
    if check.get("axError") != "success":
        raise SystemExit(f"{report_path} {contract_id} AXPress returned {check.get('axError')}")
    if before_value == after_value:
        raise SystemExit(f"{report_path} {contract_id} AXPress did not change observable state")
    if check.get("validationIssue") not in ("", None):
        raise SystemExit(f"{report_path} {contract_id} carries validationIssue {check.get('validationIssue')}")
    if presented_memory_growth != presented_memory - baseline_memory:
        raise SystemExit(f"{report_path} {contract_id} presented-memory delta is inconsistent")
    if presented_memory > MAXIMUM_PRESENTED_RESIDENT_MEMORY_BYTES:
        raise SystemExit(
            f"{report_path} {contract_id} presented physical footprint "
            f"{presented_memory} exceeds {MAXIMUM_PRESENTED_RESIDENT_MEMORY_BYTES} bytes"
        )
    if baseline_threads > MAXIMUM_PRESENTED_THREAD_COUNT or presented_threads > MAXIMUM_PRESENTED_THREAD_COUNT:
        raise SystemExit(
            f"{report_path} {contract_id} activation thread count exceeds "
            f"{MAXIMUM_PRESENTED_THREAD_COUNT}"
        )
    if contract_id == "command.search" and not all(
        marker in interaction_evidence for marker in ("focused", "AXValue")
    ):
        raise SystemExit(
            f"{report_path} command.search does not prove focused AXValue text entry"
        )
    if contract_id == "command.new-chat" and not all(
        marker in interaction_evidence for marker in ("exactly one", "selected", "focused", "AXValue")
    ):
        raise SystemExit(
            f"{report_path} command.new-chat does not prove one selected chat with focused AXValue entry"
        )
    if contract_id == "composer.model-picker" and not all(
        marker in interaction_evidence
        for marker in ("focused", "AXValue", "Prometheus 1.0", "model option")
    ):
        raise SystemExit(
            f"{report_path} composer.model-picker does not prove focused catalog search"
        )
    if contract_id == "command.settings" and not all(
        marker in interaction_evidence
        for marker in ("Settings", "notifications control", "quillcode-settings-close", "AXPress")
    ):
        raise SystemExit(
            f"{report_path} command.settings does not prove rendered controls and close-button dismissal"
        )
    if contract_id == "onboarding.developer-key" and not all(
        marker in interaction_evidence
        for marker in (
            "Developer override settings",
            "developer key field",
            "quillcode-settings-close",
            "AXPress",
        )
    ):
        raise SystemExit(
            f"{report_path} onboarding.developer-key does not prove direct developer-key settings routing"
        )
    if contract_id == "command.toggle-automations" and not all(
        marker in interaction_evidence
        for marker in ("Automations", "Create control", "quillcode-automations-close", "AXPress")
    ):
        raise SystemExit(
            f"{report_path} command.toggle-automations does not prove rendered controls and close-button dismissal"
        )
    if contract_id == "command.toggle-extensions" and not all(
        marker in interaction_evidence
        for marker in ("Extensions", "Add control", "quillcode-extensions-close", "AXPress")
    ):
        raise SystemExit(
            f"{report_path} command.toggle-extensions does not prove rendered controls and close-button dismissal"
        )
    if contract_id == "command.toggle-memories" and not all(
        marker in interaction_evidence
        for marker in ("Memories", "Add control", "quillcode-memories-close", "AXPress")
    ):
        raise SystemExit(
            f"{report_path} command.toggle-memories does not prove rendered controls and close-button dismissal"
        )
    if contract_id == "command.toggle-activity" and not all(
        marker in interaction_evidence
        for marker in (
            "Activity",
            "task summary",
            "quillcode-activity-close",
            "AXPress",
            "restored composer width",
        )
    ):
        raise SystemExit(
            f"{report_path} command.toggle-activity does not prove rendered content, close-button dismissal, and workspace restoration"
        )
    if contract_id == "command.toggle-review-panel" and not all(
        marker in interaction_evidence
        for marker in (
            "Review",
            "scope control",
            "quillcode-review-close",
            "AXPress",
        )
    ):
        raise SystemExit(
            f"{report_path} command.toggle-review-panel does not prove rendered scope controls and close-button dismissal"
        )

    return {
        "contractID": contract_id,
        "selectorKind": selector_kind,
        "selector": selector,
        "resolvedIdentifier": resolved_identifier,
        "expectedOutcome": expected_outcome,
        "beforeValue": before_value,
        "afterValue": after_value,
        "interactionEvidence": interaction_evidence,
        "baselineResidentMemoryBytes": baseline_memory,
        "presentedResidentMemoryBytes": presented_memory,
        "presentedResidentMemoryGrowthBytes": presented_memory_growth,
        "baselineThreadCount": baseline_threads,
        "presentedThreadCount": presented_threads,
    }


def _required_string(check: dict[str, Any], key: str, report_path: Path) -> str:
    value = check.get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{report_path} Accessibility activation check missing {key}")
    return value


def _integer(value: Any, key: str, report_path: Path) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise SystemExit(f"{report_path} Accessibility activation check missing integer {key}")
    return value


def _positive_integer(value: Any, key: str, report_path: Path) -> int:
    integer = _integer(value, key, report_path)
    if integer <= 0:
        raise SystemExit(f"{report_path} Accessibility activation check has nonpositive {key}")
    return integer
