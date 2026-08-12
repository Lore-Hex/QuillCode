"""Semantic validation for published packaged-performance evidence."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from performance_evidence_contract import (
    DEFAULT_MAX_LAUNCH_READY_MILLISECONDS,
    IDLE_MEASUREMENT,
    INITIAL_MEASUREMENT,
    INTERACTION_SWEEP_COUNT,
    MEMORY_MEASUREMENT,
    PERFORMANCE_PRODUCT,
    PERFORMANCE_SCHEMA_VERSION,
    PERFORMANCE_WORKLOAD,
    POST_INTERACTION_MEASUREMENT,
    PROCESSOR_TIME_MEASUREMENT,
    RELEASE_ATTEMPT_COUNT,
    REPEATED_INTERACTION_MEASUREMENT,
    production_budgets,
)
from release_verification_contract import (
    MACOS_ARCHITECTURES,
    VerificationError,
    load_json_bytes,
)
from release_verification_performance_attempt import (
    finite_number,
    integer,
    require_keys,
    validate_attempt,
)


PERFORMANCE_EVIDENCE_BYTE_LIMIT = 256 * 1024

TOP_LEVEL_KEYS = frozenset(
    {
        "aggregation",
        "attemptCount",
        "attempts",
        "budgets",
        "interactionSweepCount",
        "idleCPUPercent",
        "idleDurationMilliseconds",
        "idleMeasurement",
        "idleProcessorTimeMilliseconds",
        "idleProcessorTimeNanoseconds",
        "idleResidentMemoryBytes",
        "idleResidentMemoryGrowthBytes",
        "idleResidentMemoryGrowthMiB",
        "idleResidentMemoryMiB",
        "idleThreadCount",
        "idleThreadGrowth",
        "launchReadyMilliseconds",
        "measurement",
        "memoryMeasurement",
        "processorTimeMeasurement",
        "ok",
        "passingAttemptCount",
        "postInteractionMeasurement",
        "postInteractionResidentMemoryBytes",
        "postInteractionResidentMemoryMiB",
        "postInteractionThreadCount",
        "product",
        "repeatedInteractionMeasurement",
        "repeatedInteractionResidentMemoryBytes",
        "repeatedInteractionResidentMemoryGrowthBytes",
        "repeatedInteractionResidentMemoryGrowthMiB",
        "repeatedInteractionResidentMemoryMiB",
        "repeatedInteractionThreadCount",
        "repeatedInteractionThreadGrowth",
        "requiredPassingAttemptCount",
        "residentMemoryBytes",
        "residentMemoryGrowthBytes",
        "residentMemoryGrowthMiB",
        "residentMemoryMiB",
        "schemaVersion",
        "selectedAttempt",
        "threadCount",
        "threadGrowth",
        "withinBudget",
        "workload",
    }
)

SUMMARY_FIELDS = (
    "launchReadyMilliseconds",
    "residentMemoryBytes",
    "residentMemoryMiB",
    "threadCount",
    "postInteractionResidentMemoryBytes",
    "postInteractionResidentMemoryMiB",
    "postInteractionThreadCount",
    "residentMemoryGrowthBytes",
    "residentMemoryGrowthMiB",
    "threadGrowth",
    "repeatedInteractionResidentMemoryBytes",
    "repeatedInteractionResidentMemoryMiB",
    "repeatedInteractionThreadCount",
    "repeatedInteractionResidentMemoryGrowthBytes",
    "repeatedInteractionResidentMemoryGrowthMiB",
    "repeatedInteractionThreadGrowth",
    "idleDurationMilliseconds",
    "idleProcessorTimeNanoseconds",
    "idleProcessorTimeMilliseconds",
    "idleCPUPercent",
    "idleResidentMemoryBytes",
    "idleResidentMemoryMiB",
    "idleResidentMemoryGrowthBytes",
    "idleResidentMemoryGrowthMiB",
    "idleThreadCount",
    "idleThreadGrowth",
)


def validate_performance_evidence(evidence: dict[str, Any]) -> None:
    require_keys(evidence, TOP_LEVEL_KEYS, "performance evidence")
    expected_identity = {
        "schemaVersion": PERFORMANCE_SCHEMA_VERSION,
        "ok": True,
        "product": PERFORMANCE_PRODUCT,
        "workload": PERFORMANCE_WORKLOAD,
        "measurement": INITIAL_MEASUREMENT,
        "memoryMeasurement": MEMORY_MEASUREMENT,
        "processorTimeMeasurement": PROCESSOR_TIME_MEASUREMENT,
        "postInteractionMeasurement": POST_INTERACTION_MEASUREMENT,
        "repeatedInteractionMeasurement": REPEATED_INTERACTION_MEASUREMENT,
        "idleMeasurement": IDLE_MEASUREMENT,
        "interactionSweepCount": INTERACTION_SWEEP_COUNT,
        "aggregation": "median-of-fresh-processes",
        "attemptCount": RELEASE_ATTEMPT_COUNT,
        "requiredPassingAttemptCount": RELEASE_ATTEMPT_COUNT // 2 + 1,
        "withinBudget": True,
    }
    for field, expected in expected_identity.items():
        if evidence[field] != expected or type(evidence[field]) is not type(expected):
            raise VerificationError(f"performance evidence {field} is invalid")

    budgets = evidence["budgets"]
    expected_budgets = production_budgets()
    if not isinstance(budgets, dict):
        raise VerificationError("performance evidence budgets must be an object")
    require_keys(budgets, frozenset(expected_budgets), "performance budgets")
    for field, expected in expected_budgets.items():
        actual = finite_number(budgets[field], f"performance budgets {field}")
        if actual != expected:
            raise VerificationError(f"performance budgets {field} is not production policy")

    raw_attempts = evidence["attempts"]
    if not isinstance(raw_attempts, list) or len(raw_attempts) != RELEASE_ATTEMPT_COUNT:
        raise VerificationError(
            f"performance evidence must contain {RELEASE_ATTEMPT_COUNT} attempts"
        )
    attempts = [
        validate_attempt(raw_attempt, index)
        for index, raw_attempt in enumerate(raw_attempts, start=1)
    ]
    passing_attempts = sum(
        attempt.launch_ready_milliseconds <= DEFAULT_MAX_LAUNCH_READY_MILLISECONDS
        for attempt in attempts
    )
    required_passing = RELEASE_ATTEMPT_COUNT // 2 + 1
    if passing_attempts < required_passing:
        raise VerificationError("performance evidence misses the launch-ready majority")
    if integer(
        evidence["passingAttemptCount"],
        "performance evidence passingAttemptCount",
    ) != passing_attempts:
        raise VerificationError("performance evidence passingAttemptCount is inconsistent")

    selected_number = integer(
        evidence["selectedAttempt"],
        "performance evidence selectedAttempt",
    )
    if selected_number not in range(1, RELEASE_ATTEMPT_COUNT + 1):
        raise VerificationError("performance evidence selectedAttempt is invalid")
    selected = attempts[selected_number - 1]
    median_launch = sorted(
        attempt.launch_ready_milliseconds for attempt in attempts
    )[RELEASE_ATTEMPT_COUNT // 2]
    if selected.launch_ready_milliseconds != median_launch:
        raise VerificationError("performance evidence selectedAttempt is not the median launch")
    for field in SUMMARY_FIELDS:
        if (
            evidence[field] != selected.values[field]
            or type(evidence[field]) is not type(selected.values[field])
        ):
            raise VerificationError(
                f"performance evidence {field} disagrees with selectedAttempt"
            )


def verify_performance_evidence_asset(
    asset_directory: Path,
    assets: list[dict[str, Any]],
    manifest: dict[str, Any],
) -> None:
    performance_assets = {
        asset["arch"]: asset
        for asset in assets
        if asset["kind"] == "performance"
        and asset["platform"] == "macOS"
        and asset["install"] == "json"
    }
    matching_count = sum(
        asset["kind"] == "performance"
        and asset["platform"] == "macOS"
        and asset["install"] == "json"
        for asset in assets
    )
    if (
        matching_count != len(MACOS_ARCHITECTURES)
        or set(performance_assets) != set(MACOS_ARCHITECTURES)
    ):
        raise VerificationError(
            "release must contain one packaged performance asset per macOS architecture"
        )

    app_architectures = {
        asset["arch"] for asset in manifest["updater"]["macOSAppAssets"]
    }
    if app_architectures != set(MACOS_ARCHITECTURES):
        raise VerificationError("packaged performance assets disagree with the macOS apps")

    for architecture in MACOS_ARCHITECTURES:
        performance_asset = performance_assets[architecture]
        expected_name = f"Quill-Cowork-macOS-{architecture}-PERFORMANCE.json"
        expected_metadata = {
            "name": expected_name,
            "platform": "macOS",
            "arch": architecture,
            "install": "json",
        }
        for field, expected in expected_metadata.items():
            if performance_asset.get(field) == expected:
                continue
            raise VerificationError(
                f"packaged performance asset {field} disagrees with the macOS app"
            )

        path = asset_directory / expected_name
        try:
            if path.is_symlink() or not path.is_file():
                raise VerificationError("packaged performance evidence must be a regular file")
            if path.stat().st_size > PERFORMANCE_EVIDENCE_BYTE_LIMIT:
                raise VerificationError("packaged performance evidence exceeds its size limit")
            evidence_bytes = path.read_bytes()
        except VerificationError:
            raise
        except OSError as error:
            raise VerificationError(
                "packaged performance evidence could not be read"
            ) from error
        evidence = load_json_bytes(
            evidence_bytes,
            f"{architecture} packaged performance evidence",
        )
        validate_performance_evidence(evidence)
