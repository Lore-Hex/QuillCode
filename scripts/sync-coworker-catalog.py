#!/usr/bin/env python3
"""Normalize a Google Sheets coworker-catalog CSV export into a checked-in contract."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from datetime import date
from pathlib import Path
from typing import Any


CATALOG_SPREADSHEET_URL = (
    "https://docs.google.com/spreadsheets/d/"
    "1uq8uYGwoAxdwPcVn11nysjoozZjKY4acYZNVw-Hu5LM/edit?gid=0#gid=0"
)
REQUIRED_COLUMNS = (
    "ID",
    "Wave",
    "Status",
    "Category",
    "Task (what the person types)",
    "Capability needed",
    "QuillCode coverage",
    "Next QuillCode gap",
    "Last QuillCode review",
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="CSV exported from the canonical Google Sheet")
    parser.add_argument("output", type=Path, help="Normalized JSON contract to write")
    parser.add_argument(
        "--review-date",
        default=date.today().isoformat(),
        help="Review date stored in the contract (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail when output differs instead of writing it",
    )
    return parser.parse_args()


def normalized_catalog(input_path: Path, review_date: str) -> dict[str, Any]:
    source_bytes = input_path.read_bytes()
    with input_path.open("r", encoding="utf-8-sig", newline="") as input_file:
        reader = csv.DictReader(input_file)
        headers = tuple(reader.fieldnames or ())
        missing = [column for column in REQUIRED_COLUMNS if column not in headers]
        if missing:
            raise SystemExit(f"catalog CSV is missing required columns: {', '.join(missing)}")
        source_rows = list(reader)

    rows: list[dict[str, Any]] = []
    for index, source in enumerate(source_rows, start=2):
        try:
            task_id = int(source["ID"])
        except (TypeError, ValueError) as error:
            raise SystemExit(f"catalog CSV row {index} has an invalid ID") from error
        task = (source["Task (what the person types)"] or "").strip()
        if not task:
            raise SystemExit(f"catalog CSV row {index} has an empty task")
        rows.append(
            {
                "id": task_id,
                "wave": (source["Wave"] or "").strip(),
                "sourceStatus": (source["Status"] or "").strip(),
                "category": (source["Category"] or "").strip(),
                "task": task,
                "capabilityNeeded": (source["Capability needed"] or "").strip(),
                "quillCodeCoverage": (source["QuillCode coverage"] or "").strip(),
                "nextQuillCodeGap": (source["Next QuillCode gap"] or "").strip(),
                "lastQuillCodeReview": (source["Last QuillCode review"] or "").strip(),
            }
        )

    task_ids = [row["id"] for row in rows]
    if len(task_ids) != len(set(task_ids)):
        raise SystemExit("catalog CSV contains duplicate task IDs")
    expected_ids = list(range(1, len(task_ids) + 1))
    if task_ids != expected_ids:
        raise SystemExit(
            "catalog task IDs must be ordered and contiguous from 1; "
            f"found {task_ids[:3]}...{task_ids[-3:]}"
        )

    status_counts = Counter(row["sourceStatus"] for row in rows)
    coverage_counts = Counter(row["quillCodeCoverage"] for row in rows)
    return {
        "catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL,
        "reviewDate": review_date,
        "sourceSHA256": hashlib.sha256(source_bytes).hexdigest(),
        "rowCount": len(rows),
        "taskIDs": task_ids,
        "sourceStatusCounts": dict(sorted(status_counts.items())),
        "quillCodeCoverageCounts": dict(sorted(coverage_counts.items())),
        "rows": rows,
    }


def encoded_catalog(catalog: dict[str, Any]) -> str:
    return json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"


def main() -> None:
    arguments = parse_arguments()
    rendered = encoded_catalog(normalized_catalog(arguments.input, arguments.review_date))
    if arguments.check:
        if not arguments.output.exists() or arguments.output.read_text(encoding="utf-8") != rendered:
            raise SystemExit(
                f"{arguments.output} is stale; run {Path(__file__).name} without --check"
            )
        return
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(rendered, encoding="utf-8")


if __name__ == "__main__":
    main()
