"""Command-line entrypoint for native click-probe contract validation."""

from __future__ import annotations

import argparse
from pathlib import Path

from .accessibility_frames import write_accessibility_frames_manifest
from .browser_workflow import write_browser_workflow_manifest
from .computer_use import write_computer_use_manifest
from .computer_use_action import write_computer_use_action_manifest
from .coworker_catalog import write_coworker_catalog_coverage
from .live_saas import write_live_saas_manifest
from .live_saas_template import write_live_saas_template
from .live_app_computer_use import write_live_app_computer_use_manifest
from .live_app_computer_use_template import write_live_app_computer_use_template
from .multi_file_artifact import write_multi_file_artifact_manifest
from .one_turn_coworker import write_one_turn_coworker_manifest
from .packaged_window import (
    validate_packaged_window_report,
    write_accessibility_readiness_manifest,
    write_comparison_manifest,
)
from .performance import (
    DEFAULT_MAX_IDLE_CPU_PERCENT,
    DEFAULT_MAX_IDLE_RESIDENT_MEMORY_GROWTH_BYTES,
    DEFAULT_MAX_IDLE_THREAD_GROWTH,
    DEFAULT_MAX_LAUNCH_READY_MILLISECONDS,
    DEFAULT_MAX_RESIDENT_MEMORY_BYTES,
    DEFAULT_MAX_RESIDENT_MEMORY_GROWTH_BYTES,
    DEFAULT_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES,
    DEFAULT_MAX_REPEATED_RETAINED_THREAD_GROWTH,
    DEFAULT_MAX_THREAD_COUNT,
    PERFORMANCE_PRODUCT,
    write_performance_manifest,
)
from .probe_contracts import validate_report
from .scheduled_coworker import write_scheduled_coworker_manifest
from .scheduled_notification_observation import write_scheduled_notification_observation_manifest
from .scheduled_notification_observation_template import write_scheduled_notification_observation_template
from .safety_reviewer_calibration import (
    write_safety_reviewer_calibration_manifest,
    write_safety_reviewer_calibration_rollup,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate QuillCode native click-probe contracts emitted by smoke reports.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="validate one native smoke report's click probes")
    validate_parser.add_argument("report", type=Path)
    validate_parser.add_argument("--label", default="quill-code-desktop native smoke")

    compare_parser = subparsers.add_parser("compare", help="compare direct executable and Launch Services click probes")
    compare_parser.add_argument("direct_report", type=Path)
    compare_parser.add_argument("launch_services_report", type=Path)
    compare_parser.add_argument("--manifest", required=True, type=Path)

    readiness_parser = subparsers.add_parser("readiness", help="write packaged native Accessibility readiness evidence")
    readiness_parser.add_argument("artifact_root", type=Path)
    readiness_parser.add_argument("--manifest", required=True, type=Path)

    scheduled_parser = subparsers.add_parser(
        "scheduled-coworker",
        help="write packaged scheduled coworker evidence",
    )
    scheduled_parser.add_argument("direct_report", type=Path)
    scheduled_parser.add_argument("launch_services_report", type=Path)
    scheduled_parser.add_argument("--manifest", required=True, type=Path)

    multi_file_parser = subparsers.add_parser(
        "multi-file-artifact",
        help="write packaged multi-file artifact evidence",
    )
    multi_file_parser.add_argument("direct_report", type=Path)
    multi_file_parser.add_argument("launch_services_report", type=Path)
    multi_file_parser.add_argument("--manifest", required=True, type=Path)

    one_turn_coworker_parser = subparsers.add_parser(
        "one-turn-coworker",
        help="write packaged one-turn office coworker evidence",
    )
    one_turn_coworker_parser.add_argument("direct_report", type=Path)
    one_turn_coworker_parser.add_argument("launch_services_report", type=Path)
    one_turn_coworker_parser.add_argument("--manifest", required=True, type=Path)

    browser_workflow_parser = subparsers.add_parser(
        "browser-workflow",
        help="write packaged browser coworker workflow evidence",
    )
    browser_workflow_parser.add_argument("direct_report", type=Path)
    browser_workflow_parser.add_argument("launch_services_report", type=Path)
    browser_workflow_parser.add_argument("--manifest", required=True, type=Path)

    window_parser = subparsers.add_parser("window", help="validate packaged live-window smoke report and screenshot")
    window_parser.add_argument("report", type=Path)
    window_parser.add_argument("screenshot", type=Path)

    frames_parser = subparsers.add_parser("frames", help="write live packaged Accessibility frame evidence")
    frames_parser.add_argument("report", type=Path)
    frames_parser.add_argument("screenshot", type=Path)
    frames_parser.add_argument("--click-probe-manifest", type=Path)
    frames_parser.add_argument("--manifest", required=True, type=Path)

    performance_parser = subparsers.add_parser(
        "performance",
        help="validate packaged native launch and resident-memory evidence",
    )
    performance_parser.add_argument("reports", nargs="+", type=Path)
    performance_parser.add_argument("--manifest", required=True, type=Path)
    performance_parser.add_argument("--expected-app-name", default=PERFORMANCE_PRODUCT)
    performance_parser.add_argument(
        "--max-launch-ready-milliseconds",
        type=float,
        default=DEFAULT_MAX_LAUNCH_READY_MILLISECONDS,
    )
    performance_parser.add_argument(
        "--max-resident-memory-bytes",
        type=int,
        default=DEFAULT_MAX_RESIDENT_MEMORY_BYTES,
    )
    performance_parser.add_argument(
        "--max-resident-memory-growth-bytes",
        type=int,
        default=DEFAULT_MAX_RESIDENT_MEMORY_GROWTH_BYTES,
    )
    performance_parser.add_argument(
        "--max-repeated-resident-memory-growth-bytes",
        type=int,
        default=DEFAULT_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES,
    )
    performance_parser.add_argument(
        "--max-thread-count",
        type=int,
        default=DEFAULT_MAX_THREAD_COUNT,
    )
    performance_parser.add_argument(
        "--max-repeated-retained-thread-growth",
        type=int,
        default=DEFAULT_MAX_REPEATED_RETAINED_THREAD_GROWTH,
    )
    performance_parser.add_argument(
        "--max-idle-cpu-percent",
        type=float,
        default=DEFAULT_MAX_IDLE_CPU_PERCENT,
    )
    performance_parser.add_argument(
        "--max-idle-resident-memory-growth-bytes",
        type=int,
        default=DEFAULT_MAX_IDLE_RESIDENT_MEMORY_GROWTH_BYTES,
    )
    performance_parser.add_argument(
        "--max-idle-thread-growth",
        type=int,
        default=DEFAULT_MAX_IDLE_THREAD_GROWTH,
    )

    computer_use_parser = subparsers.add_parser(
        "computer-use",
        help="write packaged Computer Use release evidence",
    )
    computer_use_parser.add_argument("direct_report", type=Path)
    computer_use_parser.add_argument("launch_services_report", type=Path)
    computer_use_parser.add_argument("window_report", type=Path)
    computer_use_parser.add_argument("--click-probe-manifest", required=True, type=Path)
    computer_use_parser.add_argument("--accessibility-frames-manifest", required=True, type=Path)
    computer_use_parser.add_argument("--manifest", required=True, type=Path)

    computer_use_action_parser = subparsers.add_parser(
        "computer-use-action",
        help="write packaged Computer Use action smoke evidence",
    )
    computer_use_action_parser.add_argument("direct_report", type=Path)
    computer_use_action_parser.add_argument("launch_services_report", type=Path)
    computer_use_action_parser.add_argument("--manifest", required=True, type=Path)

    live_saas_parser = subparsers.add_parser(
        "live-saas",
        help="validate optional signed-in live SaaS coworker evidence",
    )
    live_saas_parser.add_argument("evidence", type=Path)
    live_saas_parser.add_argument("--manifest", required=True, type=Path)

    live_saas_template_parser = subparsers.add_parser(
        "live-saas-template",
        help="write a row-linked live SaaS evidence template",
    )
    live_saas_template_parser.add_argument("catalog_task_ids", nargs="+", type=int)
    live_saas_template_parser.add_argument("--output", required=True, type=Path)
    live_saas_template_parser.add_argument("--service-name")
    live_saas_template_parser.add_argument("--task-name")
    live_saas_template_parser.add_argument("--url")

    live_app_computer_use_parser = subparsers.add_parser(
        "live-app-computer-use",
        help="validate optional live local-app Computer Use coworker evidence",
    )
    live_app_computer_use_parser.add_argument("evidence", type=Path)
    live_app_computer_use_parser.add_argument("--manifest", required=True, type=Path)

    live_app_computer_use_template_parser = subparsers.add_parser(
        "live-app-computer-use-template",
        help="write a row-linked live local-app Computer Use evidence template",
    )
    live_app_computer_use_template_parser.add_argument("catalog_task_ids", nargs="+", type=int)
    live_app_computer_use_template_parser.add_argument("--output", required=True, type=Path)
    live_app_computer_use_template_parser.add_argument("--app-name")
    live_app_computer_use_template_parser.add_argument("--task-name")

    coworker_catalog_parser = subparsers.add_parser(
        "coworker-catalog",
        help="write row-level office coworker catalog coverage from validated evidence manifests",
    )
    coworker_catalog_parser.add_argument("manifests", nargs="+", type=Path)
    coworker_catalog_parser.add_argument("--output", required=True, type=Path)
    coworker_catalog_parser.add_argument("--markdown-output", type=Path)

    safety_reviewer_parser = subparsers.add_parser(
        "safety-reviewer-calibration",
        help="validate redacted Auto safety reviewer calibration evidence",
    )
    safety_reviewer_parser.add_argument("evidence", type=Path)
    safety_reviewer_parser.add_argument("--manifest", required=True, type=Path)

    safety_reviewer_rollup_parser = subparsers.add_parser(
        "safety-reviewer-calibration-rollup",
        help="roll up validated Auto safety reviewer calibration manifests",
    )
    safety_reviewer_rollup_parser.add_argument("manifests", nargs="+", type=Path)
    safety_reviewer_rollup_parser.add_argument("--output", required=True, type=Path)
    safety_reviewer_rollup_parser.add_argument("--markdown-output", type=Path)

    scheduled_notification_parser = subparsers.add_parser(
        "scheduled-notification-observation",
        help="validate optional packaged native notification observation evidence",
    )
    scheduled_notification_parser.add_argument("evidence", type=Path)
    scheduled_notification_parser.add_argument("--manifest", required=True, type=Path)

    scheduled_notification_template_parser = subparsers.add_parser(
        "scheduled-notification-observation-template",
        help="write a row-linked scheduled notification observation evidence template",
    )
    scheduled_notification_template_parser.add_argument("catalog_task_ids", nargs="+", type=int)
    scheduled_notification_template_parser.add_argument("--output", required=True, type=Path)

    args = parser.parse_args()
    if args.command == "validate":
        validate_report(args.report, args.label)
    elif args.command == "compare":
        write_comparison_manifest(args.direct_report, args.launch_services_report, args.manifest)
    elif args.command == "readiness":
        write_accessibility_readiness_manifest(args.artifact_root, args.manifest)
    elif args.command == "scheduled-coworker":
        write_scheduled_coworker_manifest(
            args.direct_report,
            args.launch_services_report,
            args.manifest,
        )
    elif args.command == "multi-file-artifact":
        write_multi_file_artifact_manifest(
            args.direct_report,
            args.launch_services_report,
            args.manifest,
        )
    elif args.command == "one-turn-coworker":
        write_one_turn_coworker_manifest(
            args.direct_report,
            args.launch_services_report,
            args.manifest,
        )
    elif args.command == "browser-workflow":
        write_browser_workflow_manifest(
            args.direct_report,
            args.launch_services_report,
            args.manifest,
        )
    elif args.command == "window":
        validate_packaged_window_report(args.report, args.screenshot)
    elif args.command == "frames":
        write_accessibility_frames_manifest(
            args.report,
            args.screenshot,
            args.click_probe_manifest,
            args.manifest,
        )
    elif args.command == "performance":
        write_performance_manifest(
            args.reports,
            args.manifest,
            max_launch_ready_milliseconds=args.max_launch_ready_milliseconds,
            max_resident_memory_bytes=args.max_resident_memory_bytes,
            max_resident_memory_growth_bytes=args.max_resident_memory_growth_bytes,
            max_repeated_resident_memory_growth_bytes=(
                args.max_repeated_resident_memory_growth_bytes
            ),
            max_thread_count=args.max_thread_count,
            max_repeated_retained_thread_growth=(
                args.max_repeated_retained_thread_growth
            ),
            max_idle_cpu_percent=args.max_idle_cpu_percent,
            max_idle_resident_memory_growth_bytes=(
                args.max_idle_resident_memory_growth_bytes
            ),
            max_idle_thread_growth=args.max_idle_thread_growth,
            expected_app_name=args.expected_app_name,
        )
    elif args.command == "computer-use":
        write_computer_use_manifest(
            args.direct_report,
            args.launch_services_report,
            args.window_report,
            args.click_probe_manifest,
            args.accessibility_frames_manifest,
            args.manifest,
        )
    elif args.command == "computer-use-action":
        write_computer_use_action_manifest(
            args.direct_report,
            args.launch_services_report,
            args.manifest,
        )
    elif args.command == "live-saas":
        write_live_saas_manifest(args.evidence, args.manifest)
    elif args.command == "live-saas-template":
        write_live_saas_template(
            args.catalog_task_ids,
            args.output,
            service_name=args.service_name,
            task_name=args.task_name,
            url=args.url,
        )
    elif args.command == "live-app-computer-use":
        write_live_app_computer_use_manifest(args.evidence, args.manifest)
    elif args.command == "live-app-computer-use-template":
        write_live_app_computer_use_template(
            args.catalog_task_ids,
            args.output,
            app_name=args.app_name,
            task_name=args.task_name,
        )
    elif args.command == "coworker-catalog":
        write_coworker_catalog_coverage(args.manifests, args.output, args.markdown_output)
    elif args.command == "safety-reviewer-calibration":
        write_safety_reviewer_calibration_manifest(args.evidence, args.manifest)
    elif args.command == "safety-reviewer-calibration-rollup":
        write_safety_reviewer_calibration_rollup(args.manifests, args.output, args.markdown_output)
    elif args.command == "scheduled-notification-observation":
        write_scheduled_notification_observation_manifest(args.evidence, args.manifest)
    elif args.command == "scheduled-notification-observation-template":
        write_scheduled_notification_observation_template(args.catalog_task_ids, args.output)
