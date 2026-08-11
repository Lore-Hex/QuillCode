"""Validate packaged native launch and physical-footprint evidence."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from performance_evidence_contract import (
    DEFAULT_MAX_LAUNCH_READY_MILLISECONDS,
    DEFAULT_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES,
    DEFAULT_MAX_REPEATED_THREAD_GROWTH,
    DEFAULT_MAX_RESIDENT_MEMORY_BYTES,
    DEFAULT_MAX_RESIDENT_MEMORY_GROWTH_BYTES,
    DEFAULT_MAX_THREAD_COUNT,
    INITIAL_MEASUREMENT,
    INTERACTION_SWEEP_COUNT,
    MEMORY_MEASUREMENT,
    PERFORMANCE_PRODUCT,
    PERFORMANCE_SCHEMA_VERSION,
    PERFORMANCE_WORKLOAD,
    POST_INTERACTION_MEASUREMENT,
    REPEATED_INTERACTION_MEASUREMENT,
)

from .json_io import load_report, require


@dataclass(frozen=True)
class PerformanceAttempt:
    launch_ready_milliseconds: float
    resident_memory_bytes: int
    thread_count: int
    post_interaction_resident_memory_bytes: int
    post_interaction_thread_count: int
    repeated_interaction_resident_memory_bytes: int
    repeated_interaction_thread_count: int

    @property
    def resident_memory_growth_bytes(self) -> int:
        return self.post_interaction_resident_memory_bytes - self.resident_memory_bytes

    @property
    def thread_growth(self) -> int:
        return self.post_interaction_thread_count - self.thread_count

    @property
    def repeated_interaction_resident_memory_growth_bytes(self) -> int:
        return (
            self.repeated_interaction_resident_memory_bytes
            - self.post_interaction_resident_memory_bytes
        )

    @property
    def repeated_interaction_thread_growth(self) -> int:
        return self.repeated_interaction_thread_count - self.post_interaction_thread_count


def _finite_number(value: Any, label: str) -> float:
    require(
        not isinstance(value, bool) and isinstance(value, (int, float)),
        f"{label} is not numeric: {value!r}",
    )
    number = float(value)
    require(math.isfinite(number), f"{label} is not finite: {value!r}")
    return number


def _positive_integer(value: Any, label: str) -> int:
    require(
        not isinstance(value, bool) and isinstance(value, int) and value > 0,
        f"{label} is not a positive integer: {value!r}",
    )
    return value


def _integer(value: Any, label: str) -> int:
    require(
        not isinstance(value, bool) and isinstance(value, int),
        f"{label} is not an integer: {value!r}",
    )
    return value


def _load_attempt(report_path: Path) -> PerformanceAttempt:
    report = load_report(report_path)
    require(report.get("ok") is True, f"{report_path} does not report ok=true")
    require(report.get("appName") == PERFORMANCE_PRODUCT, f"{report_path} has the wrong app identity")
    performance = report.get("performance")
    require(isinstance(performance, dict), f"{report_path} is missing performance evidence")
    require(
        performance.get("schemaVersion") == PERFORMANCE_SCHEMA_VERSION,
        "unsupported performance evidence schema",
    )
    require(
        performance.get("workload") == PERFORMANCE_WORKLOAD,
        "unexpected packaged performance workload",
    )
    require(
        performance.get("measurement") == INITIAL_MEASUREMENT,
        "unexpected performance measurement boundary",
    )
    require(
        performance.get("memoryMeasurement") == MEMORY_MEASUREMENT,
        "unexpected performance memory measurement",
    )

    launch_ready = _finite_number(
        performance.get("launchReadyMilliseconds"),
        "performance.launchReadyMilliseconds",
    )
    resident = _positive_integer(
        performance.get("residentMemoryBytes"),
        "performance.residentMemoryBytes",
    )
    thread_count = _positive_integer(
        performance.get("threadCount"),
        "performance.threadCount",
    )
    require(
        performance.get("postInteractionMeasurement")
        == POST_INTERACTION_MEASUREMENT,
        "unexpected post-interaction performance measurement boundary",
    )
    post_interaction_resident = _positive_integer(
        performance.get("postInteractionResidentMemoryBytes"),
        "performance.postInteractionResidentMemoryBytes",
    )
    post_interaction_thread_count = _positive_integer(
        performance.get("postInteractionThreadCount"),
        "performance.postInteractionThreadCount",
    )
    reported_memory_growth = _integer(
        performance.get("residentMemoryGrowthBytes"),
        "performance.residentMemoryGrowthBytes",
    )
    reported_thread_growth = _integer(
        performance.get("threadGrowth"),
        "performance.threadGrowth",
    )
    require(
        performance.get("repeatedInteractionMeasurement")
        == REPEATED_INTERACTION_MEASUREMENT,
        "unexpected repeated-interaction performance measurement boundary",
    )
    require(
        performance.get("interactionSweepCount") == INTERACTION_SWEEP_COUNT,
        "performance evidence must contain exactly two native interaction sweeps",
    )
    repeated_interaction_resident = _positive_integer(
        performance.get("repeatedInteractionResidentMemoryBytes"),
        "performance.repeatedInteractionResidentMemoryBytes",
    )
    repeated_interaction_thread_count = _positive_integer(
        performance.get("repeatedInteractionThreadCount"),
        "performance.repeatedInteractionThreadCount",
    )
    reported_repeated_memory_growth = _integer(
        performance.get("repeatedInteractionResidentMemoryGrowthBytes"),
        "performance.repeatedInteractionResidentMemoryGrowthBytes",
    )
    reported_repeated_thread_growth = _integer(
        performance.get("repeatedInteractionThreadGrowth"),
        "performance.repeatedInteractionThreadGrowth",
    )
    require(
        reported_memory_growth == post_interaction_resident - resident,
        "performance resident-memory growth does not match its snapshots",
    )
    require(
        reported_thread_growth == post_interaction_thread_count - thread_count,
        "performance thread growth does not match its snapshots",
    )
    require(
        reported_repeated_memory_growth
        == repeated_interaction_resident - post_interaction_resident,
        "performance repeated resident-memory growth does not match its snapshots",
    )
    require(
        reported_repeated_thread_growth
        == repeated_interaction_thread_count - post_interaction_thread_count,
        "performance repeated thread growth does not match its snapshots",
    )
    require(launch_ready >= 0, "performance.launchReadyMilliseconds cannot be negative")
    return PerformanceAttempt(
        launch_ready_milliseconds=launch_ready,
        resident_memory_bytes=resident,
        thread_count=thread_count,
        post_interaction_resident_memory_bytes=post_interaction_resident,
        post_interaction_thread_count=post_interaction_thread_count,
        repeated_interaction_resident_memory_bytes=repeated_interaction_resident,
        repeated_interaction_thread_count=repeated_interaction_thread_count,
    )


def write_performance_manifest(
    report_paths: Sequence[Path],
    manifest_path: Path,
    *,
    max_launch_ready_milliseconds: float = DEFAULT_MAX_LAUNCH_READY_MILLISECONDS,
    max_resident_memory_bytes: int = DEFAULT_MAX_RESIDENT_MEMORY_BYTES,
    max_resident_memory_growth_bytes: int = DEFAULT_MAX_RESIDENT_MEMORY_GROWTH_BYTES,
    max_repeated_resident_memory_growth_bytes: int = (
        DEFAULT_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES
    ),
    max_thread_count: int = DEFAULT_MAX_THREAD_COUNT,
    max_repeated_thread_growth: int = DEFAULT_MAX_REPEATED_THREAD_GROWTH,
) -> None:
    max_launch = _finite_number(
        max_launch_ready_milliseconds,
        "maximum launch-ready milliseconds",
    )
    max_resident = _positive_integer(
        max_resident_memory_bytes,
        "maximum resident-memory bytes",
    )
    max_resident_growth = _positive_integer(
        max_resident_memory_growth_bytes,
        "maximum resident-memory growth bytes",
    )
    max_repeated_resident_growth = _positive_integer(
        max_repeated_resident_memory_growth_bytes,
        "maximum repeated resident-memory growth bytes",
    )
    maximum_threads = _positive_integer(max_thread_count, "maximum thread count")
    maximum_repeated_thread_growth = _integer(
        max_repeated_thread_growth,
        "maximum repeated thread growth",
    )
    require(max_launch > 0, "maximum launch-ready milliseconds must be positive")
    require(
        maximum_repeated_thread_growth >= 0,
        "maximum repeated thread growth cannot be negative",
    )
    require(report_paths, "at least one packaged performance report is required")

    attempts = [_load_attempt(path) for path in report_paths]
    required_passing_attempts = len(attempts) // 2 + 1
    passing_attempts = sum(
        attempt.launch_ready_milliseconds <= max_launch for attempt in attempts
    )
    if len(attempts) == 1:
        require(
            passing_attempts == 1,
            f"packaged launch-ready time {attempts[0].launch_ready_milliseconds:.2f}ms "
            f"exceeds {max_launch:.2f}ms budget",
        )
    else:
        launch_measurements = ", ".join(
            f"{attempt.launch_ready_milliseconds:.2f}ms" for attempt in attempts
        )
        require(
            passing_attempts >= required_passing_attempts,
            f"only {passing_attempts} of {len(attempts)} packaged launches met the "
            f"{max_launch:.2f}ms budget; {required_passing_attempts} required "
            f"({launch_measurements})",
        )

    for attempt in attempts:
        require(
            attempt.resident_memory_bytes <= max_resident,
            f"packaged initial resident memory {attempt.resident_memory_bytes} bytes "
            f"exceeds {max_resident} byte budget",
        )
        require(
            attempt.post_interaction_resident_memory_bytes <= max_resident,
            "packaged post-interaction resident memory "
            f"{attempt.post_interaction_resident_memory_bytes} bytes exceeds "
            f"{max_resident} byte budget",
        )
        require(
            attempt.repeated_interaction_resident_memory_bytes <= max_resident,
            "packaged repeated-interaction resident memory "
            f"{attempt.repeated_interaction_resident_memory_bytes} bytes exceeds "
            f"{max_resident} byte budget",
        )
        require(
            attempt.resident_memory_growth_bytes <= max_resident_growth,
            f"packaged retained resident-memory growth "
            f"{attempt.resident_memory_growth_bytes} bytes exceeds "
            f"{max_resident_growth} byte budget",
        )
        require(
            attempt.repeated_interaction_resident_memory_growth_bytes
            <= max_repeated_resident_growth,
            "packaged repeated-interaction retained resident-memory growth "
            f"{attempt.repeated_interaction_resident_memory_growth_bytes} bytes exceeds "
            f"{max_repeated_resident_growth} byte budget",
        )
        require(
            attempt.thread_count <= maximum_threads,
            f"packaged initial thread count {attempt.thread_count} exceeds "
            f"{maximum_threads} thread budget",
        )
        require(
            attempt.post_interaction_thread_count <= maximum_threads,
            "packaged post-interaction thread count "
            f"{attempt.post_interaction_thread_count} exceeds "
            f"{maximum_threads} thread budget",
        )
        require(
            attempt.repeated_interaction_thread_count <= maximum_threads,
            "packaged repeated-interaction thread count "
            f"{attempt.repeated_interaction_thread_count} exceeds "
            f"{maximum_threads} thread budget",
        )
        require(
            attempt.repeated_interaction_thread_growth <= maximum_repeated_thread_growth,
            "packaged repeated-interaction thread growth "
            f"{attempt.repeated_interaction_thread_growth} exceeds "
            f"{maximum_repeated_thread_growth} thread budget",
        )

    selected_attempt = sorted(
        attempts,
        key=lambda attempt: attempt.launch_ready_milliseconds,
    )[len(attempts) // 2]
    selected_attempt_number = attempts.index(selected_attempt) + 1
    launch_ready = selected_attempt.launch_ready_milliseconds
    resident = selected_attempt.resident_memory_bytes
    thread_count = selected_attempt.thread_count
    post_interaction_resident = selected_attempt.post_interaction_resident_memory_bytes
    post_interaction_thread_count = selected_attempt.post_interaction_thread_count
    repeated_interaction_resident = selected_attempt.repeated_interaction_resident_memory_bytes
    repeated_interaction_thread_count = selected_attempt.repeated_interaction_thread_count
    resident_growth = selected_attempt.resident_memory_growth_bytes
    thread_growth = selected_attempt.thread_growth
    repeated_resident_growth = selected_attempt.repeated_interaction_resident_memory_growth_bytes
    repeated_thread_growth = selected_attempt.repeated_interaction_thread_growth

    manifest = {
        "schemaVersion": PERFORMANCE_SCHEMA_VERSION,
        "ok": True,
        "product": PERFORMANCE_PRODUCT,
        "workload": PERFORMANCE_WORKLOAD,
        "measurement": INITIAL_MEASUREMENT,
        "memoryMeasurement": MEMORY_MEASUREMENT,
        "postInteractionMeasurement": POST_INTERACTION_MEASUREMENT,
        "launchReadyMilliseconds": launch_ready,
        "residentMemoryBytes": resident,
        "residentMemoryMiB": round(resident / (1024 * 1024), 2),
        "threadCount": thread_count,
        "postInteractionResidentMemoryBytes": post_interaction_resident,
        "postInteractionResidentMemoryMiB": round(
            post_interaction_resident / (1024 * 1024),
            2,
        ),
        "postInteractionThreadCount": post_interaction_thread_count,
        "residentMemoryGrowthBytes": resident_growth,
        "residentMemoryGrowthMiB": round(resident_growth / (1024 * 1024), 2),
        "threadGrowth": thread_growth,
        "repeatedInteractionMeasurement": REPEATED_INTERACTION_MEASUREMENT,
        "interactionSweepCount": INTERACTION_SWEEP_COUNT,
        "repeatedInteractionResidentMemoryBytes": repeated_interaction_resident,
        "repeatedInteractionResidentMemoryMiB": round(
            repeated_interaction_resident / (1024 * 1024),
            2,
        ),
        "repeatedInteractionThreadCount": repeated_interaction_thread_count,
        "repeatedInteractionResidentMemoryGrowthBytes": repeated_resident_growth,
        "repeatedInteractionResidentMemoryGrowthMiB": round(
            repeated_resident_growth / (1024 * 1024),
            2,
        ),
        "repeatedInteractionThreadGrowth": repeated_thread_growth,
        "aggregation": "single-attempt" if len(attempts) == 1 else "median-of-fresh-processes",
        "attemptCount": len(attempts),
        "selectedAttempt": selected_attempt_number,
        "passingAttemptCount": passing_attempts,
        "requiredPassingAttemptCount": required_passing_attempts,
        "attempts": [
            {
                "attempt": index,
                "launchReadyMilliseconds": attempt.launch_ready_milliseconds,
                "residentMemoryBytes": attempt.resident_memory_bytes,
                "residentMemoryMiB": round(attempt.resident_memory_bytes / (1024 * 1024), 2),
                "threadCount": attempt.thread_count,
                "postInteractionResidentMemoryBytes": attempt.post_interaction_resident_memory_bytes,
                "postInteractionResidentMemoryMiB": round(
                    attempt.post_interaction_resident_memory_bytes / (1024 * 1024),
                    2,
                ),
                "postInteractionThreadCount": attempt.post_interaction_thread_count,
                "residentMemoryGrowthBytes": attempt.resident_memory_growth_bytes,
                "residentMemoryGrowthMiB": round(
                    attempt.resident_memory_growth_bytes / (1024 * 1024),
                    2,
                ),
                "threadGrowth": attempt.thread_growth,
                "repeatedInteractionResidentMemoryBytes": (
                    attempt.repeated_interaction_resident_memory_bytes
                ),
                "repeatedInteractionResidentMemoryMiB": round(
                    attempt.repeated_interaction_resident_memory_bytes / (1024 * 1024),
                    2,
                ),
                "repeatedInteractionThreadCount": attempt.repeated_interaction_thread_count,
                "repeatedInteractionResidentMemoryGrowthBytes": (
                    attempt.repeated_interaction_resident_memory_growth_bytes
                ),
                "repeatedInteractionResidentMemoryGrowthMiB": round(
                    attempt.repeated_interaction_resident_memory_growth_bytes / (1024 * 1024),
                    2,
                ),
                "repeatedInteractionThreadGrowth": attempt.repeated_interaction_thread_growth,
                "withinLaunchBudget": attempt.launch_ready_milliseconds <= max_launch,
                "withinResidentMemoryBudget": (
                    attempt.resident_memory_bytes <= max_resident
                    and attempt.post_interaction_resident_memory_bytes <= max_resident
                    and attempt.repeated_interaction_resident_memory_bytes <= max_resident
                ),
                "withinResidentMemoryGrowthBudget": (
                    attempt.resident_memory_growth_bytes <= max_resident_growth
                ),
                "withinRepeatedResidentMemoryGrowthBudget": (
                    attempt.repeated_interaction_resident_memory_growth_bytes
                    <= max_repeated_resident_growth
                ),
                "withinThreadCountBudget": (
                    attempt.thread_count <= maximum_threads
                    and attempt.post_interaction_thread_count <= maximum_threads
                    and attempt.repeated_interaction_thread_count <= maximum_threads
                ),
                "withinRepeatedThreadGrowthBudget": (
                    attempt.repeated_interaction_thread_growth
                    <= maximum_repeated_thread_growth
                ),
            }
            for index, attempt in enumerate(attempts, start=1)
        ],
        "budgets": {
            "maximumLaunchReadyMilliseconds": max_launch,
            "maximumResidentMemoryBytes": max_resident,
            "maximumResidentMemoryGrowthBytes": max_resident_growth,
            "maximumRepeatedResidentMemoryGrowthBytes": max_repeated_resident_growth,
            "maximumThreadCount": maximum_threads,
            "maximumRepeatedThreadGrowth": maximum_repeated_thread_growth,
        },
        "withinBudget": True,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("w", encoding="utf-8") as manifest_file:
        json.dump(manifest, manifest_file, indent=2, sort_keys=True)
        manifest_file.write("\n")

    print(
        "Quill Cowork packaged performance passed: "
        f"{launch_ready:.2f}ms median launch-ready, "
        f"{manifest['residentMemoryMiB']:.2f} MiB initial and "
        f"{manifest['postInteractionResidentMemoryMiB']:.2f} MiB post-interaction "
        f"and {manifest['repeatedInteractionResidentMemoryMiB']:.2f} MiB repeated "
        f"({passing_attempts}/{len(attempts)} launches within budget)."
    )
