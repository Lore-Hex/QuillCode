"""Summarize row-level office coworker catalog evidence."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .json_io import load_report, relative_manifest_path, require
from .live_saas import (
    CATALOG_SNAPSHOT,
    CATALOG_SPREADSHEET_URL,
    CATALOG_TASK_IDS,
    CATALOG_TASK_ID_MAX,
    CATALOG_TASK_ID_MIN,
    CATALOG_TASK_ID_SET,
)
from .one_turn_coworker import EXPECTED_CASES


def _require_catalog_task_ids(value: Any, label: str) -> list[int]:
    require(isinstance(value, list) and value, f"{label} must be a non-empty list")
    task_ids: list[int] = []
    for index, item in enumerate(value):
        require(isinstance(item, int) and not isinstance(item, bool), f"{label}[{index}] must be an integer")
        require(
            item in CATALOG_TASK_ID_SET,
            f"{label}[{index}] must match a catalog row ID between "
            f"{CATALOG_TASK_ID_MIN} and {CATALOG_TASK_ID_MAX}",
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
        notification_title == "Quill Cowork scheduled task ready",
        f"{path}.notificationTitle must prove the Quill Cowork scheduled task notification",
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
        "serviceName": "Quill Cowork Notifications",
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
        "serviceName": "Quill Cowork Packaged Smoke",
        "taskName": "One-turn local shell/file coworker smoke",
        "urlHost": "local-packaged-app",
    }


def _validated_packaged_multi_file_manifest(
    manifest: dict[str, Any],
    path: Path,
    base_directory: Path,
) -> dict[str, Any]:
    require(
        manifest.get("packagedMultiFileArtifactValidated") is True,
        f"{path} must be a packaged multi-file artifact validation manifest",
    )
    base = _manifest_base(manifest, path, base_directory)
    expected_task_ids = [69, 70, 71, 72, 73]
    require(
        base["catalogTaskIDs"] == expected_task_ids,
        f"{path}.catalogTaskIDs must be {expected_task_ids}",
    )
    require(
        manifest.get("taskIDs") == expected_task_ids,
        f"{path}.taskIDs must match catalogTaskIDs",
    )
    require(
        manifest.get("multiFileArtifactMatchesDirect") is True
        and manifest.get("launchServicesMatchesDirect") is True,
        f"{path} must prove direct executable and Launch Services multi-file smoke match",
    )
    catalog_cases = manifest.get("catalogCases")
    catalog_case_ids = sorted(
        case.get("taskID")
        for case in catalog_cases
        if isinstance(case, dict)
    ) if isinstance(catalog_cases, list) else []
    require(
        isinstance(catalog_cases, list)
        and catalog_case_ids == expected_task_ids,
        f"{path} must include the row #69 through #73 multi-file catalog cases",
    )

    return {
        **base,
        "evidenceType": "packaged-multi-file-artifact",
        "serviceName": "Quill Cowork Packaged Smoke",
        "taskName": "Multi-file artifact coworker smoke",
        "urlHost": "local-packaged-app",
    }


def _validated_saas_analogue_manifest(
    manifest: dict[str, Any],
    path: Path,
    base_directory: Path,
) -> dict[str, Any]:
    require(manifest.get("saasAnalogueValidated") is True, f"{path} must be a SaaS analogue manifest")
    base = _manifest_base(manifest, path, base_directory)
    require(
        base["catalogTaskIDs"] == [199, 200],
        f"{path}.catalogTaskIDs must be [199, 200] for the packaged CRM and sheet analogues",
    )
    require(manifest.get("usesSyntheticData") is True, f"{path} must declare synthetic data")
    require(
        manifest.get("externalSaaSValidated") is False,
        f"{path} must not claim external SaaS validation",
    )
    require(
        manifest.get("browserWorkflowMatchesDirect") is True
        and manifest.get("launchServicesMatchesDirect") is True,
        f"{path} must prove direct executable and Launch Services browser workflows match",
    )
    scenarios = manifest.get("analogueScenarios")
    scenario_ids = sorted(
        scenario.get("taskID")
        for scenario in scenarios
        if isinstance(scenario, dict)
    ) if isinstance(scenarios, list) else []
    require(scenario_ids == [199, 200], f"{path} must map analogue scenarios to rows 199 and 200")
    limitations = manifest.get("limitations")
    require(
        isinstance(limitations, list)
        and len(limitations) >= 2
        and all(isinstance(item, str) and item for item in limitations),
        f"{path}.limitations must disclose at least two non-empty limitations",
    )

    return {
        **base,
        "evidenceType": "packaged-saas-analogue",
        "evidenceClass": "analogue",
        "serviceName": "Quill Cowork Local SaaS Lab",
        "taskName": "CRM and shared-sheet browser workflow analogues",
        "urlHost": "local-synthetic-browser",
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
    if manifest.get("packagedMultiFileArtifactValidated") is True:
        return _validated_packaged_multi_file_manifest(manifest, path, base_directory)
    if manifest.get("saasAnalogueValidated") is True:
        return _validated_saas_analogue_manifest(manifest, path, base_directory)
    raise SystemExit(
        f"{path} must be a supported coworker evidence manifest "
        "(live SaaS, live app Computer Use, scheduled notification observation, "
        "packaged one-turn coworker, packaged multi-file artifact, or packaged SaaS analogue)"
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
                    "evidenceClass": entry.get("evidenceClass", "proof"),
                    "serviceName": entry["serviceName"],
                    "taskName": entry["taskName"],
                    "urlHost": entry["urlHost"],
                }
            )

    proven_task_ids = sorted(
        task_id
        for task_id, task_evidence in evidence_by_task_id.items()
        if any(item["evidenceClass"] == "proof" for item in task_evidence)
    )
    analogue_task_ids = sorted(
        task_id
        for task_id, task_evidence in evidence_by_task_id.items()
        if task_id not in proven_task_ids
        and any(item["evidenceClass"] == "analogue" for item in task_evidence)
    )
    all_task_ids = set(CATALOG_TASK_IDS)
    pending_task_ids = sorted(all_task_ids.difference(proven_task_ids, analogue_task_ids))
    task_audit = []
    for row in CATALOG_SNAPSHOT["rows"]:
        task_id = row["id"]
        row_evidence = evidence_by_task_id.get(task_id, [])
        if task_id in proven_task_ids:
            result = "proven"
        elif task_id in analogue_task_ids:
            result = "analogue"
        else:
            result = "pending"
        task_audit.append(
            {
                "taskID": task_id,
                "result": result,
                "category": row["category"],
                "task": row["task"],
                "sourceStatus": row["sourceStatus"],
                "quillCodeCoverage": row["quillCodeCoverage"],
                "nextQuillCodeGap": row["nextQuillCodeGap"],
                "evidence": row_evidence,
            }
        )

    return {
        "ok": True,
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "catalogSnapshot": {
            "reviewDate": CATALOG_SNAPSHOT["reviewDate"],
            "sourceSHA256": CATALOG_SNAPSHOT["sourceSHA256"],
        },
        "catalogTaskRange": {
            "first": CATALOG_TASK_ID_MIN,
            "last": CATALOG_TASK_ID_MAX,
            "total": len(CATALOG_TASK_IDS),
        },
        "evidenceManifestCount": len(evidence),
        "provenTaskCount": len(proven_task_ids),
        "analogueTaskCount": len(analogue_task_ids),
        "pendingTaskCount": len(pending_task_ids),
        "provenTaskIDs": proven_task_ids,
        "analogueTaskIDs": analogue_task_ids,
        "pendingTaskIDs": pending_task_ids,
        "evidenceByTaskID": {
            str(task_id): evidence_by_task_id[task_id]
            for task_id in proven_task_ids
        },
        "taskAudit": task_audit,
    }


def coworker_catalog_markdown(summary: dict[str, Any]) -> str:
    lines = [
        "# Quill Cowork Coworker Coverage",
        "",
        f"- Catalog: {summary['catalogSpreadsheetURL']}",
        f"- Evidence manifests: {summary['evidenceManifestCount']}",
        f"- Proven rows: {summary['provenTaskCount']}",
        f"- Analogue rows: {summary['analogueTaskCount']}",
        f"- Pending rows: {summary['pendingTaskCount']}",
        f"- Catalog snapshot reviewed: {summary['catalogSnapshot']['reviewDate']}",
        "",
        "This report is fail-closed: a source-sheet status or capability analogue is not proof.",
        "Analogue means equivalent mechanics passed against synthetic local data; it does not validate external authentication or vendor behavior.",
        "Every catalog row remains pending or analogue until a row-linked proof manifest passes its evidence gate.",
        "",
        "| Row | Result | Category | Task | Evidence or next gap |",
        "| --- | --- | --- | --- | --- |",
    ]

    for row in summary["taskAudit"]:
        if row["evidence"]:
            evidence_label = "; ".join(
                f"{entry['evidenceType']} [{entry['evidenceClass']}] (`{entry['manifestPath']}`)"
                for entry in row["evidence"]
            )
        else:
            evidence_label = row["nextQuillCodeGap"] or row["quillCodeCoverage"] or "Row-linked evidence required"
        lines.append(
            "| {row} | {result} | {category} | {task} | {evidence} |".format(
                row=row["taskID"],
                result=row["result"],
                category=_markdown_table_cell(row["category"]),
                task=_markdown_table_cell(row["task"]),
                evidence=_markdown_table_cell(evidence_label),
            )
        )

    lines.extend(
        [
            "",
            "All catalog rows are listed. Pending means no row-linked evidence was supplied; analogue is synthetic and is not live SaaS proof.",
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
