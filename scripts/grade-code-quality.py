#!/usr/bin/env python3
"""Generate a deterministic per-file and per-module code quality report.

The grader is intentionally heuristic: it highlights maintainability risk that is
cheap to measure and useful during review. It does not replace human judgment.
"""

from __future__ import annotations

import argparse
import dataclasses
import re
from collections import Counter, defaultdict
from pathlib import Path


CODE_ROOTS = ("Sources", "Tests", "E2E/playwright/tests", "scripts")
CODE_SUFFIXES = {".swift", ".ts", ".js", ".py", ".sh"}
IGNORED_NAMES = {"package-lock.json"}
OPEN_ITEM_PATTERN = r"\b(" + "TO" + "DO|FIX" + "ME" + r")\b"
UNSAFE_MARKER_PATTERN = "|".join([
    "try" + "!",
    "as" + "!",
    r"fatalError\(",
])


@dataclasses.dataclass(frozen=True)
class FileGrade:
    path: str
    module: str
    score: int
    grade: str
    lines: int
    issue_summary: str


def grade_name(score: int) -> str:
    if score >= 96:
        return "A+"
    if score >= 92:
        return "A"
    if score >= 88:
        return "A-"
    if score >= 84:
        return "B+"
    if score >= 80:
        return "B"
    if score >= 76:
        return "B-"
    if score >= 72:
        return "C+"
    if score >= 68:
        return "C"
    if score >= 64:
        return "C-"
    return "D"


def module_name(path: Path) -> str:
    parts = path.parts
    if len(parts) >= 2 and parts[0] == "Sources":
        return f"source:{parts[1]}"
    if len(parts) >= 2 and parts[0] == "Tests":
        return f"test:{parts[1]}"
    if len(parts) >= 3 and parts[:3] == ("E2E", "playwright", "tests"):
        return "e2e:playwright"
    if parts and parts[0] == "scripts":
        return "scripts"
    return "other"


def issue_count(pattern: str, text: str) -> int:
    return len(re.findall(pattern, text, flags=re.MULTILINE))


def swift_text_without_multiline_string_payloads(text: str) -> str:
    """Keep Swift source structure while ignoring embedded fixture payloads.

    Many parity tests embed sample Swift/HTML/script bodies in multiline string
    literals. Those payloads are important test data, but counting their braces,
    long lines, duplicate indentation, and fake top-level types as test-source
    complexity makes the grade less useful. The source line count still uses the
    real file; this helper only feeds structural heuristics.
    """

    rendered: list[str] = []
    inside_multiline_literal = False

    for line in text.splitlines():
        if '"""' not in line:
            if not inside_multiline_literal:
                rendered.append(line)
            continue

        marker_count = line.count('"""')
        if inside_multiline_literal:
            suffix = line.rsplit('"""', 1)[-1]
            rendered.append('"""' + suffix)
        else:
            prefix = line.split('"""', 1)[0]
            rendered.append(prefix + '"""')

        if marker_count % 2 == 1:
            inside_multiline_literal = not inside_multiline_literal

    return "\n".join(rendered)


def analysis_text(relative_path: Path, text: str) -> str:
    if relative_path.suffix == ".swift":
        return swift_text_without_multiline_string_payloads(text)
    return text


def duplicate_line_ratio(lines: list[str]) -> float:
    normalized = [
        line.strip()
        for line in lines
        if len(line.strip()) >= 24 and not line.strip().startswith(("//", "#", "*"))
    ]
    if not normalized:
        return 0.0
    counts = Counter(normalized)
    repeated = sum(count for count in counts.values() if count > 1)
    return repeated / len(normalized)


def score_file(root: Path, relative_path: Path) -> FileGrade:
    path = root / relative_path
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    structural_text = analysis_text(relative_path, text)
    structural_lines = structural_text.splitlines()
    line_count = len(lines)
    long_lines = sum(1 for line in structural_lines if len(line) > 120)
    very_long_lines = sum(1 for line in structural_lines if len(line) > 160)
    duplicate_ratio = duplicate_line_ratio(structural_lines)
    open_item_count = issue_count(OPEN_ITEM_PATTERN, structural_text)
    unsafe_markers = issue_count(UNSAFE_MARKER_PATTERN, structural_text)
    force_unwrap_markers = issue_count(r"[A-Za-z0-9_\)\]]!\s*(\.|\)|,|\]|$)", structural_text)
    public_decl_count = issue_count(
        r"^\s*public\s+(struct|enum|class|actor|protocol|func|var|let)\b",
        structural_text,
    )
    top_level_type_count = issue_count(r"^\s*(public\s+)?(struct|enum|class|actor|protocol)\b", structural_text)

    score = 100
    issues: list[str] = []
    source_root = relative_path.parts[0] if relative_path.parts else ""
    is_test = source_root == "Tests"

    size_limits = (650, 900, 1200) if is_test else (350, 550, 800)
    if line_count > size_limits[2]:
        score -= 10
        issues.append(f"very large file ({line_count} lines)")
    elif line_count > size_limits[1]:
        score -= 6
        issues.append(f"large file ({line_count} lines)")
    elif line_count > size_limits[0]:
        score -= 3
        issues.append(f"watch file size ({line_count} lines)")

    if long_lines:
        penalty = min(8, 1 + long_lines // 8)
        score -= penalty
        issues.append(f"{long_lines} lines >120 chars")
    if very_long_lines:
        score -= min(6, very_long_lines)
        issues.append(f"{very_long_lines} lines >160 chars")
    duplicate_ratio_should_penalize = not is_test or line_count > 240
    if duplicate_ratio_should_penalize and duplicate_ratio >= 0.24:
        score -= 8
        issues.append(f"high duplicate-line ratio ({duplicate_ratio:.0%})")
    elif duplicate_ratio_should_penalize and duplicate_ratio >= 0.16:
        score -= 4
        issues.append(f"duplicate-line ratio ({duplicate_ratio:.0%})")
    if open_item_count:
        score -= min(8, open_item_count * 2)
        issues.append(f"{open_item_count} open follow-up marker")
    if unsafe_markers:
        score -= min(12, unsafe_markers * 4)
        issues.append(f"{unsafe_markers} unsafe marker")
    if force_unwrap_markers and source_root == "Sources":
        score -= min(12, force_unwrap_markers * 3)
        issues.append(f"{force_unwrap_markers} force-unwrap marker")
    if public_decl_count > 12 and not is_test:
        score -= 3
        issues.append(f"{public_decl_count} public declarations")
    if top_level_type_count > 10:
        score -= 3
        issues.append(f"{top_level_type_count} top-level types")

    score = max(0, min(100, score))
    issue_summary = "; ".join(issues) if issues else "no automated issues"
    return FileGrade(
        path=relative_path.as_posix(),
        module=module_name(relative_path),
        score=score,
        grade=grade_name(score),
        lines=line_count,
        issue_summary=issue_summary,
    )


def iter_code_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for code_root in CODE_ROOTS:
        base = root / code_root
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.name in IGNORED_NAMES:
                continue
            if path.suffix in CODE_SUFFIXES:
                files.append(path.relative_to(root))
    return sorted(files, key=lambda path: path.as_posix())


def render_markdown(grades: list[FileGrade]) -> str:
    by_module: dict[str, list[FileGrade]] = defaultdict(list)
    for grade in grades:
        by_module[grade.module].append(grade)

    lines: list[str] = [
        "# Code Quality File Grades",
        "",
        "Generated by `scripts/grade-code-quality.py`. Grades are deterministic heuristics for maintainability review, not a substitute for human code review.",
        "",
        "## Module Summary",
        "",
        "| Module | Files | Lines | Avg Score | Grade | Lowest Files |",
        "| --- | ---: | ---: | ---: | --- | --- |",
    ]
    for module in sorted(by_module):
        module_grades = by_module[module]
        total_lines = sum(grade.lines for grade in module_grades)
        avg_score = round(sum(grade.score for grade in module_grades) / len(module_grades))
        lowest = sorted(module_grades, key=lambda grade: (grade.score, -grade.lines, grade.path))[:3]
        lowest_text = "<br>".join(f"`{Path(item.path).name}` {item.grade}" for item in lowest)
        lines.append(
            f"| `{module}` | {len(module_grades)} | {total_lines} | {avg_score} | {grade_name(avg_score)} | {lowest_text} |"
        )

    lines.extend([
        "",
        "## Lowest Scored Files",
        "",
        "| Grade | Score | Lines | Module | File | Main Issues |",
        "| --- | ---: | ---: | --- | --- | --- |",
    ])
    for grade in sorted(grades, key=lambda item: (item.score, -item.lines, item.path))[:40]:
        lines.append(
            f"| {grade.grade} | {grade.score} | {grade.lines} | `{grade.module}` | `{grade.path}` | {grade.issue_summary} |"
        )

    lines.extend([
        "",
        "## Every File",
        "",
        "| Grade | Score | Lines | Module | File | Main Issues |",
        "| --- | ---: | ---: | --- | --- | --- |",
    ])
    for grade in sorted(grades, key=lambda item: (item.module, item.path)):
        lines.append(
            f"| {grade.grade} | {grade.score} | {grade.lines} | `{grade.module}` | `{grade.path}` | {grade.issue_summary} |"
        )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="Repository root to grade.")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    grades = [score_file(root, path) for path in iter_code_files(root)]
    print(render_markdown(grades))


if __name__ == "__main__":
    main()
