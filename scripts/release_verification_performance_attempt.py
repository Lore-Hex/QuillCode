"""Validate one published packaged-performance attempt."""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from performance_evidence_contract import (
    DEFAULT_MAX_IDLE_CPU_PERCENT,
    DEFAULT_MAX_IDLE_RESIDENT_MEMORY_GROWTH_BYTES,
    DEFAULT_MAX_IDLE_THREAD_GROWTH,
    DEFAULT_MAX_LAUNCH_READY_MILLISECONDS,
    DEFAULT_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES,
    DEFAULT_MAX_REPEATED_THREAD_GROWTH,
    DEFAULT_MAX_RESIDENT_MEMORY_BYTES,
    DEFAULT_MAX_RESIDENT_MEMORY_GROWTH_BYTES,
    DEFAULT_MAX_THREAD_COUNT,
    MINIMUM_IDLE_DURATION_MILLISECONDS,
)
from release_verification_contract import VerificationError


MIB = 1024 * 1024
ATTEMPT_KEYS = frozenset(
    {
        "attempt",
        "idleCPUPercent",
        "idleDurationMilliseconds",
        "idleProcessorTimeMilliseconds",
        "idleProcessorTimeNanoseconds",
        "idleResidentMemoryBytes",
        "idleResidentMemoryGrowthBytes",
        "idleResidentMemoryGrowthMiB",
        "idleResidentMemoryMiB",
        "idleThreadCount",
        "idleThreadGrowth",
        "launchReadyMilliseconds",
        "postInteractionResidentMemoryBytes",
        "postInteractionResidentMemoryMiB",
        "postInteractionThreadCount",
        "repeatedInteractionResidentMemoryBytes",
        "repeatedInteractionResidentMemoryGrowthBytes",
        "repeatedInteractionResidentMemoryGrowthMiB",
        "repeatedInteractionResidentMemoryMiB",
        "repeatedInteractionThreadCount",
        "repeatedInteractionThreadGrowth",
        "residentMemoryBytes",
        "residentMemoryGrowthBytes",
        "residentMemoryGrowthMiB",
        "residentMemoryMiB",
        "threadCount",
        "threadGrowth",
        "withinLaunchBudget",
        "withinIdleCPUPercentBudget",
        "withinIdleResidentMemoryGrowthBudget",
        "withinIdleThreadGrowthBudget",
        "withinRepeatedResidentMemoryGrowthBudget",
        "withinRepeatedThreadGrowthBudget",
        "withinResidentMemoryBudget",
        "withinResidentMemoryGrowthBudget",
        "withinThreadCountBudget",
    }
)


@dataclass(frozen=True)
class ValidatedPerformanceAttempt:
    number: int
    launch_ready_milliseconds: float
    values: dict[str, Any]


def require_keys(
    value: dict[str, Any],
    expected: frozenset[str],
    label: str,
) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        raise VerificationError(
            f"{label} fields do not match schema "
            f"(missing={missing}, unexpected={unexpected})"
        )


def integer(value: Any, label: str) -> int:
    if type(value) is not int:
        raise VerificationError(f"{label} must be an integer")
    return value


def finite_number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise VerificationError(f"{label} must be numeric")
    number = float(value)
    if not math.isfinite(number):
        raise VerificationError(f"{label} must be finite")
    return number


def _positive_integer(value: Any, label: str) -> int:
    number = integer(value, label)
    if number <= 0:
        raise VerificationError(f"{label} must be positive")
    return number


def _nonnegative_integer(value: Any, label: str) -> int:
    number = integer(value, label)
    if number < 0:
        raise VerificationError(f"{label} must not be negative")
    return number


def _boolean(value: Any, label: str) -> bool:
    if type(value) is not bool:
        raise VerificationError(f"{label} must be a Boolean")
    return value


def _validate_mib(
    values: dict[str, Any],
    byte_field: str,
    mib_field: str,
    label: str,
) -> None:
    expected = round(integer(values[byte_field], f"{label} {byte_field}") / MIB, 2)
    actual = finite_number(values[mib_field], f"{label} {mib_field}")
    if actual != expected:
        raise VerificationError(f"{label} {mib_field} disagrees with its byte value")


def validate_attempt(
    raw_attempt: Any,
    expected_number: int,
) -> ValidatedPerformanceAttempt:
    label = f"performance attempt {expected_number}"
    if not isinstance(raw_attempt, dict):
        raise VerificationError(f"{label} must be an object")
    require_keys(raw_attempt, ATTEMPT_KEYS, label)
    if integer(raw_attempt["attempt"], f"{label} number") != expected_number:
        raise VerificationError(f"{label} has a noncanonical attempt number")

    launch = finite_number(
        raw_attempt["launchReadyMilliseconds"],
        f"{label} launchReadyMilliseconds",
    )
    if launch < 0:
        raise VerificationError(f"{label} launchReadyMilliseconds cannot be negative")

    resident = _positive_integer(
        raw_attempt["residentMemoryBytes"],
        f"{label} residentMemoryBytes",
    )
    post_resident = _positive_integer(
        raw_attempt["postInteractionResidentMemoryBytes"],
        f"{label} postInteractionResidentMemoryBytes",
    )
    repeated_resident = _positive_integer(
        raw_attempt["repeatedInteractionResidentMemoryBytes"],
        f"{label} repeatedInteractionResidentMemoryBytes",
    )
    idle_resident = _positive_integer(
        raw_attempt["idleResidentMemoryBytes"],
        f"{label} idleResidentMemoryBytes",
    )
    threads = _positive_integer(raw_attempt["threadCount"], f"{label} threadCount")
    post_threads = _positive_integer(
        raw_attempt["postInteractionThreadCount"],
        f"{label} postInteractionThreadCount",
    )
    repeated_threads = _positive_integer(
        raw_attempt["repeatedInteractionThreadCount"],
        f"{label} repeatedInteractionThreadCount",
    )
    idle_threads = _positive_integer(
        raw_attempt["idleThreadCount"],
        f"{label} idleThreadCount",
    )

    resident_growth = integer(
        raw_attempt["residentMemoryGrowthBytes"],
        f"{label} residentMemoryGrowthBytes",
    )
    thread_growth = integer(raw_attempt["threadGrowth"], f"{label} threadGrowth")
    repeated_resident_growth = integer(
        raw_attempt["repeatedInteractionResidentMemoryGrowthBytes"],
        f"{label} repeatedInteractionResidentMemoryGrowthBytes",
    )
    repeated_thread_growth = integer(
        raw_attempt["repeatedInteractionThreadGrowth"],
        f"{label} repeatedInteractionThreadGrowth",
    )
    idle_duration = finite_number(
        raw_attempt["idleDurationMilliseconds"],
        f"{label} idleDurationMilliseconds",
    )
    idle_processor_time = _nonnegative_integer(
        raw_attempt["idleProcessorTimeNanoseconds"],
        f"{label} idleProcessorTimeNanoseconds",
    )
    idle_processor_time_milliseconds = finite_number(
        raw_attempt["idleProcessorTimeMilliseconds"],
        f"{label} idleProcessorTimeMilliseconds",
    )
    idle_cpu_percent = finite_number(
        raw_attempt["idleCPUPercent"],
        f"{label} idleCPUPercent",
    )
    idle_resident_growth = integer(
        raw_attempt["idleResidentMemoryGrowthBytes"],
        f"{label} idleResidentMemoryGrowthBytes",
    )
    idle_thread_growth = integer(
        raw_attempt["idleThreadGrowth"],
        f"{label} idleThreadGrowth",
    )
    if resident_growth != post_resident - resident:
        raise VerificationError(f"{label} resident-memory delta is forged")
    if thread_growth != post_threads - threads:
        raise VerificationError(f"{label} thread delta is forged")
    if repeated_resident_growth != repeated_resident - post_resident:
        raise VerificationError(f"{label} repeated resident-memory delta is forged")
    if repeated_thread_growth != repeated_threads - post_threads:
        raise VerificationError(f"{label} repeated thread delta is forged")
    if idle_resident_growth != idle_resident - repeated_resident:
        raise VerificationError(f"{label} idle resident-memory delta is forged")
    if idle_thread_growth != idle_threads - repeated_threads:
        raise VerificationError(f"{label} idle thread delta is forged")
    if idle_duration < MINIMUM_IDLE_DURATION_MILLISECONDS:
        raise VerificationError(f"{label} idle duration is too short")
    if idle_cpu_percent < 0:
        raise VerificationError(f"{label} idle CPU percent cannot be negative")
    expected_idle_processor_time_milliseconds = round(idle_processor_time / 1_000_000, 2)
    if idle_processor_time_milliseconds != expected_idle_processor_time_milliseconds:
        raise VerificationError(f"{label} idle processor-time milliseconds is forged")
    expected_idle_cpu_percent = (
        idle_processor_time / 1_000_000_000 / (idle_duration / 1_000) * 100
    )
    if not math.isclose(idle_cpu_percent, expected_idle_cpu_percent, abs_tol=0.0001):
        raise VerificationError(f"{label} idle CPU percent is forged")

    for byte_field, mib_field in (
        ("residentMemoryBytes", "residentMemoryMiB"),
        ("postInteractionResidentMemoryBytes", "postInteractionResidentMemoryMiB"),
        (
            "repeatedInteractionResidentMemoryBytes",
            "repeatedInteractionResidentMemoryMiB",
        ),
        ("residentMemoryGrowthBytes", "residentMemoryGrowthMiB"),
        (
            "repeatedInteractionResidentMemoryGrowthBytes",
            "repeatedInteractionResidentMemoryGrowthMiB",
        ),
        ("idleResidentMemoryBytes", "idleResidentMemoryMiB"),
        ("idleResidentMemoryGrowthBytes", "idleResidentMemoryGrowthMiB"),
    ):
        _validate_mib(raw_attempt, byte_field, mib_field, label)

    within_launch = launch <= DEFAULT_MAX_LAUNCH_READY_MILLISECONDS
    within_memory = max(resident, post_resident, repeated_resident, idle_resident) <= (
        DEFAULT_MAX_RESIDENT_MEMORY_BYTES
    )
    within_growth = resident_growth <= DEFAULT_MAX_RESIDENT_MEMORY_GROWTH_BYTES
    within_repeated_growth = repeated_resident_growth <= (
        DEFAULT_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES
    )
    within_threads = max(threads, post_threads, repeated_threads, idle_threads) <= (
        DEFAULT_MAX_THREAD_COUNT
    )
    within_repeated_thread_growth = (
        repeated_thread_growth <= DEFAULT_MAX_REPEATED_THREAD_GROWTH
    )
    within_idle_cpu = idle_cpu_percent <= DEFAULT_MAX_IDLE_CPU_PERCENT
    within_idle_resident_growth = (
        idle_resident_growth <= DEFAULT_MAX_IDLE_RESIDENT_MEMORY_GROWTH_BYTES
    )
    within_idle_thread_growth = idle_thread_growth <= DEFAULT_MAX_IDLE_THREAD_GROWTH

    resource_checks = (
        (within_memory, "resident-memory"),
        (within_growth, "resident-memory growth"),
        (within_repeated_growth, "repeated resident-memory growth"),
        (within_threads, "thread-count"),
        (within_repeated_thread_growth, "repeated thread-growth"),
        (within_idle_cpu, "idle CPU"),
        (within_idle_resident_growth, "idle resident-memory growth"),
        (within_idle_thread_growth, "idle thread-growth"),
    )
    for passed, budget_name in resource_checks:
        if not passed:
            raise VerificationError(f"{label} violates the {budget_name} budget")

    expected_flags = {
        "withinLaunchBudget": within_launch,
        "withinResidentMemoryBudget": within_memory,
        "withinResidentMemoryGrowthBudget": within_growth,
        "withinRepeatedResidentMemoryGrowthBudget": within_repeated_growth,
        "withinThreadCountBudget": within_threads,
        "withinRepeatedThreadGrowthBudget": within_repeated_thread_growth,
        "withinIdleCPUPercentBudget": within_idle_cpu,
        "withinIdleResidentMemoryGrowthBudget": within_idle_resident_growth,
        "withinIdleThreadGrowthBudget": within_idle_thread_growth,
    }
    for field, expected in expected_flags.items():
        if _boolean(raw_attempt[field], f"{label} {field}") is not expected:
            raise VerificationError(f"{label} {field} is inconsistent")

    return ValidatedPerformanceAttempt(
        number=expected_number,
        launch_ready_milliseconds=launch,
        values=raw_attempt,
    )
