"""Canonical schema and production budgets for packaged performance evidence."""

from __future__ import annotations


PERFORMANCE_SCHEMA_VERSION = 6
PERFORMANCE_PRODUCT = "Quill Cowork"
PERFORMANCE_WORKLOAD = "daily-driver-100-chats"
MEMORY_MEASUREMENT = "physical-footprint"
PROCESSOR_TIME_MEASUREMENT = "process-user-plus-system-nanoseconds"
INITIAL_MEASUREMENT = "initial-live-window"
POST_INTERACTION_MEASUREMENT = "settled-after-native-interaction-sweep"
REPEATED_INTERACTION_MEASUREMENT = (
    "settled-after-repeated-native-interaction-sweep"
)
IDLE_MEASUREMENT = "settled-idle-after-interaction-sweeps"
MINIMUM_IDLE_DURATION_MILLISECONDS = 2_000.0
INTERACTION_SWEEP_COUNT = 2
RELEASE_ATTEMPT_COUNT = 3

DEFAULT_MAX_LAUNCH_READY_MILLISECONDS = 2_500.0
DEFAULT_MAX_RESIDENT_MEMORY_BYTES = 128 * 1024 * 1024
DEFAULT_MAX_RESIDENT_MEMORY_GROWTH_BYTES = 64 * 1024 * 1024
DEFAULT_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES = 12 * 1024 * 1024
DEFAULT_MAX_THREAD_COUNT = 32
DEFAULT_MAX_REPEATED_THREAD_GROWTH = 2
DEFAULT_MAX_IDLE_CPU_PERCENT = 5.0
DEFAULT_MAX_IDLE_RESIDENT_MEMORY_GROWTH_BYTES = 8 * 1024 * 1024
DEFAULT_MAX_IDLE_THREAD_GROWTH = 2


def production_budgets() -> dict[str, int | float]:
    return {
        "maximumLaunchReadyMilliseconds": DEFAULT_MAX_LAUNCH_READY_MILLISECONDS,
        "maximumResidentMemoryBytes": DEFAULT_MAX_RESIDENT_MEMORY_BYTES,
        "maximumResidentMemoryGrowthBytes": DEFAULT_MAX_RESIDENT_MEMORY_GROWTH_BYTES,
        "maximumRepeatedResidentMemoryGrowthBytes": (
            DEFAULT_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES
        ),
        "maximumThreadCount": DEFAULT_MAX_THREAD_COUNT,
        "maximumRepeatedThreadGrowth": DEFAULT_MAX_REPEATED_THREAD_GROWTH,
        "maximumIdleCPUPercent": DEFAULT_MAX_IDLE_CPU_PERCENT,
        "maximumIdleResidentMemoryGrowthBytes": (
            DEFAULT_MAX_IDLE_RESIDENT_MEMORY_GROWTH_BYTES
        ),
        "maximumIdleThreadGrowth": DEFAULT_MAX_IDLE_THREAD_GROWTH,
    }
