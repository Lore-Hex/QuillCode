#!/usr/bin/env python3
"""Run a bounded, secret-free live agentic eval against TrustedRouter."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = ROOT / "docs" / "cheap-agentic-eval-catalog.json"
DEFAULT_BINARY = ROOT / ".build" / "debug" / "quill-code"
EXACT_MODEL = "deepseek/deepseek-v4-flash-0731"
ALLOWED_CATEGORIES = {"cybersecurity", "biology", "ai", "evals", "agentic"}
ALLOWED_GRADERS = {
    "json_file_equals",
    "json_file_subset",
    "text_file_equals",
    "text_file_lines_equal",
    "file_excludes",
    "setup_file_unchanged",
    "command_succeeds",
}
ALLOWED_COMMANDS = {"python3"}
DEFAULT_KEY_FILES = (
    Path.home() / ".quillcode" / "secrets" / "trustedrouter_api_key",
    Path.home() / ".quill.code.keyfile",
)


class EvalError(RuntimeError):
    pass


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run low-cost objective agentic evals with an exact-model and call-count fuse."
    )
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--model", default=EXACT_MODEL)
    parser.add_argument("--trials", type=int)
    parser.add_argument("--case", action="append", dest="case_ids", default=[])
    parser.add_argument("--key-file", type=Path)
    parser.add_argument("--artifact-dir", type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--keep-homes", action="store_true")
    return parser.parse_args()


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvalError(f"Cannot read JSON {path}: {error}") from error


def relative_path(root, raw):
    candidate = Path(raw)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise EvalError(f"Unsafe relative path: {raw}")
    root = root.resolve()
    resolved = (root / candidate).resolve()
    if os.path.commonpath((str(root), str(resolved))) != str(root):
        raise EvalError(f"Path escapes workspace: {raw}")
    return resolved


def validate_catalog(catalog):
    if catalog.get("version") != 1:
        raise EvalError("Catalog version must be 1")
    if catalog.get("taskModel") != EXACT_MODEL:
        raise EvalError(f"Catalog taskModel must be {EXACT_MODEL}")
    max_calls = catalog.get("maxPaidInvocations")
    max_prompt = catalog.get("maxPromptCharacters")
    default_trials = catalog.get("defaultTrials")
    if not isinstance(max_calls, int) or not 1 <= max_calls <= 24:
        raise EvalError("maxPaidInvocations must be between 1 and 24")
    if not isinstance(max_prompt, int) or not 1 <= max_prompt <= 320:
        raise EvalError("maxPromptCharacters must be between 1 and 320")
    if not isinstance(default_trials, int) or default_trials < 1:
        raise EvalError("defaultTrials must be positive")

    cases = catalog.get("cases")
    if not isinstance(cases, list) or not cases:
        raise EvalError("Catalog cases must be a nonempty array")
    ids = set()
    for case in cases:
        case_id = case.get("id")
        if not isinstance(case_id, str) or not case_id:
            raise EvalError("Each case needs a nonempty id")
        if case_id in ids:
            raise EvalError(f"Duplicate case id: {case_id}")
        ids.add(case_id)
        if case.get("category") not in ALLOWED_CATEGORIES:
            raise EvalError(f"{case_id}: unsupported category")
        if case.get("sandbox") not in {"read-only", "workspace-write"}:
            raise EvalError(f"{case_id}: unsafe sandbox")
        prompt = case.get("prompt")
        if not isinstance(prompt, str) or not prompt.strip():
            raise EvalError(f"{case_id}: missing prompt")
        if len(prompt) > max_prompt:
            raise EvalError(f"{case_id}: prompt exceeds {max_prompt} characters")
        files = case.get("files")
        if not isinstance(files, dict) or not files:
            raise EvalError(f"{case_id}: files must be a nonempty object")
        for path, text in files.items():
            relative_path(Path("/private/tmp/catalog-root"), path)
            if not isinstance(text, str):
                raise EvalError(f"{case_id}: setup file {path} must be text")
        graders = case.get("graders")
        if not isinstance(graders, list) or not graders:
            raise EvalError(f"{case_id}: graders must be nonempty")
        for grader in graders:
            grader_type = grader.get("type")
            if grader_type not in ALLOWED_GRADERS:
                raise EvalError(f"{case_id}: unsupported grader {grader_type}")
            if grader_type == "command_succeeds":
                argv = grader.get("argv")
                if (
                    not isinstance(argv, list)
                    or len(argv) != 2
                    or argv[0] not in ALLOWED_COMMANDS
                    or argv[1] not in files
                ):
                    raise EvalError(f"{case_id}: command grader is not allowlisted")
            else:
                relative_path(Path("/private/tmp/catalog-root"), grader.get("path", ""))
    return cases


def select_cases(cases, requested):
    if not requested:
        return cases
    by_id = {case["id"]: case for case in cases}
    unknown = sorted(set(requested) - set(by_id))
    if unknown:
        raise EvalError(f"Unknown case id(s): {', '.join(unknown)}")
    requested_set = set(requested)
    return [case for case in cases if case["id"] in requested_set]


def load_api_key(explicit_path):
    value = os.environ.get("QUILLCODE_API_KEY") or os.environ.get("TRUSTEDROUTER_API_KEY")
    if value and value.strip():
        return value.strip(), "environment"
    paths = (explicit_path,) if explicit_path else DEFAULT_KEY_FILES
    for path in paths:
        if path and path.is_file():
            value = path.read_text(encoding="utf-8").strip()
            if value:
                return value, "key-file"
    raise EvalError(
        "No TrustedRouter key found in QUILLCODE_API_KEY, TRUSTEDROUTER_API_KEY, "
        "or the supported key files"
    )


def prepare_artifact_dir(raw_path):
    if raw_path:
        path = raw_path if raw_path.is_absolute() else ROOT / raw_path
    else:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        path = ROOT / ".build" / "quillcode-validation" / "cheap-agentic-evals" / stamp
    if path.exists() and (not path.is_dir() or any(path.iterdir())):
        raise EvalError(f"Artifact directory must be absent or empty: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def write_setup_files(workspace, files):
    hashes = {}
    for raw_path, text in files.items():
        path = relative_path(workspace, raw_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        hashes[raw_path] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def json_matches_subset(actual, expected):
    if not isinstance(actual, dict):
        return False
    return all(key in actual and actual[key] == value for key, value in expected.items())


def grade_case(case, workspace, setup_hashes):
    results = []
    for grader in case["graders"]:
        grader_type = grader["type"]
        detail = ""
        passed = False
        try:
            if grader_type in {"json_file_equals", "json_file_subset"}:
                path = relative_path(workspace, grader["path"])
                actual = read_json(path)
                expected = grader["expected"]
                passed = (
                    actual == expected
                    if grader_type == "json_file_equals"
                    else json_matches_subset(actual, expected)
                )
                detail = "matched" if passed else f"expected {expected!r}, got {actual!r}"
            elif grader_type == "text_file_equals":
                actual = relative_path(workspace, grader["path"]).read_text(encoding="utf-8")
                passed = actual == grader["expected"]
                detail = "matched" if passed else "text did not match exactly"
            elif grader_type == "text_file_lines_equal":
                actual = relative_path(workspace, grader["path"]).read_text(encoding="utf-8")
                passed = actual.splitlines() == grader["expected"].splitlines()
                detail = "matched lines" if passed else "text lines did not match"
            elif grader_type == "file_excludes":
                actual = relative_path(workspace, grader["path"]).read_text(encoding="utf-8")
                passed = grader["text"] not in actual
                detail = "excluded" if passed else "forbidden text remained"
            elif grader_type == "setup_file_unchanged":
                path = relative_path(workspace, grader["path"])
                actual_hash = hashlib.sha256(path.read_bytes()).hexdigest()
                passed = actual_hash == setup_hashes[grader["path"]]
                detail = "unchanged" if passed else "setup file changed"
            elif grader_type == "command_succeeds":
                completed = subprocess.run(
                    grader["argv"],
                    cwd=workspace,
                    capture_output=True,
                    text=True,
                    timeout=30,
                    check=False,
                    env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")},
                )
                passed = completed.returncode == 0
                detail = (
                    completed.stdout.strip()[-300:]
                    if passed
                    else (completed.stdout + completed.stderr).strip()[-300:]
                )
        except (OSError, EvalError, ValueError, subprocess.TimeoutExpired) as error:
            detail = str(error)
        results.append({"type": grader_type, "passed": passed, "detail": detail})
    return results


def parse_events(stdout):
    records = []
    invalid_lines = 0
    for line in stdout.splitlines():
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            invalid_lines += 1
    completion = next(
        (record for record in reversed(records) if record.get("type") == "turn.completed"),
        None,
    )
    completed_tools = [
        record.get("item", {}).get("name")
        for record in records
        if record.get("type") == "item.completed"
        and record.get("item", {}).get("status") == "completed"
        and record.get("item", {}).get("name")
    ]
    return completion, completed_tools, invalid_lines


def sanitize(text, secret):
    return text.replace(secret, "[REDACTED]")


def run_trial(binary, model, case, trial, artifact_dir, key, timeout, keep_homes):
    case_dir = artifact_dir / "runs" / f"trial-{trial}" / case["id"]
    workspace = case_dir / "workspace"
    case_dir.mkdir(parents=True)
    workspace.mkdir()
    home = Path(tempfile.mkdtemp(prefix=f"quill-eval-{case['id']}-home-"))
    setup_hashes = write_setup_files(workspace, case["files"])
    stdout_path = case_dir / "events.jsonl"
    stderr_path = case_dir / "stderr.txt"
    final_path = case_dir / "final.txt"
    command = [
        str(binary),
        "--home",
        str(home),
        "exec",
        "--json",
        "--ephemeral",
        "--live",
        "--model",
        model,
        "--sandbox",
        case["sandbox"],
        "--skip-git-repo-check",
        "--ignore-user-config",
        "--ignore-rules",
        "--cwd",
        str(workspace),
        "--output-last-message",
        str(final_path),
        case["prompt"],
    ]
    child_env = os.environ.copy()
    child_env["QUILLCODE_API_KEY"] = key
    child_env.pop("TRUSTEDROUTER_API_KEY", None)

    started = time.monotonic()
    timed_out = False
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            env=child_env,
            capture_output=True,
            text=True,
            timeout=timeout,
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
        stderr += f"\nTimed out after {timeout} seconds.\n"
    duration_ms = round((time.monotonic() - started) * 1000)

    stdout_path.write_text(sanitize(stdout, key), encoding="utf-8")
    stderr_path.write_text(sanitize(stderr, key), encoding="utf-8")
    if final_path.exists():
        final_path.write_text(
            sanitize(final_path.read_text(encoding="utf-8", errors="replace"), key),
            encoding="utf-8",
        )
    completion, completed_tools, invalid_lines = parse_events(stdout)
    graders = grade_case(case, workspace, setup_hashes)
    lifecycle_ok = completion is not None and exit_code == 0 and not timed_out
    passed = lifecycle_ok and all(grader["passed"] for grader in graders)
    usage = (completion or {}).get("usage", {})

    if not keep_homes:
        shutil.rmtree(home, ignore_errors=True)
        home_record = None
    else:
        retained_home = case_dir / "home"
        shutil.move(str(home), retained_home)
        home_record = str(retained_home.relative_to(artifact_dir))

    return {
        "case": case["id"],
        "category": case["category"],
        "trial": trial,
        "passed": passed,
        "lifecyclePassed": lifecycle_ok,
        "exitCode": exit_code,
        "timedOut": timed_out,
        "durationMs": duration_ms,
        "usage": usage,
        "completedTools": completed_tools,
        "invalidJSONLines": invalid_lines,
        "graders": graders,
        "paths": {
            "events": str(stdout_path.relative_to(artifact_dir)),
            "stderr": str(stderr_path.relative_to(artifact_dir)),
            "final": str(final_path.relative_to(artifact_dir)) if final_path.exists() else None,
            "workspace": str(workspace.relative_to(artifact_dir)),
            "home": home_record,
        },
    }


def trial_scores(results):
    scores = {}
    trials = sorted({result["trial"] for result in results})
    for trial in trials:
        trial_results = [result for result in results if result["trial"] == trial]
        categories = {}
        for category in sorted(ALLOWED_CATEGORIES):
            items = [result for result in trial_results if result["category"] == category]
            if items:
                categories[category] = {
                    "passed": sum(item["passed"] for item in items),
                    "total": len(items),
                }
        scores[str(trial)] = {
            "passed": sum(item["passed"] for item in trial_results),
            "total": len(trial_results),
            "categories": categories,
        }
    return scores


def reproducibility(results, scores):
    grouped = defaultdict(list)
    for result in results:
        grouped[result["case"]].append(result["passed"])
    outcome_agreement = all(len(set(outcomes)) == 1 for outcomes in grouped.values())
    score_vectors = [
        (
            score["passed"],
            tuple(
                (name, value["passed"], value["total"])
                for name, value in sorted(score["categories"].items())
            ),
        )
        for score in scores.values()
    ]
    return {
        "outcomeAgreement": outcome_agreement,
        "identicalScoreVectors": len(set(score_vectors)) <= 1,
    }


def redact_secret_from_tree(root, secret):
    leaked = []
    needle = secret.encode("utf-8")
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        data = path.read_bytes()
        if needle in data:
            leaked.append(str(path.relative_to(root)))
            path.write_bytes(data.replace(needle, b"[REDACTED]"))
    return leaked


def main():
    args = parse_args()
    catalog = read_json(args.catalog.resolve())
    cases = validate_catalog(catalog)
    selected = select_cases(cases, args.case_ids)
    trials = args.trials if args.trials is not None else catalog["defaultTrials"]
    if trials < 1:
        raise EvalError("--trials must be positive")
    paid_invocations = len(selected) * trials
    if paid_invocations > catalog["maxPaidInvocations"]:
        raise EvalError(
            f"Refusing {paid_invocations} paid invocations; cap is "
            f"{catalog['maxPaidInvocations']}"
        )
    if args.model != EXACT_MODEL:
        raise EvalError(f"Refusing non-pinned task model: {args.model}")
    if args.validate_only:
        print(
            f"Catalog valid: {len(cases)} cases, {paid_invocations} selected invocations, "
            f"task model {EXACT_MODEL}"
        )
        return 0

    binary = args.binary.resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise EvalError(f"CLI binary is not executable: {binary}")
    key, key_source = load_api_key(args.key_file)
    artifact_dir = prepare_artifact_dir(args.artifact_dir)
    results = []
    print(
        f"Running {len(selected)} cases x {trials} trials "
        f"({paid_invocations}/{catalog['maxPaidInvocations']} call cap)"
    )
    try:
        for trial in range(1, trials + 1):
            for case in selected:
                result = run_trial(
                    binary,
                    args.model,
                    case,
                    trial,
                    artifact_dir,
                    key,
                    args.timeout,
                    args.keep_homes,
                )
                results.append(result)
                mark = "PASS" if result["passed"] else "FAIL"
                print(
                    f"[{mark}] trial {trial} {case['id']} "
                    f"({result['durationMs']} ms)",
                    flush=True,
                )

        scores = trial_scores(results)
        reproducible = reproducibility(results, scores)
        manifest = {
            "schemaVersion": 1,
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "status": "passed" if all(result["passed"] for result in results) else "failed",
            "taskModel": args.model,
            "transport": "TrustedRouter",
            "keySource": key_source,
            "secretFree": True,
            "catalog": str(args.catalog.resolve()),
            "catalogVersion": catalog["version"],
            "limits": {
                "maxPaidInvocations": catalog["maxPaidInvocations"],
                "paidInvocations": paid_invocations,
                "maxPromptCharacters": catalog["maxPromptCharacters"],
            },
            "scope": {
                "syntheticDataOnly": True,
                "defensiveCybersecurityOnly": True,
                "nonClinicalBiologyOnly": True,
                "productionSafetyPolicy": True,
            },
            "scores": scores,
            "reproducibility": reproducible,
            "usage": {
                "inputTokens": sum(
                    int(result["usage"].get("input_tokens", 0)) for result in results
                ),
                "outputTokens": sum(
                    int(result["usage"].get("output_tokens", 0)) for result in results
                ),
            },
            "results": results,
        }
        manifest_path = artifact_dir / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        leaked = redact_secret_from_tree(artifact_dir, key)
        if leaked:
            manifest["status"] = "failed"
            manifest["secretFree"] = False
            manifest["secretLeakFileCount"] = len(leaked)
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            raise EvalError(
                f"Secret scan found and redacted key material in {len(leaked)} artifact file(s)"
            )
        print(json.dumps({"scores": scores, "reproducibility": reproducible}, indent=2))
        print(f"Evidence: {manifest_path}")
        return 0 if manifest["status"] == "passed" and all(reproducible.values()) else 1
    except BaseException:
        redact_secret_from_tree(artifact_dir, key)
        raise


if __name__ == "__main__":
    try:
        sys.exit(main())
    except EvalError as error:
        print(f"cheap-agentic-evals: {error}", file=sys.stderr)
        sys.exit(2)
