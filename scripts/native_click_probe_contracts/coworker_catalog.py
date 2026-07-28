"""Summarize row-level office coworker catalog evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, relative_manifest_path, require
from .live_saas import CATALOG_SPREADSHEET_URL, CATALOG_TASK_ID_MAX, CATALOG_TASK_ID_MIN
from .one_turn_coworker import EXPECTED_CASES


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


def _manifest_base(manifest: dict[str, Any], path: Path, base_directory: Path) -> dict[str, Any]:
    require(manifest.get("ok") is True, f"{path} ok must be true")
    require(
        manifest.get("catalogSpreadsheetURL") == CATALOG_SPREADSHEET_URL,
        f"{path} must reference the canonical coworker catalog spreadsheet",
    )
    catalog_task_ids = _require_catalog_task_ids(manifest.get("catalogTaskIDs"), f"{path}.catalogTaskIDs")
    return {
        "manifestPath": relative_manifest_path(path, base_directory),
        "catalogTaskIDs": catalog_task_ids,
    }


def _validated_live_saas_manifest(manifest: dict[str, Any], path: Path, base_directory: Path) -> dict[str, Any]:
    require(manifest.get("liveSaaSValidated") is True, f"{path} must be a live SaaS validation manifest")
    base = _manifest_base(manifest, path, base_directory)

    service_name = manifest.get("serviceName")
    task_name = manifest.get("taskName")
    url_host = manifest.get("urlHost")
    require(isinstance(service_name, str) and service_name, f"{path}.serviceName must be non-empty")
    require(isinstance(task_name, str) and task_name, f"{path}.taskName must be non-empty")
    require(isinstance(url_host, str) and url_host, f"{path}.urlHost must be non-empty")

    return {
        **base,
        "evidenceType": "live-saas",
        "serviceName": service_name,
        "taskName": task_name,
        "urlHost": url_host,
    }


def _validated_scheduled_notification_manifest(
    manifest: dict[str, Any],
    path: Path,
    base_directory: Path,
) -> dict[str, Any]:
    require(
        manifest.get("scheduledNotificationObservationValidated") is True,
        f"{path} must be a scheduled notification observation manifest",
    )
    base = _manifest_base(manifest, path, base_directory)
    notification_title = manifest.get("notificationTitle")
    follow_up_thread_title = manifest.get("followUpThreadTitle")
    observation_method = manifest.get("observationMethod")
    require(
        notification_title == "QuillCode scheduled task ready",
        f"{path}.notificationTitle must prove the QuillCode scheduled task notification",
    )
    require(
        isinstance(follow_up_thread_title, str) and follow_up_thread_title.startswith("Scheduled check: "),
        f"{path}.followUpThreadTitle must identify the scheduled follow-up thread",
    )
    require(
        observation_method in {"accessibility", "computer-use", "manual-screenshot"},
        f"{path}.observationMethod must be accessibility, computer-use, or manual-screenshot",
    )
    require(
        manifest.get("notificationVisible") is True
        and manifest.get("activationOpenedFollowUp") is True
        and manifest.get("notificationBodyContainsTask") is True,
        f"{path} must prove visible notification text and follow-up activation",
    )
    return {
        **base,
        "evidenceType": "scheduled-notification-observation",
        "serviceName": "QuillCode Notifications",
        "taskName": follow_up_thread_title,
        "urlHost": "local-notification-center",
        "notificationTitle": notification_title,
        "observationMethod": observation_method,
    }


def _validated_live_app_computer_use_manifest(
    manifest: dict[str, Any],
    path: Path,
    base_directory: Path,
) -> dict[str, Any]:
    require(
        manifest.get("liveAppComputerUseValidated") is True,
        f"{path} must be a live app Computer Use validation manifest",
    )
    base = _manifest_base(manifest, path, base_directory)

    app_name = manifest.get("appName")
    task_name = manifest.get("taskName")
    foreground_application = manifest.get("foregroundApplication")
    require(isinstance(app_name, str) and app_name, f"{path}.appName must be non-empty")
    require(isinstance(task_name, str) and task_name, f"{path}.taskName must be non-empty")
    require(
        isinstance(foreground_application, str) and foreground_application,
        f"{path}.foregroundApplication must be non-empty",
    )
    require(manifest.get("taskCompleted") is True, f"{path}.taskCompleted must be true")
    require(
        manifest.get("screenshotArtifactExists") is True,
        f"{path}.screenshotArtifactExists must be true",
    )

    return {
        **base,
        "evidenceType": "live-app-computer-use",
        "serviceName": app_name,
        "taskName": task_name,
        "urlHost": f"local-app:{foreground_application}",
    }


def _validated_packaged_one_turn_manifest(
    manifest: dict[str, Any],
    path: Path,
    base_directory: Path,
) -> dict[str, Any]:
    require(
        manifest.get("packagedOneTurnCoworkerValidated") is True,
        f"{path} must be a packaged one-turn coworker validation manifest",
    )
    base = _manifest_base(manifest, path, base_directory)
    expected_task_ids = sorted(EXPECTED_CASES)
    require(
        base["catalogTaskIDs"] == expected_task_ids,
        f"{path}.catalogTaskIDs must be {expected_task_ids}",
    )
    require(
        manifest.get("taskIDs") == expected_task_ids,
        f"{path}.taskIDs must match catalogTaskIDs",
    )
    require(
        manifest.get("oneTurnCoworkerMatchesDirect") is True
        and manifest.get("launchServicesMatchesDirect") is True,
        f"{path} must prove direct executable and Launch Services one-turn smoke match",
    )

    return {
        **base,
        "evidenceType": "packaged-one-turn-coworker",
        "serviceName": "QuillCode Packaged Smoke",
        "taskName": "One-turn local shell/file coworker smoke",
        "urlHost": "local-packaged-app",
    }


def _validated_manifest(manifest: dict[str, Any], path: Path, base_directory: Path) -> dict[str, Any]:
    if manifest.get("liveSaaSValidated") is True:
        return _validated_live_saas_manifest(manifest, path, base_directory)
    if manifest.get("scheduledNotificationObservationValidated") is True:
        return _validated_scheduled_notification_manifest(manifest, path, base_directory)
    if manifest.get("liveAppComputerUseValidated") is True:
        return _validated_live_app_computer_use_manifest(manifest, path, base_directory)
    if manifest.get("packagedOneTurnCoworkerValidated") is True:
        return _validated_packaged_one_turn_manifest(manifest, path, base_directory)
    raise SystemExit(
        f"{path} must be a supported coworker evidence manifest "
        "(live SaaS, live app Computer Use, scheduled notification observation, or packaged one-turn coworker)"
    )


def build_coworker_catalog_coverage(manifest_paths: list[Path], base_directory: Path) -> dict[str, Any]:
    require(manifest_paths, "at least one coworker evidence manifest path is required")
    evidence = [
        _validated_manifest(load_report(path), path, base_directory)
        for path in manifest_paths
    ]

    evidence_by_task_id: dict[int, list[dict[str, str]]] = {}
    for entry in evidence:
        for task_id in entry["catalogTaskIDs"]:
            evidence_by_task_id.setdefault(task_id, []).append(
                {
                    "manifestPath": entry["manifestPath"],
                    "evidenceType": entry["evidenceType"],
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


def coworker_catalog_markdown(summary: dict[str, Any]) -> str:
    lines = [
        "# QuillCode Coworker Coverage",
        "",
        f"- Catalog: {summary['catalogSpreadsheetURL']}",
        f"- Evidence manifests: {summary['evidenceManifestCount']}",
        f"- Proven rows: {summary['provenTaskCount']}",
        f"- Pending rows: {summary['pendingTaskCount']}",
        "",
        "| Row | Evidence | Service | Task | Source |",
        "| --- | --- | --- | --- | --- |",
    ]

    evidence_by_task_id = summary["evidenceByTaskID"]
    for task_id in summary["provenTaskIDs"]:
        row_entries = evidence_by_task_id[str(task_id)]
        first_entry = row_entries[0]
        extra_count = len(row_entries) - 1
        evidence_label = first_entry["evidenceType"]
        if extra_count:
            evidence_label = f"{evidence_label} (+{extra_count})"
        lines.append(
            "| {row} | {evidence} | {service} | {task} | `{source}` |".format(
                row=task_id,
                evidence=_markdown_table_cell(evidence_label),
                service=_markdown_table_cell(first_entry["serviceName"]),
                task=_markdown_table_cell(first_entry["taskName"]),
                source=str(first_entry["manifestPath"]).replace("`", "\\`"),
            )
        )

    lines.extend(
        [
            "",
            "Rows not listed here remain unproven until a row-linked manifest is validated.",
            "",
        ]
    )
    return "\n".join(lines)


def _markdown_table_cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def write_coworker_catalog_coverage(
    manifest_paths: list[Path],
    output_path: Path,
    markdown_output_path: Path | None = None,
) -> None:
    base_directory = output_path.parent
    summary = build_coworker_catalog_coverage(manifest_paths, base_directory)
    with output_path.open("w", encoding="utf-8") as output_file:
        json.dump(summary, output_file, indent=2, sort_keys=True)
        output_file.write("\n")
    if markdown_output_path is not None:
        with markdown_output_path.open("w", encoding="utf-8") as output_file:
            output_file.write(coworker_catalog_markdown(summary))
