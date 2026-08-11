"""Canonical schema and production budgets for packaged performance evidence."""

from __future__ import annotations


PERFORMANCE_SCHEMA_VERSION = 4
PERFORMANCE_PRODUCT = "Quill Cowork"
PERFORMANCE_WORKLOAD = "daily-driver-100-chats"
INITIAL_MEASUREMENT = "initial-live-window"
POST_INTERACTION_MEASUREMENT = "settled-after-native-interaction-sweep"
REPEATED_INTERACTION_MEASUREMENT = (
    "settled-after-repeated-native-interaction-sweep"
)
INTERACTION_SWEEP_COUNT = 2
RELEASE_ATTEMPT_COUNT = 3

DEFAULT_MAX_LAUNCH_READY_MILLISECONDS = 3_000.0
DEFAULT_MAX_RESIDENT_MEMORY_BYTES = 256 * 1024 * 1024
DEFAULT_MAX_RESIDENT_MEMORY_GROWTH_BYTES = 80 * 1024 * 1024
DEFAULT_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES = 16 * 1024 * 1024
DEFAULT_MAX_THREAD_COUNT = 64
DEFAULT_MAX_REPEATED_THREAD_GROWTH = 4


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
    }
