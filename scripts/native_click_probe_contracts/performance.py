"""Validate packaged native launch and resident-memory evidence."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

from .json_io import load_report, require


DEFAULT_MAX_LAUNCH_READY_MILLISECONDS = 3_000.0
DEFAULT_MAX_RESIDENT_MEMORY_BYTES = 256 * 1024 * 1024


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


def write_performance_manifest(
    report_path: Path,
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
    require(
        launch_ready <= max_launch,
        f"packaged launch-ready time {launch_ready:.2f}ms exceeds {max_launch:.2f}ms budget",
    )
    require(
        resident <= max_resident,
        f"packaged resident memory {resident} bytes exceeds {max_resident} byte budget",
    )

    manifest = {
        "schemaVersion": 1,
        "ok": True,
        "product": "Quill Cowork",
        "measurement": "initial-live-window",
        "launchReadyMilliseconds": launch_ready,
        "residentMemoryBytes": resident,
        "residentMemoryMiB": round(resident / (1024 * 1024), 2),
        "threadCount": thread_count,
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
        f"{launch_ready:.2f}ms launch-ready, {manifest['residentMemoryMiB']:.2f} MiB resident."
    )
