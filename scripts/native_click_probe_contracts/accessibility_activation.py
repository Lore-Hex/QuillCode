"""Validate live Accessibility activation samples from packaged window smoke reports."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .constants import REQUIRED_LIVE_ACCESSIBILITY_ACTIVATION_CONTRACT_IDS
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

    return {
        "contractID": contract_id,
        "selectorKind": selector_kind,
        "selector": selector,
        "resolvedIdentifier": resolved_identifier,
        "expectedOutcome": expected_outcome,
        "beforeValue": before_value,
        "afterValue": after_value,
        "interactionEvidence": interaction_evidence,
    }


def _required_string(check: dict[str, Any], key: str, report_path: Path) -> str:
    value = check.get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{report_path} Accessibility activation check missing {key}")
    return value
