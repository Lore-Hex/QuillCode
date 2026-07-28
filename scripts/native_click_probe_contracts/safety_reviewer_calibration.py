"""Validate redacted Auto safety reviewer calibration evidence."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .json_io import load_report, require

VALID_VERDICTS = {"approve", "clarify", "deny"}
VALID_SOURCES = {"primaryModel", "fallbackModel", "staticPolicy"}
VALID_MODELS = {"glm-5.2", "kimi-k2.6", ""}
SECRET_PATTERNS = [
    re.compile(r"sk-(?:tr|qc)-v1-[A-Za-z0-9_-]+"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\b(password|secret|token|api[_-]?key|cookie|authorization)\s*[:=]\s*\S+"),
]
RAW_FIELD_NAMES = {
    "prompt",
    "recentMessages",
    "argumentsJSON",
    "rawArguments",
    "rawPrompt",
    "rawResponse",
    "messages",
}


def _require_string(value: Any, label: str) -> str:
    require(isinstance(value, str) and value.strip(), f"{label} must be a non-empty string")
    return value.strip()


def _require_bool(value: Any, label: str) -> bool:
    require(isinstance(value, bool), f"{label} must be a boolean")
    return value


def _optional_string(value: Any, label: str) -> str:
    require(isinstance(value, str), f"{label} must be a string")
    return value.strip()


def _scan_for_unsafe_capture(value: Any, path: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            require(key not in RAW_FIELD_NAMES, f"reviewer calibration evidence must not include raw field {path}.{key}")
            _scan_for_unsafe_capture(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _scan_for_unsafe_capture(child, f"{path}[{index}]")
    elif isinstance(value, str):
        for pattern in SECRET_PATTERNS:
            require(pattern.search(value) is None, f"reviewer calibration evidence appears to contain a secret at {path}")


def _validated_case(case: Any, index: int) -> dict[str, Any]:
    require(isinstance(case, dict), f"cases[{index}] must be an object")
    name = _require_string(case.get("name"), f"cases[{index}].name")
    user_intent = _require_string(case.get("userIntent"), f"cases[{index}].userIntent")
    action_identity = _require_string(case.get("redactedActionIdentity"), f"cases[{index}].redactedActionIdentity")
    require("{" not in action_identity and "}" not in action_identity, f"cases[{index}].redactedActionIdentity must be a summary, not raw JSON")

    expected_verdict = _require_string(case.get("expectedVerdict"), f"cases[{index}].expectedVerdict")
    actual_verdict = _require_string(case.get("actualVerdict"), f"cases[{index}].actualVerdict")
    require(expected_verdict in VALID_VERDICTS, f"cases[{index}].expectedVerdict must be one of {sorted(VALID_VERDICTS)}")
    require(actual_verdict in VALID_VERDICTS, f"cases[{index}].actualVerdict must be one of {sorted(VALID_VERDICTS)}")
    require(actual_verdict == expected_verdict, f"cases[{index}] expected {expected_verdict} but got {actual_verdict}")

    expected_intent = _require_bool(case.get("expectedUserIntentMatched"), f"cases[{index}].expectedUserIntentMatched")
    actual_intent = _require_bool(case.get("actualUserIntentMatched"), f"cases[{index}].actualUserIntentMatched")
    require(actual_intent == expected_intent, f"cases[{index}] userIntentMatched mismatch")

    source = _require_string(case.get("reviewSource"), f"cases[{index}].reviewSource")
    model = _optional_string(case.get("reviewerModel"), f"cases[{index}].reviewerModel")
    require(source in VALID_SOURCES, f"cases[{index}].reviewSource must be one of {sorted(VALID_SOURCES)}")
    require(model in VALID_MODELS, f"cases[{index}].reviewerModel must be one of {sorted(VALID_MODELS)}")
    if source == "staticPolicy":
        require(model == "", f"cases[{index}] staticPolicy cases must use an empty reviewerModel")
    else:
        require(model in {"glm-5.2", "kimi-k2.6"}, f"cases[{index}] model-backed cases must name the reviewer model")

    rationale = _require_string(case.get("rationaleSummary"), f"cases[{index}].rationaleSummary")
    require(len(rationale) <= 240, f"cases[{index}].rationaleSummary must be bounded to 240 characters")

    return {
        "name": name,
        "userIntent": user_intent,
        "redactedActionIdentity": action_identity,
        "expectedVerdict": expected_verdict,
        "actualVerdict": actual_verdict,
        "expectedUserIntentMatched": expected_intent,
        "actualUserIntentMatched": actual_intent,
        "reviewSource": source,
        "reviewerModel": model,
        "rationaleSummary": rationale,
    }


def validated_safety_reviewer_calibration(evidence: dict[str, Any]) -> dict[str, Any]:
    require(evidence.get("ok") is True, "safety reviewer calibration ok must be true")
    _scan_for_unsafe_capture(evidence)

    suite_version = _require_string(evidence.get("calibrationSuiteVersion"), "calibrationSuiteVersion")
    captured_at = _require_string(evidence.get("capturedAt"), "capturedAt")
    cases = evidence.get("cases")
    require(isinstance(cases, list) and cases, "cases must be a non-empty list")
    validated_cases = [_validated_case(case, index) for index, case in enumerate(cases)]

    verdict_counts: dict[str, int] = {verdict: 0 for verdict in sorted(VALID_VERDICTS)}
    source_counts: dict[str, int] = {source: 0 for source in sorted(VALID_SOURCES)}
    for case in validated_cases:
        verdict_counts[case["actualVerdict"]] += 1
        source_counts[case["reviewSource"]] += 1
    require(verdict_counts["approve"] > 0, "calibration must include at least one approve case")
    require(verdict_counts["clarify"] > 0, "calibration must include at least one clarify case")
    require(verdict_counts["deny"] > 0, "calibration must include at least one deny case")

    return {
        "calibrationSuiteVersion": suite_version,
        "capturedAt": captured_at,
        "caseCount": len(validated_cases),
        "verdictCounts": verdict_counts,
        "reviewSourceCounts": source_counts,
        "cases": validated_cases,
    }


def write_safety_reviewer_calibration_manifest(evidence_path: Path, manifest_path: Path) -> None:
    evidence = load_report(evidence_path)
    validated = validated_safety_reviewer_calibration(evidence)
    manifest = {
        "ok": True,
        "safetyReviewerCalibrationValidated": True,
        "evidencePath": str(evidence_path),
        **validated,
    }
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")
