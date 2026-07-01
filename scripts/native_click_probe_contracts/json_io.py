"""JSON loading and primitive validation helpers for native smoke reports."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

def load_json_object(path: Path, label: str) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as json_file:
        value = json.load(json_file)
    if not isinstance(value, dict):
        raise SystemExit(f"{label} at {path} did not contain a JSON object")
    return value

def load_report(path: Path) -> dict[str, Any]:
    return load_json_object(path, "native smoke report")

def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)

def relative_manifest_path(path: Path, base_directory: Path) -> str:
    try:
        return str(path.resolve().relative_to(base_directory.resolve()))
    except ValueError:
        return str(path)

def numeric_value(value: Any, label: str) -> float:
    if not isinstance(value, (int, float)):
        raise SystemExit(f"{label} is not numeric: {value!r}")
    return float(value)

def string_list(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise SystemExit(f"{label} is not a list of strings")
    return value

def required_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"{label} is not a nonempty string: {value!r}")
    return value
