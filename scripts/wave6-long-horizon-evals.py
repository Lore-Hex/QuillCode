#!/usr/bin/env python3
"""Prepare and grade the ten Wave 6 long-horizon founder tasks.

The prompts are submitted through the visible Quill Cowork app. This script owns only
the deterministic startup packet and artifact grading so a UI run remains inspectable
and resumable.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "docs" / "coworker-task-catalog.json"
DEFAULT_RUN_ROOT = ROOT / ".build" / "quillcode-validation" / "wave6-ui"
DEFAULT_BINARY = ROOT / ".build" / "debug" / "quill-code-desktop"
WAVE5_SCRIPT = ROOT / "scripts" / "wave5-cowork-evals.py"
TASK_IDS = tuple(range(311, 321))
EXACT_MODEL = "deepseek/deepseek-v4-flash-0731"
KEY_FILES = (
    Path.home() / ".quillcode" / "secrets" / "trustedrouter_api_key",
    Path.home() / ".quill.code.keyfile",
)


class EvalError(RuntimeError):
    pass


@dataclass(frozen=True)
class TaskSpec:
    required_files: tuple[str, ...]
    csv_minima: dict[str, int]
    source_files: tuple[str, ...] = ()
    workbook_files: tuple[str, ...] = ()


SPECS = {
    311: TaskSpec(
        required_files=(
            "research-log.csv", "people-shortlist.csv", "signal-taxonomy.csv",
            "segment-scorecard.csv", "icp-decision-memo.md", "interview-guide.md",
            "outreach-drafts.md",
        ),
        csv_minima={"people-shortlist.csv": 60, "research-log.csv": 80},
        source_files=("research-log.csv", "people-shortlist.csv"),
    ),
    312: TaskSpec(
        required_files=(
            "accounts.csv", "contacts.csv", "research-log.csv", "scoring-model.md",
            "pipeline-analysis.md", "outreach-sequences.md",
        ),
        csv_minima={"accounts.csv": 150, "contacts.csv": 150},
        source_files=("accounts.csv", "contacts.csv", "research-log.csv"),
    ),
    313: TaskSpec(
        required_files=(
            "research-log.csv", "competitor-workflows.csv", "opportunity-scorecard.csv",
            "evidence-map.md", "roadmap-options.md", "decision-memo.md", "prd-1.md",
            "prd-2.md", "prd-3.md",
        ),
        csv_minima={"competitor-workflows.csv": 20, "research-log.csv": 150,
                    "opportunity-scorecard.csv": 30},
        source_files=("research-log.csv", "competitor-workflows.csv"),
    ),
    314: TaskSpec(
        required_files=(
            "research-log.csv", "distribution-map.csv", "people-map.csv",
            "campaign-teardowns.csv", "channel-scorecard.csv", "launch-plan.md",
            "content-calendar.csv", "asset-briefs.md", "outreach-drafts.md",
        ),
        csv_minima={"distribution-map.csv": 120, "people-map.csv": 60,
                    "campaign-teardowns.csv": 50},
        source_files=("research-log.csv", "distribution-map.csv", "people-map.csv"),
    ),
    315: TaskSpec(
        required_files=(
            "investors.csv", "partners.csv", "portfolio-conflicts.csv", "warm-paths.csv",
            "research-log.csv", "scoring-model.md", "fundraising-strategy.md",
            "outreach-drafts.md", "warm-intro-blurbs.md", "meeting-briefs.md",
        ),
        csv_minima={"investors.csv": 100, "warm-paths.csv": 50},
        source_files=("investors.csv", "partners.csv", "research-log.csv"),
    ),
    316: TaskSpec(
        required_files=(
            "operating-model.xlsx", "reconciliation-log.csv", "benchmark-sources.csv",
            "vendor-options.csv", "hiring-benchmarks.csv", "scenario-summary.csv",
            "assumption-register.csv", "board-finance-memo.md", "13-week-action-plan.md",
        ),
        csv_minima={"vendor-options.csv": 30, "hiring-benchmarks.csv": 40,
                    "benchmark-sources.csv": 95, "scenario-summary.csv": 5},
        source_files=("benchmark-sources.csv", "vendor-options.csv", "hiring-benchmarks.csv"),
        workbook_files=("operating-model.xlsx",),
    ),
    317: TaskSpec(
        required_files=(
            "candidates.csv", "evidence-dossiers.md", "research-log.csv", "scorecard.md",
            "sourcing-analysis.md", "interview-plan.md", "reference-check-plan.md",
            "outreach-drafts.md",
        ),
        csv_minima={"candidates.csv": 100},
        source_files=("candidates.csv", "research-log.csv"),
    ),
    318: TaskSpec(
        required_files=(
            "research-log.csv", "company-and-leader-map.csv", "precedent-analysis.csv",
            "scenario-model.xlsx", "assumption-register.csv", "risk-register.csv",
            "board-decision-memo.md", "board-deck-outline.md", "board-questions.md",
        ),
        csv_minima={"research-log.csv": 100, "company-and-leader-map.csv": 20},
        source_files=("research-log.csv", "company-and-leader-map.csv"),
        workbook_files=("scenario-model.xlsx",),
    ),
    319: TaskSpec(
        required_files=(
            "source-log.csv", "jurisdiction-matrix.csv", "control-gap-map.csv",
            "vendor-comparison.csv", "owner-map.csv", "risk-register.csv",
            "counsel-question-list.md", "90-day-plan.md", "go-no-go-memo.md",
        ),
        csv_minima={"source-log.csv": 80, "vendor-comparison.csv": 40},
        source_files=("source-log.csv", "vendor-comparison.csv", "owner-map.csv"),
    ),
    320: TaskSpec(
        required_files=(
            "research-log.csv", "competitor-pricing.csv", "feature-and-limit-matrix.csv",
            "review-signal-taxonomy.csv", "company-and-leader-signals.csv",
            "normalized-price-model.xlsx", "packaging-options.md", "pricing-decision-memo.md",
            "sales-faq.md", "landing-page-pricing-drafts.md",
        ),
        csv_minima={"competitor-pricing.csv": 25, "review-signal-taxonomy.csv": 200},
        source_files=("research-log.csv", "competitor-pricing.csv", "review-signal-taxonomy.csv"),
        workbook_files=("normalized-price-model.xlsx",),
    ),
}


def load_rows() -> dict[int, dict]:
    try:
        payload = json.loads(CATALOG.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvalError(f"Cannot read {CATALOG}: {error}") from error
    rows = {int(row["id"]): row for row in payload.get("rows", []) if int(row["id"]) in TASK_IDS}
    missing = sorted(set(TASK_IDS) - rows.keys())
    if missing:
        raise EvalError(f"Catalog is missing Wave 6 tasks: {missing}")
    return rows


def load_wave5_module():
    spec = importlib.util.spec_from_file_location("wave5_cowork_evals", WAVE5_SCRIPT)
    if spec is None or spec.loader is None:
        raise EvalError(f"Cannot import fixtures from {WAVE5_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_category_fixtures() -> dict:
    return load_wave5_module().CATEGORY_FIXTURES


def safe_name(category: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", category.lower()).strip("-")


def task_prompt(row: dict, task_id: int) -> str:
    spec_for_task = SPECS[task_id]
    deliverables = "\n".join(f"- outputs/{task_id}/{name}" for name in spec_for_task.required_files)
    return f"""{row['task']}

Evaluation workspace instructions:
- Read `inputs/README.md` and every file under `inputs/{task_id}/` before research.
- Put `progress.md` at `outputs/{task_id}/progress.md` and update it after each phase.
- Use these canonical filenames so the run can be graded:
{deliverables}
- Use the already-open desktop Firefox and its signed-in LinkedIn session through Computer Use when the task calls for LinkedIn. Keep LinkedIn read-only.
- The startup and internal records are synthetic, but every public source and current-role claim must be real and cited.
- Work autonomously and resumably. Do not declare completion while any stated minimum or named artifact is missing.
"""


def write_task_packet(workspace: Path, task_id: int, row: dict, fixture: dict) -> str:
    inputs = workspace / "inputs"
    inputs.mkdir(parents=True, exist_ok=True)
    task_inputs = inputs / str(task_id)
    task_inputs.mkdir(parents=True, exist_ok=True)
    (task_inputs / "company-brief.md").write_text(
        fixture["context"].strip() + "\n", encoding="utf-8"
    )
    (task_inputs / "internal-data.csv").write_text(
        fixture["header"] + "".join(fixture["rows"]), encoding="utf-8"
    )
    (task_inputs / "constraints.md").write_text(
        "# Evaluation constraints\n\n"
        "Research is read-only. Never contact people, submit forms, purchase, register, apply, "
        "or modify an external account. Preserve exact blockers and never fabricate evidence.\n",
        encoding="utf-8",
    )
    manifest = [
        "# LedgerLoop Wave 6 evaluation packet",
        "",
        "LedgerLoop is a synthetic B2B SaaS company. Treat all names and records in this packet",
        "as synthetic evaluation data. Use the folder matching the requested task ID. Public web",
        "research must still use current lawful sources, and signed-in sites remain read-only.",
        "",
        "Task folders:",
        f"- {task_id}: {row['category']} (`inputs/{task_id}/`)",
    ]
    (inputs / "README.md").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    return task_prompt(row, task_id)


def prepare(run_root: Path) -> None:
    rows = load_rows()
    fixtures = load_category_fixtures()
    workspace = run_root / "workspace"
    prompts = run_root / "prompts"
    prompts.mkdir(parents=True, exist_ok=True)
    for task_id in TASK_IDS:
        row = rows[task_id]
        prompt = write_task_packet(workspace, task_id, row, fixtures[row["category"]])
        (prompts / f"{task_id}.txt").write_text(prompt, encoding="utf-8")
    manifest = [
        "# LedgerLoop Wave 6 evaluation packet",
        "",
        "LedgerLoop is a synthetic B2B SaaS company. Treat all names and records in this packet",
        "as synthetic evaluation data. Use the folder matching the requested task ID. Public web",
        "research must still use current lawful sources, and signed-in sites remain read-only.",
        "",
        "Task folders:",
    ]
    manifest.extend(
        f"- {task_id}: {rows[task_id]['category']} (`inputs/{task_id}/`)"
        for task_id in TASK_IDS
    )
    (workspace / "inputs" / "README.md").write_text(
        "\n".join(manifest) + "\n", encoding="utf-8"
    )
    print(workspace)


def csv_rows(path: Path) -> tuple[int, list[str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.reader(handle)
        header = next(reader, [])
        return sum(1 for row in reader if any(cell.strip() for cell in row)), header


def source_metadata_issues(path: Path) -> list[str]:
    _, header = csv_rows(path)
    normalized = [re.sub(r"[^a-z0-9]", "", value.lower()) for value in header]

    def has_any(*terms: str) -> bool:
        return any(any(term in column for term in terms) for column in normalized)

    issues = []
    if not has_any("url", "source", "link"):
        issues.append("missing URL/source column")
    if not has_any("accessdate", "accessed", "retrieved"):
        issues.append("missing access-date column")
    if not has_any("confidence", "evidencequality"):
        issues.append("missing confidence column")
    return issues


def workbook_issue(path: Path) -> str | None:
    try:
        with zipfile.ZipFile(path) as archive:
            names = set(archive.namelist())
            if "xl/workbook.xml" not in names:
                return "not a readable XLSX workbook"
            if not any(name.startswith("xl/worksheets/sheet") for name in names):
                return "workbook contains no worksheets"
    except (OSError, zipfile.BadZipFile):
        return "not a readable XLSX workbook"
    return None


def grade_task(workspace: Path, task_id: int) -> dict:
    spec = SPECS[task_id]
    output = workspace / "outputs" / str(task_id)
    checks: list[dict] = []

    def add(name: str, ok: bool, detail: str) -> None:
        checks.append({"name": name, "ok": ok, "detail": detail})

    progress = output / "progress.md"
    add("progress checkpoint", progress.is_file() and progress.stat().st_size > 80, str(progress))
    for relative in spec.required_files:
        path = output / relative
        add(f"artifact {relative}", path.is_file() and path.stat().st_size > 40, str(path))
    for relative, minimum in spec.csv_minima.items():
        path = output / relative
        try:
            count, _ = csv_rows(path)
        except (OSError, csv.Error):
            count = 0
        add(f"{relative} row minimum", count >= minimum, f"{count} / {minimum}")
    for relative in spec.source_files:
        path = output / relative
        issues = source_metadata_issues(path) if path.is_file() else ["file missing"]
        add(f"{relative} source metadata", not issues, "; ".join(issues) or "present")
    for relative in spec.workbook_files:
        path = output / relative
        issue = workbook_issue(path) if path.is_file() else "file missing"
        add(f"{relative} workbook readback", issue is None, issue or "readable")
    return {"task_id": task_id, "ok": all(check["ok"] for check in checks), "checks": checks}


def grade(run_root: Path, selected: tuple[int, ...]) -> int:
    workspace = run_root / "workspace"
    results = [grade_task(workspace, task_id) for task_id in selected]
    report = {
        "ok": all(result["ok"] for result in results),
        "workspace": str(workspace),
        "tasks": results,
    }
    report_path = run_root / "grade-report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(report_path)
    for result in results:
        failed = [check for check in result["checks"] if not check["ok"]]
        print(f"{result['task_id']}: {'PASS' if not failed else 'FAIL'} ({len(failed)} failed checks)")
        for check in failed:
            print(f"  - {check['name']}: {check['detail']}")
    return 0 if report["ok"] else 1


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvalError(f"Cannot read JSON {path}: {error}") from error


def load_api_key(explicit_path: Path | None) -> str:
    candidates = (explicit_path,) if explicit_path else KEY_FILES
    for path in candidates:
        if path is None:
            continue
        try:
            value = path.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if value:
            return value
    raise EvalError("No TrustedRouter API key found; pass --key-file")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sanitize(value: str, secret: str) -> str:
    return value.replace(secret, "[REDACTED]")


def run_task(
    binary: Path,
    row: dict,
    fixture: dict,
    root: Path,
    key: str,
    timeout: int,
    max_tool_steps: int,
    spend_fuse_usd: float,
    keep_homes: bool,
) -> dict:
    task_id = int(row["id"])
    case_dir = root / "runs" / str(task_id)
    workspace = case_dir / "workspace"
    home = Path(tempfile.mkdtemp(prefix=f"quill-wave6-{task_id}-home-"))
    case_dir.mkdir(parents=True, exist_ok=True)
    prompt = write_task_packet(workspace, task_id, row, fixture)
    prompt_path = case_dir / "prompt.txt"
    report_path = case_dir / "desktop-report.json"
    screenshot_path = case_dir / "desktop-window.png"
    stdout_path = case_dir / "stdout.txt"
    stderr_path = case_dir / "stderr.txt"
    prompt_path.write_text(prompt, encoding="utf-8")
    source_hashes = {
        path: sha256(path) for path in (workspace / "inputs").rglob("*") if path.is_file()
    }
    command = [
        str(binary),
        "--cowork-eval",
        "--cowork-eval-home", str(home),
        "--cowork-eval-workspace", str(workspace),
        "--cowork-eval-prompt-file", str(prompt_path),
        "--cowork-eval-report", str(report_path),
        "--cowork-eval-screenshot", str(screenshot_path),
        "--cowork-eval-model", EXACT_MODEL,
        "--cowork-eval-timeout-seconds", str(timeout),
        "--cowork-eval-max-tool-steps", str(max_tool_steps),
        "--cowork-eval-run-spend-fuse-usd", str(spend_fuse_usd),
    ]
    environment = os.environ.copy()
    environment["QUILLCODE_API_KEY"] = key
    environment.pop("TRUSTEDROUTER_API_KEY", None)
    environment.pop("QUILLCODE_USE_MOCK_LLM", None)

    started = time.monotonic()
    timed_out = False
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
            timeout=timeout + 30,
            check=False,
        )
        exit_code = completed.returncode
        stdout = completed.stdout
        stderr = completed.stderr
    except subprocess.TimeoutExpired as error:
        timed_out = True
        exit_code = 124
        stdout = error.stdout or ""
        stderr = error.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        stderr += f"\nProcess timeout after {timeout + 30} seconds.\n"
    duration_ms = round((time.monotonic() - started) * 1000)
    stdout_path.write_text(sanitize(stdout, key), encoding="utf-8")
    stderr_path.write_text(sanitize(stderr, key), encoding="utf-8")
    report = read_json(report_path) if report_path.exists() else None
    structural = grade_task(workspace, task_id)
    checks = list(structural["checks"])

    def add(name: str, ok: bool, detail: str) -> None:
        checks.append({"name": name, "ok": ok, "detail": detail})

    add(
        "exact requested and selected model",
        bool(
            report
            and report.get("requestedModelID") == EXACT_MODEL
            and report.get("selectedModelID") == EXACT_MODEL
        ),
        repr(
            {
                "requested": report.get("requestedModelID") if report else None,
                "selected": report.get("selectedModelID") if report else None,
            }
        ),
    )
    add(
        "native app completed",
        bool(report and report.get("ok") and report.get("stopReason") == "finished"),
        repr(
            {
                "ok": report.get("ok") if report else None,
                "stopReason": report.get("stopReason") if report else None,
                "timedOut": report.get("timedOut") if report else None,
            }
        ),
    )
    screenshot = report.get("screenshot") if report else None
    add(
        "native desktop window screenshot",
        bool(
            isinstance(screenshot, dict)
            and screenshot.get("path") == str(screenshot_path)
            and screenshot_path.is_file()
            and screenshot_path.stat().st_size > 0
            and screenshot.get("distinctColorBuckets", 0) >= 14
        ),
        repr(screenshot),
    )
    tool_names = [tool.get("name") for tool in report.get("tools", [])] if report else []
    computer_tools = [name for name in tool_names if isinstance(name, str) and name.startswith("host.computer.")]
    add(
        "desktop Firefox Computer Use exercised",
        "host.computer.activate" in computer_tools and "host.computer.screenshot" in computer_tools,
        repr(sorted(set(computer_tools))),
    )
    add(
        "source inputs unchanged",
        all(path.is_file() and sha256(path) == digest for path, digest in source_hashes.items()),
        f"{len(source_hashes)} fixture hashes",
    )
    passed = exit_code == 0 and not timed_out and all(check["ok"] for check in checks)

    if keep_homes:
        retained = case_dir / "home"
        if retained.exists():
            shutil.rmtree(retained)
        shutil.move(str(home), retained)
        home_record = str(retained.relative_to(root))
    else:
        shutil.rmtree(home, ignore_errors=True)
        home_record = None
    return {
        "task_id": task_id,
        "passed": passed,
        "exitCode": exit_code,
        "timedOut": timed_out,
        "durationMilliseconds": duration_ms,
        "usage": report.get("usage", {}) if report else {},
        "tools": tool_names,
        "checks": checks,
        "paths": {
            "workspace": str(workspace.relative_to(root)),
            "report": str(report_path.relative_to(root)) if report_path.exists() else None,
            "screenshot": str(screenshot_path.relative_to(root)) if screenshot_path.exists() else None,
            "stdout": str(stdout_path.relative_to(root)),
            "stderr": str(stderr_path.relative_to(root)),
            "home": home_record,
        },
    }


def write_run_summary(root: Path, results: list[dict]) -> dict:
    results = sorted(results, key=lambda result: result["task_id"])
    usage = {
        key: sum(result.get("usage", {}).get(key, 0) for result in results)
        for key in ("promptTokens", "completionTokens", "totalTokens")
    }
    summary = {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "model": EXACT_MODEL,
        "passed": sum(result["passed"] for result in results),
        "total": len(results),
        "usage": usage,
        "results": results,
    }
    root.mkdir(parents=True, exist_ok=True)
    (root / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    failures = [result for result in results if not result["passed"]]
    lines = [
        "# Wave 6 native Cowork evaluation",
        "",
        f"- Model: `{EXACT_MODEL}`",
        f"- Result: {summary['passed']}/{summary['total']} passed",
        f"- Tokens: {usage['totalTokens']} total",
    ]
    if failures:
        lines.extend(["", "## Failures", ""])
        for result in failures:
            failed = ", ".join(check["name"] for check in result["checks"] if not check["ok"])
            lines.append(f"- {result['task_id']}: {failed}")
    (root / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return summary


def run_tasks(
    binary: Path,
    root: Path,
    selected: tuple[int, ...],
    key: str,
    timeout: int,
    max_tool_steps: int,
    spend_fuse_usd: float,
    keep_homes: bool,
) -> int:
    rows = load_rows()
    fixtures = load_category_fixtures()
    results = []
    for task_id in selected:
        row = rows[task_id]
        try:
            result = run_task(
                binary.resolve(), row, fixtures[row["category"]], root, key, timeout,
                max_tool_steps, spend_fuse_usd, keep_homes,
            )
        except Exception as error:
            result = {
                "task_id": task_id,
                "passed": False,
                "exitCode": None,
                "timedOut": False,
                "durationMilliseconds": 0,
                "usage": {},
                "tools": [],
                "checks": [{"name": "runner exception", "ok": False, "detail": str(error)}],
                "paths": {},
            }
        results.append(result)
        state = "PASS" if result["passed"] else "FAIL"
        print(f"[{len(results)}/{len(selected)}] task {task_id}: {state}", flush=True)
        write_run_summary(root, list(results))
    summary = write_run_summary(root, results)
    print(f"Evidence: {root}")
    print(f"Result: {summary['passed']}/{summary['total']} passed")
    return 0 if summary["passed"] == summary["total"] else 1


def parse_task_ids(raw: str) -> tuple[int, ...]:
    if raw == "all":
        return TASK_IDS
    selected = tuple(int(value) for value in raw.split(",") if value.strip())
    invalid = sorted(set(selected) - set(TASK_IDS))
    if invalid:
        raise EvalError(f"Unknown Wave 6 task IDs: {invalid}")
    return selected


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "grade", "run"))
    parser.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    parser.add_argument("--tasks", default="all", help="all or comma-separated IDs 311-320")
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--model", default=EXACT_MODEL)
    parser.add_argument("--key-file", type=Path)
    parser.add_argument("--timeout", type=int, default=21_600)
    parser.add_argument("--max-tool-steps", type=int, default=4_096)
    parser.add_argument("--spend-fuse-usd", type=float, default=10.0)
    parser.add_argument("--keep-homes", action="store_true")
    args = parser.parse_args()
    selected = parse_task_ids(args.tasks)
    if args.command == "prepare":
        prepare(args.run_root)
        return 0
    if args.command == "grade":
        return grade(args.run_root, selected)
    if args.model != EXACT_MODEL:
        raise EvalError(f"Model must be exactly {EXACT_MODEL}")
    if not args.binary.is_file():
        raise EvalError(f"Desktop binary not found: {args.binary}")
    if not 300 <= args.timeout <= 21_600:
        raise EvalError("--timeout must be between 300 and 21600 seconds")
    if not 1 <= args.max_tool_steps <= 4_096:
        raise EvalError("--max-tool-steps must be between 1 and 4096")
    if not 0 < args.spend_fuse_usd <= 100:
        raise EvalError("--spend-fuse-usd must be between 0 and 100")
    return run_tasks(
        args.binary,
        args.run_root,
        selected,
        load_api_key(args.key_file),
        args.timeout,
        args.max_tool_steps,
        args.spend_fuse_usd,
        args.keep_homes,
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvalError as error:
        print(f"wave6-long-horizon-evals: {error}", file=sys.stderr)
        raise SystemExit(2)
