"""Validate packaged native launch and resident-memory evidence."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from .json_io import load_report, require


DEFAULT_MAX_LAUNCH_READY_MILLISECONDS = 3_000.0
DEFAULT_MAX_RESIDENT_MEMORY_BYTES = 256 * 1024 * 1024


@dataclass(frozen=True)
class PerformanceAttempt:
    launch_ready_milliseconds: float
    resident_memory_bytes: int
    thread_count: int


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


def _load_attempt(report_path: Path) -> PerformanceAttempt:
    report = load_report(report_path)
    require(report.get("ok") is True, f"{report_path} does not report ok=true")
    require(report.get("appName") == "Quill Cowork", f"{report_path} has the wrong app identity")
    performance = report.get("performance")
    require(isinstance(performance, dict), f"{report_path} is missing performance evidence")
    require(performance.get("schemaVersion") == 1, "unsupported performance evidence schema")
    require(
        performance.get("measurement") == "initial-live-window",
        "unexpected performance measurement boundary",
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
    require(launch_ready >= 0, "performance.launchReadyMilliseconds cannot be negative")
    return PerformanceAttempt(
        launch_ready_milliseconds=launch_ready,
        resident_memory_bytes=resident,
        thread_count=thread_count,
    )


def write_performance_manifest(
    report_paths: Sequence[Path],
    manifest_path: Path,
    *,
    max_launch_ready_milliseconds: float = DEFAULT_MAX_LAUNCH_READY_MILLISECONDS,
    max_resident_memory_bytes: int = DEFAULT_MAX_RESIDENT_MEMORY_BYTES,
) -> None:
    max_launch = _finite_number(
        max_launch_ready_milliseconds,
        "maximum launch-ready milliseconds",
    )
    max_resident = _positive_integer(
        max_resident_memory_bytes,
        "maximum resident-memory bytes",
    )
    require(max_launch > 0, "maximum launch-ready milliseconds must be positive")
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
            f"packaged resident memory {attempt.resident_memory_bytes} bytes "
            f"exceeds {max_resident} byte budget",
        )

    selected_attempt = sorted(
        attempts,
        key=lambda attempt: attempt.launch_ready_milliseconds,
    )[len(attempts) // 2]
    selected_attempt_number = attempts.index(selected_attempt) + 1
    launch_ready = selected_attempt.launch_ready_milliseconds
    resident = selected_attempt.resident_memory_bytes
    thread_count = selected_attempt.thread_count

    manifest = {
        "schemaVersion": 1,
        "ok": True,
        "product": "Quill Cowork",
        "measurement": "initial-live-window",
        "launchReadyMilliseconds": launch_ready,
        "residentMemoryBytes": resident,
        "residentMemoryMiB": round(resident / (1024 * 1024), 2),
        "threadCount": thread_count,
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
                "withinLaunchBudget": attempt.launch_ready_milliseconds <= max_launch,
                "withinResidentMemoryBudget": attempt.resident_memory_bytes <= max_resident,
            }
            for index, attempt in enumerate(attempts, start=1)
        ],
        "budgets": {
            "maximumLaunchReadyMilliseconds": max_launch,
            "maximumResidentMemoryBytes": max_resident,
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
        f"{manifest['residentMemoryMiB']:.2f} MiB resident "
        f"({passing_attempts}/{len(attempts)} launches within budget)."
    )
