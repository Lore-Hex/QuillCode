"""Summarize row-level office coworker catalog evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, relative_manifest_path, require
from .live_saas import CATALOG_SPREADSHEET_URL, CATALOG_TASK_ID_MAX, CATALOG_TASK_ID_MIN


def _require_catalog_task_ids(value: Any, label: str) -> list[int]:
    require(isinstance(value, list) and value, f"{label} must be a non-empty list")
    task_ids: list[int] = []
    for index, item in enumerate(value):
        require(isinstance(item, int) and not isinstance(item, bool), f"{label}[{index}] must be an integer")
        require(
            CATALOG_TASK_ID_MIN <= item <= CATALOG_TASK_ID_MAX,
            f"{label}[{index}] must be between {CATALOG_TASK_ID_MIN} and {CATALOG_TASK_ID_MAX}",
        )
        task_ids.append(item)
    require(len(set(task_ids)) == len(task_ids), f"{label} must not contain duplicates")
    return task_ids


def _validated_live_saas_manifest(manifest: dict[str, Any], path: Path, base_directory: Path) -> dict[str, Any]:
    require(manifest.get("ok") is True, f"{path} ok must be true")
    require(manifest.get("liveSaaSValidated") is True, f"{path} must be a live SaaS validation manifest")
    require(
        manifest.get("catalogSpreadsheetURL") == CATALOG_SPREADSHEET_URL,
        f"{path} must reference the canonical coworker catalog spreadsheet",
    )
    catalog_task_ids = _require_catalog_task_ids(manifest.get("catalogTaskIDs"), f"{path}.catalogTaskIDs")

    service_name = manifest.get("serviceName")
    task_name = manifest.get("taskName")
    url_host = manifest.get("urlHost")
    require(isinstance(service_name, str) and service_name, f"{path}.serviceName must be non-empty")
    require(isinstance(task_name, str) and task_name, f"{path}.taskName must be non-empty")
    require(isinstance(url_host, str) and url_host, f"{path}.urlHost must be non-empty")

    return {
        "manifestPath": relative_manifest_path(path, base_directory),
        "serviceName": service_name,
        "taskName": task_name,
        "urlHost": url_host,
        "catalogTaskIDs": catalog_task_ids,
    }


def build_coworker_catalog_coverage(manifest_paths: list[Path], base_directory: Path) -> dict[str, Any]:
    require(manifest_paths, "at least one live SaaS manifest path is required")
    evidence = [
        _validated_live_saas_manifest(load_report(path), path, base_directory)
        for path in manifest_paths
    ]

    evidence_by_task_id: dict[int, list[dict[str, str]]] = {}
    for entry in evidence:
        for task_id in entry["catalogTaskIDs"]:
            evidence_by_task_id.setdefault(task_id, []).append(
                {
                    "manifestPath": entry["manifestPath"],
                    "serviceName": entry["serviceName"],
                    "taskName": entry["taskName"],
                    "urlHost": entry["urlHost"],
                }
            )

    proven_task_ids = sorted(evidence_by_task_id)
    all_task_ids = set(range(CATALOG_TASK_ID_MIN, CATALOG_TASK_ID_MAX + 1))
    pending_task_ids = sorted(all_task_ids.difference(proven_task_ids))

    return {
        "ok": True,
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "catalogTaskRange": {
            "first": CATALOG_TASK_ID_MIN,
            "last": CATALOG_TASK_ID_MAX,
            "total": CATALOG_TASK_ID_MAX - CATALOG_TASK_ID_MIN + 1,
        },
        "evidenceManifestCount": len(evidence),
        "provenTaskCount": len(proven_task_ids),
        "pendingTaskCount": len(pending_task_ids),
        "provenTaskIDs": proven_task_ids,
        "pendingTaskIDs": pending_task_ids,
        "evidenceByTaskID": {
            str(task_id): evidence_by_task_id[task_id]
            for task_id in proven_task_ids
        },
    }


def write_coworker_catalog_coverage(manifest_paths: list[Path], output_path: Path) -> None:
    base_directory = output_path.parent
    summary = build_coworker_catalog_coverage(manifest_paths, base_directory)
    with output_path.open("w", encoding="utf-8") as output_file:
        json.dump(summary, output_file, indent=2, sort_keys=True)
        output_file.write("\n")
