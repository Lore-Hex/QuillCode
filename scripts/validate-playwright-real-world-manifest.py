#!/usr/bin/env python3
"""Validate Playwright real-world action release evidence."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


REQUIRED_SCENARIOS = {
    "runs natural shell requests immediately with nonempty arguments",
    "writes requested file content immediately without a confirmation loop",
    "answers device diagnostic prompts with concrete shell actions",
    "downloads requested domains with a bounded concrete shell action",
    "answers natural git read requests with structured git tools",
    "respects explicit negative action prompts without tool cards or side effects",
}

REQUIRED_PROMPT_FRAGMENTS = [
    "whoami?",
    "Run `ls`",
    "quillcode_now_smoke",
    "quillcode_polite_smoke",
    "Can you write a file that says",
    "How much hd?",
    "Do you have openclaw?",
    "Can you download LinkedIn.com?",
    "Please check git status.",
    "what changed?",
    "Do not run whoami.",
    "forbidden.txt",
    "downloads/forbidden.html",
]

REQUIRED_REGRESSION_GUARDS = [
    "shell arguments are never {}",
    "assistant does not answer with passive promises",
    "assistant does not ask for a second confirmation",
    "safety review does not block clear user intent",
    "git status uses host.git.status instead of shell fallback",
    "negative shell intent creates no tool card",
]

MIN_PROMPT_COUNT = 15
MIN_REGRESSION_GUARD_COUNT = 18


def string_items(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("manifest root must be a JSON object")
    return data


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    scenarios = manifest.get("scenarios")
    if not isinstance(scenarios, list):
        return ["scenarios must be a list"]

    scenario_names = {
        scenario.get("name")
        for scenario in scenarios
        if isinstance(scenario, dict)
    }
    missing_scenarios = sorted(REQUIRED_SCENARIOS - scenario_names)
    if missing_scenarios:
        errors.append(f"missing scenarios: {missing_scenarios}")

    scenario_count = manifest.get("scenarioCount")
    prompt_count = manifest.get("promptCount")
    regression_guard_count = manifest.get("regressionGuardCount")
    if scenario_count != len(scenarios) or scenario_count < len(REQUIRED_SCENARIOS):
        errors.append(
            "scenarioCount should match at least "
            f"{len(REQUIRED_SCENARIOS)} scenarios, got {scenario_count!r}"
        )
    if not isinstance(prompt_count, int) or prompt_count < MIN_PROMPT_COUNT:
        errors.append(
            "promptCount should cover at least "
            f"{MIN_PROMPT_COUNT} prompts, got {prompt_count!r}"
        )
    if (
        not isinstance(regression_guard_count, int)
        or regression_guard_count < MIN_REGRESSION_GUARD_COUNT
    ):
        errors.append(
            f"regressionGuardCount should cover at least {MIN_REGRESSION_GUARD_COUNT} guards, "
            f"got {regression_guard_count!r}"
        )

    all_prompts = "\n".join(
        prompt
        for scenario in scenarios
        if isinstance(scenario, dict)
        for prompt in string_items(scenario.get("prompts"))
    )
    for required_prompt in REQUIRED_PROMPT_FRAGMENTS:
        if required_prompt not in all_prompts:
            errors.append(f"missing prompt coverage for {required_prompt!r}")

    all_guards = "\n".join(
        guard
        for scenario in scenarios
        if isinstance(scenario, dict)
        for guard in string_items(scenario.get("regressionGuards"))
    )
    for required_guard in REQUIRED_REGRESSION_GUARDS:
        if required_guard not in all_guards:
            errors.append(f"missing regression guard {required_guard!r}")

    return errors


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: validate-playwright-real-world-manifest.py MANIFEST", file=sys.stderr)
        return 2

    manifest_path = Path(argv[1])
    if not manifest_path.is_file():
        print(
            f"Playwright real-world action evidence manifest is missing: {manifest_path}",
            file=sys.stderr,
        )
        return 1

    try:
        manifest = load_manifest(manifest_path)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"Invalid Playwright real-world action evidence manifest: {error}", file=sys.stderr)
        return 1

    errors = validate_manifest(manifest)
    if errors:
        print("Invalid Playwright real-world action evidence manifest:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
