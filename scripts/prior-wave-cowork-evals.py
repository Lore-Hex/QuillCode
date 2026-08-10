#!/usr/bin/env python3
"""Drive Waves 1-4 through the visible native Quill Cowork controller.

Every catalog prompt is preserved verbatim. The appended evaluation contract redirects
filesystem and authenticated-service side effects into an isolated per-case workspace,
while confidential and scheduling tasks exercise their real native product modes.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import io
import json
import os
import posixpath
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
import zlib
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "docs" / "coworker-task-catalog.json"
DEFAULT_BINARY = ROOT / ".build" / "debug" / "quill-code-desktop"
EXACT_MODEL = "deepseek/deepseek-v4-flash-0731"
EXPECTED_IDS = set(range(1, 211))
BROWSER_CAPABILITIES = {"Browser pane"}
KEY_FILES = (
    Path.home() / ".quillcode" / "secrets" / "trustedrouter_api_key",
    Path.home() / ".quill.code.keyfile",
)

# The requested artifact is part of the behavioral contract. A spreadsheet, image,
# document, or machine-readable export must not pass as a prose Markdown summary.
CSV_TASKS = {
    1, 2, 6, 9, 11, 12, 13, 16, 18, 21, 23, 25, 26, 30, 31, 36, 43,
    47, 48, 49, 50, 53, 54, 58, 59, 61, 65, 68, 72, 73, 75, 76, 81,
    83, 84, 86, 88, 89, 90, 91, 93, 94, 98, 100, 102, 104, 106, 109,
    110, 121, 124, 132, 136, 145, 147, 153, 163, 170, 177, 186,
    189, 193, 197, 198, 200, 204, 205, 207, 208, 209,
}
XLSX_TASKS = {19, 62, 63, 74, 158}
PDF_TASKS = {5, 42}
PNG_TASKS = {20}
HTML_TASKS = {40, 82, 117}
DOCX_TASKS = {64}
MERMAID_TASKS = {28}
REUSABLE_TEMPLATE_TASKS = {60, 202}

FORMAT_INSTRUCTIONS = {
    "csv": (
        "Write valid UTF-8 CSV with one header row and one data row per requested record. "
        "Keep prose out of the CSV and use explicit status or notes columns for uncertainty."
    ),
    "xlsx": (
        "Create a real Office Open XML workbook, not CSV or Markdown renamed to .xlsx. "
        "Include the requested sheets, formulas or rollups, and usable column headers. "
        "After reopening it, inspect every formula dependency: quote sheet names containing "
        "spaces, correct references to missing or text-header cells, and remove circular references."
    ),
    "pdf": (
        "Create a real readable PDF beginning with the PDF signature, with the requested "
        "content and page structure. Do not write plain text with a .pdf extension."
    ),
    "png": (
        "Create a real PNG image at least 800 pixels wide with the requested chart or visual. "
        "Do not substitute a text description of the image."
    ),
    "html": (
        "Create a complete single-file HTML document with semantic HTML, embedded styles, "
        "and the requested visible content."
    ),
    "docx": (
        "Create a real Office Open XML Word document, not plain text renamed to .docx, and "
        "preserve the source facts the task says must remain exact."
    ),
    "mmd": "Write syntactically valid Mermaid source beginning with a diagram declaration.",
    "md": (
        "Write decision-ready Markdown with clear headings and at least one useful table or "
        "list where the task benefits from structure."
    ),
}

# Sources described as collections rather than explicit filenames need concrete files
# so the model exercises listing, batching, and aggregation instead of summarizing the
# generic context packet. Each tuple is (original description, mapped directory, count,
# extension). Explicitly named files are materialized separately.
COLLECTION_SPECS = {
    1: [("~/Brand/Assets", "inputs/Brand/Assets", 8, ".png")],
    4: [("home folder", "inputs/home-folder", 8, ".bin")],
    5: [("every .docx in ~/Board/July", "inputs/Board/July", 5, ".docx")],
    6: [("nine regional PDF sales reports", "inputs/regional-sales", 9, ".pdf")],
    8: [("/weekly-notes/2026-07", "inputs/weekly-notes/2026-07", 5, ".md")],
    11: [("three bank statement PDFs", "inputs/bank-statements", 3, ".pdf")],
    13: [("12 monthly Chase statement PDFs", "inputs/chase-statements", 12, ".pdf")],
    17: [("Client Files", "inputs/Client Files", 8, ".txt")],
    18: [("Bronze, Silver, and Gold medical plan PDFs", "inputs/medical-plans", 3, ".pdf")],
    24: [("12 unanswered tickets", "inputs/support-tickets", 12, ".eml")],
    29: [("closing binder exhibits", "inputs/closing-binder-exhibits", 12, ".pdf")],
    32: [("Downloads folder", "inputs/Downloads", 12, ".txt")],
    39: [("~/Newsletter/July", "inputs/Newsletter/July", 8, ".png")],
    57: [("20-slide product deck", "inputs/product-deck", 20, ".md")],
    58: [("scanned 1994 pension plan booklet", "inputs/pension-booklet", 12, ".png")],
    66: [("~/Shared", "inputs/Shared", 8, ".txt")],
    68: [("files edited this week", "inputs/weekly-work", 12, ".md")],
    69: [("/reorg-qa", "inputs/reorg-qa", 8, ".md")],
    70: [("/analyst-reports", "inputs/analyst-reports", 3, ".pdf")],
    71: [("~/Documents/Invoices", "inputs/Documents/Invoices", 8, ".pdf")],
    73: [("30 subcontractor COI PDFs", "inputs/coi-pdfs", 30, ".pdf")],
    74: [("14 vendor contracts in ~/Contracts/2026", "inputs/Contracts/2026", 14, ".pdf")],
    75: [("fourteen monthly store-sales spreadsheets", "inputs/Reports/2025", 14, ".xlsx")],
    76: [("40 steering meeting notes", "inputs/notes/steering", 40, ".md")],
    78: [("~/Dropbox/Proposals", "inputs/Dropbox/Proposals", 8, ".docx")],
    79: [("six onboarding docs", "inputs/onboarding", 6, ".docx")],
    80: [("receipt PDFs in ~/Expenses/June", "inputs/Expenses/June", 12, ".pdf")],
    81: [("twelve monthly Stripe payout CSVs", "inputs/Finance/2026", 12, ".csv")],
    83: [("invoice PDFs in Invoices/2026-Q2", "inputs/Invoices/2026-Q2", 12, ".pdf")],
    84: [("34 resumes in ~/Recruiting/analyst-2026", "inputs/Recruiting/analyst-2026", 34, ".pdf")],
    86: [(".eml files in ~/Desktop/inbox-export", "inputs/Desktop/inbox-export", 12, ".eml")],
    87: [("steps and screenshots in /docs/procurement", "inputs/docs/procurement", 8, ".png")],
    88: [("three warehouse count CSVs", "inputs/warehouse-counts", 3, ".csv")],
    89: [("60 invoice PDFs", "inputs/invoice-pdfs", 60, ".pdf")],
    90: [("three vendor DPAs in Legal/DPAs", "inputs/Legal/DPAs", 3, ".docx")],
    93: [("last 8 board minutes PDFs", "inputs/board-minutes", 8, ".pdf")],
    96: [("customer interview notes in /research/interviews", "inputs/research/interviews", 8, ".md")],
    97: [("past responses in /proposals", "inputs/proposals", 8, ".md")],
    98: [("200 freight invoice PDFs", "inputs/freight-invoices", 200, ".pdf")],
    99: [("fifteen account folders under /accounts", "inputs/accounts", 15, ".md")],
    100: [("9 papers in ~/Research/retention", "inputs/Research/retention", 9, ".pdf")],
    101: [("retro notes for sprints 18 through 22", "inputs/retro-notes", 5, ".md")],
    102: [("four vendor proposals in /rfp-responses", "inputs/rfp-responses", 4, ".pdf")],
    103: [("screenshots on Desktop", "inputs/Desktop/screenshots", 12, ".png")],
    104: [("Documents and Desktop files", "inputs/Documents-and-Desktop", 12, ".md")],
    106: [("30 SaaS invoice PDFs in ~/Invoices", "inputs/Invoices", 30, ".pdf")],
    107: [("six status docs in /q3-projects", "inputs/q3-projects", 6, ".md")],
    108: [("12 team update docs in ~/status/week-30", "inputs/status/week-30", 12, ".md")],
    109: [("meeting notes in ~/Notes/2026-Q3", "inputs/Notes/2026-Q3", 12, ".md")],
    110: [("three team KPI trackers in /Ops/trackers", "inputs/Ops/trackers", 3, ".xlsx")],
    120: [("5 reseller agreements", "inputs/reseller-agreements", 5, ".pdf")],
    130: [("docs in /compliance", "inputs/compliance", 4, ".docx")],
    142: [("vendor security questionnaire response PDF", "inputs/vendor-security", 1, ".pdf")],
    145: [("resumes in ~/Hiring/DesignLead", "inputs/Hiring/DesignLead", 8, ".pdf")],
    146: [("five onsite candidates in /interviews", "inputs/interviews", 5, ".md")],
    149: [("current MSA and vendor redline", "inputs/msa-redlines", 2, ".docx")],
    150: [("60-page Northwind MSA", "inputs/northwind-msa", 12, ".pdf")],
    152: [("term sheet PDF", "inputs/term-sheet", 1, ".pdf")],
    154: [("/northwind email thread", "inputs/northwind", 8, ".eml")],
    155: [("last all-hands transcript", "inputs/all-hands", 1, ".txt")],
    159: [("HR/exits/Q2", "inputs/HR/exits/Q2", 8, ".md")],
    160: [("1:1 notes", "inputs/one-on-one-notes", 8, ".md")],
    161: [("~/HR/Exits", "inputs/HR/Exits", 12, ".md")],
    163: [("three health plan quotes in /benefits-quotes", "inputs/benefits-quotes", 3, ".pdf")],
    166: [("counterparty NDA and standard template", "inputs/nda-redline", 2, ".docx")],
    169: [("/shared/customer-escalations", "inputs/shared/customer-escalations", 8, ".md")],
    177: [("40 resumes in ~/Hiring/PM-role", "inputs/Hiring/PM-role", 40, ".pdf")],
    180: [("Zendesk export folder", "inputs/zendesk-export", 8, ".csv")],
    182: [("#product-launch Slack export", "inputs/product-launch-slack", 8, ".txt")],
    186: [("45 W-9 PDFs", "inputs/w9-pdfs", 45, ".pdf")],
    188: [("/Deals/reviews", "inputs/Deals/reviews", 10, ".md")],
    193: [("invoice PDFs", "inputs/invoice-pdfs", 8, ".pdf")],
    197: [("12 monthly utility statements", "inputs/utility-statements", 12, ".pdf")],
    207: [("this week's call notes", "inputs/call-notes", 8, ".md")],
}

IMPLICIT_SOURCES = {
    9: [("office lease PDF", "inputs/office-lease.pdf")],
    46: [("maintenance-window notice", "inputs/maintenance-window-notice.md")],
    47: [("signed Acme SOW", "inputs/signed-acme-sow.pdf")],
    51: [
        ("executed MSA", "inputs/executed-msa.docx"),
        ("vendor Amendment 2", "inputs/vendor-amendment-2.docx"),
    ],
    85: [
        ("team charter", "inputs/team-charter.md"),
        ("tool list", "inputs/tool-list.csv"),
        ("last hire's ramp doc", "inputs/last-hire-ramp.docx"),
    ],
    89: [("receiving log", "inputs/receiving-log.csv")],
    91: [
        ("event registration list", "inputs/event-registration.csv"),
        ("badge-scan CSV", "inputs/badge-scans.csv"),
        ("CRM export", "inputs/event-crm-export.csv"),
    ],
    92: [
        ("LinkedIn ads CSV", "inputs/linkedin-ads.csv"),
        ("email export", "inputs/email-campaign.csv"),
        ("web analytics export", "inputs/web-analytics.csv"),
    ],
    117: [("named competitor list", "inputs/named-competitors.md")],
    125: [("current travel policy", "inputs/current-travel-policy.md")],
}


class EvalError(RuntimeError):
    pass


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--model", default=EXACT_MODEL)
    parser.add_argument("--case", action="append", dest="case_ids", default=[])
    parser.add_argument("--artifact-dir", type=Path)
    parser.add_argument("--key-file", type=Path)
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument(
        "--workers", type=int, default=1,
        help="Native AppKit runs are intentionally serialized; only 1 is supported",
    )
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--keep-homes", action="store_true")
    return parser.parse_args()


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvalError(f"Cannot read JSON {path}: {error}") from error


def validate_catalog(payload):
    rows = payload.get("rows")
    if not isinstance(rows, list):
        raise EvalError("Cowork catalog must contain a rows list")
    selected = [row for row in rows if row.get("id") in EXPECTED_IDS]
    ids = {row.get("id") for row in selected}
    if ids != EXPECTED_IDS or len(selected) != len(EXPECTED_IDS):
        raise EvalError("Prior-wave catalog must contain IDs 1 through 210 exactly once")
    supported = {"Files/Shell", "Multi-file", "Web research", "Confidential", "Scheduling", "Browser pane"}
    for row in selected:
        if not isinstance(row.get("task"), str) or not row["task"].strip():
            raise EvalError(f"Task {row.get('id')} has no prompt")
        if row.get("capabilityNeeded") not in supported:
            raise EvalError(f"Task {row.get('id')} has unsupported capability")
    return sorted(selected, key=lambda row: row["id"])


def select_cases(rows, requested):
    if not requested:
        return rows
    try:
        ids = {int(value) for value in requested}
    except ValueError as error:
        raise EvalError("--case values must be numeric task IDs") from error
    unknown = ids - EXPECTED_IDS
    if unknown:
        raise EvalError(f"Unknown prior-wave task IDs: {sorted(unknown)}")
    return [row for row in rows if row["id"] in ids]


def load_api_key(explicit_path):
    value = os.environ.get("QUILLCODE_API_KEY") or os.environ.get("TRUSTEDROUTER_API_KEY")
    if value and value.strip():
        return value.strip()
    paths = (explicit_path,) if explicit_path else KEY_FILES
    for path in paths:
        if path and path.is_file():
            value = path.read_text(encoding="utf-8").strip()
            if value:
                return value
    raise EvalError("No TrustedRouter key found in the supported environment variables or key files")


def artifact_root(raw):
    if raw:
        path = raw if raw.is_absolute() else ROOT / raw
    else:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        path = ROOT / ".build" / "quillcode-validation" / "prior-waves-cowork" / stamp
    if path.exists() and (not path.is_dir() or any(path.iterdir())):
        raise EvalError(f"Artifact directory must be absent or empty: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def normalized_words(text):
    return re.findall(r"[a-z0-9]+", text.casefold())


def task_terms(row):
    stop = {
        "about", "after", "against", "also", "and", "before", "build", "check", "draft",
        "each", "every", "file", "find", "from", "give", "into", "last", "list", "make",
        "one", "open", "our", "pull", "read", "report", "the", "their", "them", "these",
        "this", "three", "through", "turn", "using", "with", "write", "you",
    }
    words = []
    for word in normalized_words(row["task"]):
        if len(word) >= 5 and word not in stop and word not in words:
            words.append(word)
    return words[:8]


def task_term_variants(term):
    variants = {term}
    if len(term) >= 6 and term.endswith("s"):
        variants.add(term[:-1])
    if len(term) >= 7 and term.endswith("al"):
        variants.add(term[:-2])
    return variants


def matched_task_terms(row, text):
    words = set(normalized_words(text))
    return [
        term for term in task_terms(row)
        if task_term_variants(term) & words
    ]


def minimum_source_citation_count(row):
    # These tasks use one authoritative external dataset; their other authorities
    # are supplied workspace sources. One primary-source URL is therefore sufficient.
    if row["id"] in {125, 126}:
        return 1
    return 2


def source_grounding_anchors(row, workspace):
    ignored = {
        "and", "atlas", "complete", "confirmed", "context", "evaluation", "file",
        "inputs", "needs", "open", "outputs", "record", "records", "review",
        "source", "task", "the", "workspace",
    }
    anchors = []

    def add(value):
        words = [word for word in normalized_words(str(value)) if word not in ignored]
        if not words or not any(any(character.isalpha() for character in word) for word in words):
            return
        phrase = " ".join(words)
        if (len(words) >= 2 or len(words[0]) >= 5) and phrase not in anchors:
            anchors.append(phrase)

    for description, relative, _, _ in COLLECTION_SPECS.get(row["id"], []):
        add(description)
        source = workspace / relative
        if source.is_dir():
            for member in sorted(path for path in source.rglob("*") if path.is_file())[:40]:
                add(member.relative_to(source).with_suffix("").as_posix())
    for reference in source_references(row["task"]):
        add(reference)
    for description, relative in IMPLICIT_SOURCES.get(row["id"], []):
        add(description)
        add(Path(relative).stem)

    table_references = ["records.csv", *source_references(row["task"])]
    table_references.extend(description for description, _ in IMPLICIT_SOURCES.get(row["id"], []))
    table_references.extend(description for description, _, _, _ in COLLECTION_SPECS.get(row["id"], []))
    for reference in table_references:
        for values in task_table(row, reference, count=12)[1:13]:
            for value in values:
                add(value)

    context_references = source_references(row["task"]) or [row["category"]]
    context_references.extend(description for description, _ in IMPLICIT_SOURCES.get(row["id"], []))
    context_references.extend(description for description, _, _, _ in COLLECTION_SPECS.get(row["id"], []))
    for reference in context_references[:4]:
        for line in task_source_context(row, reference).splitlines():
            words = [word for word in normalized_words(line) if word not in ignored]
            for size in (3, 2):
                for index in range(max(0, len(words) - size + 1)):
                    add(" ".join(words[index:index + size]))
    return anchors[:160]


def matched_source_grounding_anchors(row, workspace, text):
    normalized = f" {' '.join(normalized_words(text))} "
    return [
        anchor for anchor in source_grounding_anchors(row, workspace)
        if f" {anchor} " in normalized
    ]


def evidence_class(row):
    capability = row["capabilityNeeded"]
    if capability == "Browser pane":
        return "native-app-synthetic-authenticated-browser"
    if capability == "Web research":
        return "native-app-live-public-web"
    if capability == "Confidential":
        return "native-app-confidential-workspace"
    if capability == "Scheduling":
        return "native-app-persisted-automation"
    return "native-app-isolated-workspace"


def output_format(row):
    task_id = row["id"]
    for extension, task_ids in (
        ("csv", CSV_TASKS),
        ("xlsx", XLSX_TASKS),
        ("pdf", PDF_TASKS),
        ("png", PNG_TASKS),
        ("html", HTML_TASKS),
        ("docx", DOCX_TASKS),
        ("mmd", MERMAID_TASKS),
    ):
        if task_id in task_ids:
            return extension
    return "md"


def output_path(row):
    return f"outputs/task-{row['id']}-deliverable.{output_format(row)}"


def fixture_context(row):
    terms = ", ".join(task_terms(row)) or row["category"]
    return f"""# Controlled source packet for catalog task {row['id']}

## Scope

This packet represents the local files or service records named in the original task.
The evaluation tenant is Atlas Labs, a 48-person B2B software company. The reporting
period is 2026-Q3 and the evidence was captured on 2026-08-08. Relevant task concepts:
{terms}.

## Verified facts

- Priya Shah owns the operating plan; Rafael Ortiz approves budget changes.
- The current milestone is 2026-09-15. The review checkpoint is 2026-08-22.
- Revenue is $540,000 versus a $500,000 plan; operating spend is $412,000 versus $390,000.
- Northstar is the highest-priority account. Its last verified activity was 2026-07-01.
- The supported recommendation is to validate source data, assign an owner, and review in seven days.
- Records marked `needs-review` have incomplete evidence and must not be presented as confirmed.
- External messages, deletions, renames, CRM updates, and campaign changes are simulated only.

## Source handling

Use `inputs/records.csv` for row-level evidence. Do not invent missing source facts. For
destructive requests, produce an exact proposed action log rather than touching files
outside this workspace. For authenticated browser requests, the open fixture page is
the isolated evaluation tenant and no real account should be modified.
"""


def csv_text(values):
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerows(values)
    return stream.getvalue()


def task_table(row, reference="", item_index=1, count=40):
    """Return deterministic, task-relevant rows for CSV, XLSX, and browser fixtures."""
    key = f"{row['category']} {row['task']} {reference}".casefold()
    owners = ("Priya Shah", "Rafael Ortiz", "Jo Chen", "Avery Lin")

    if row["id"] == 19:
        month_weights = (0.07, 0.07, 0.08, 0.08, 0.08, 0.08, 0.085, 0.085, 0.09, 0.09, 0.09, 0.10)
        channels = (
            ("Paid Search", 30000, "Capture active demand"),
            ("Paid Social", 24000, "Reach target-account buying committees"),
            ("Content and SEO", 18000, "Build durable organic demand"),
            ("Events and Webinars", 18000, "Support pipeline and Northstar account engagement"),
            ("Lifecycle Email", 15000, "Activate and retain existing leads"),
            ("Partner and ABM", 15000, "Develop partner and named-account pipeline"),
        )
        headers = (
            "channel", "annual_budget_usd",
            "jan_pct", "feb_pct", "mar_pct", "apr_pct", "may_pct", "jun_pct",
            "jul_pct", "aug_pct", "sep_pct", "oct_pct", "nov_pct", "dec_pct",
            "owner", "approval_status", "planning_basis",
        )
        return [
            headers,
            *(
                (channel, budget, *month_weights, "Jo Chen", "approved by Rafael Ortiz", basis)
                for channel, budget, basis in channels
            ),
        ]

    if row["id"] == 33:
        return [
            (
                "contact_id", "first_name", "email", "job_title", "company",
                "booth-notes", "event_name",
            ),
            (
                "C-001", "Alice", "alice@northstar.example", "VP Sales",
                "Northstar Systems",
                "Asked for a pricing recap for 75 sales seats and SSO",
                "SaaS Founders Summit",
            ),
            (
                "C-002", "Bruno", "bruno@juniper.example", "Director of Customer Success",
                "Juniper Health",
                "Wants a 30-minute workflow demo with two CSM leads next Tuesday",
                "SaaS Founders Summit",
            ),
            (
                "C-003", "Chen", "chen@cobalt.example", "CFO", "Cobalt Works",
                "Needs the SOC 2 report and annual billing estimate before finance review",
                "SaaS Founders Summit",
            ),
            (
                "C-004", "Dana", "dana@cedar.example", "Engineering Manager",
                "Cedar Robotics",
                "Interested in API rate limits and sandbox access for a migration prototype",
                "SaaS Founders Summit",
            ),
            (
                "C-005", "Elena", "elena@harbor.example", "COO", "Harbor Logistics",
                "Discussed replacing weekly spreadsheet handoffs across three regional teams",
                "SaaS Founders Summit",
            ),
            (
                "C-006", "Fatima", "fatima@lumen.example", "Head of Operations",
                "Lumen Labs",
                "Asked for a health-tech customer reference and implementation timeline",
                "SaaS Founders Summit",
            ),
        ]

    if row["id"] == 121:
        return [
            ("region", "currency", "month", "local_revenue"),
            ("DACH", "EUR", "2026-05", 128500),
            ("UK and Ireland", "GBP", "2026-05", 112750),
            ("Japan", "JPY", "2026-05", 18400000),
            ("DACH", "EUR", "2026-06", 134200),
            ("UK and Ireland", "GBP", "2026-06", 118900),
            ("Japan", "JPY", "2026-06", 19150000),
            ("DACH", "EUR", "2026-07", 139750),
            ("UK and Ireland", "GBP", "2026-07", 121400),
            ("Japan", "JPY", "2026-07", 20300000),
        ]

    if row["id"] == 125:
        return [
            (
                "claim_id", "employee", "trip_date", "business_miles",
                "meal_cost_usd", "receipt_attached",
                "current_mileage_reimbursement_usd", "current_meal_reimbursement_usd",
                "expected_updated_mileage_reimbursement_usd",
                "expected_updated_meal_reimbursement_usd", "review_note",
            ),
            (
                "TRV-125-001", "Priya Shah", "2026-01-08", 126, "64.20", "yes",
                "88.20", "64.20", "91.35", "64.20", "apply 2026 mileage rate",
            ),
            (
                "TRV-125-002", "Rafael Ortiz", "2026-01-19", 84, "82.40", "yes",
                "58.80", "65.00", "60.90", "75.00", "apply both new limits",
            ),
            (
                "TRV-125-003", "Jo Chen", "2025-12-18", 100, "71.10", "yes",
                "70.00", "65.00", "70.00", "65.00", "pre-effective-date claim",
            ),
            (
                "TRV-125-004", "Avery Lin", "2026-02-03", 0, "74.00", "yes",
                "0.00", "65.00", "0.00", "74.00", "meal cap only",
            ),
            (
                "TRV-125-005", "Priya Shah", "2026-03-11", 248, "97.00", "yes",
                "173.60", "65.00", "179.80", "75.00", "apply both new limits",
            ),
        ]

    if row["id"] == 126:
        return [
            ("fiscal_year", "nominal_revenue_usd", "reporting_basis", "status"),
            (2023, 4200000, "calendar-year recognized revenue", "audited"),
            (2024, 5100000, "calendar-year recognized revenue", "audited"),
            (2025, 6000000, "calendar-year recognized revenue", "audited"),
        ]

    if "kpi-dashboard" in reference.casefold():
        return [
            ("Metric", "Q2", "Q3", "Owner"),
            ("Revenue", 500000, 540000, "Priya Shah"),
            ("Operating spend", 390000, 412000, "Rafael Ortiz"),
            ("Activation percent", 42, 49, "Priya Shah"),
            ("Northstar open days", 21, 38, "Jo Chen"),
        ]

    if any(term in key for term in ("event registration", "badge-scan", "badge scan", "event-crm")):
        rows = []
        for index in range(1, 21):
            scanned = index % 4 != 0
            if "registration" in reference.casefold():
                scanned = False
            rows.append((
                f"E-{index:03d}", f"attendee{index:02d}@example.com", f"Attendee {index:02d}",
                ("Northstar Systems", "Juniper Health", "Cobalt Works")[index % 3],
                "registered", "2026-08-05 09:00" if scanned else "", "qualified" if index % 3 == 0 else "nurture",
            ))
        return [("registration_id", "email", "name", "company", "registration_status", "badge_scan_time", "crm_status"), *rows]

    if "contact" in key or "lead" in key or "shortlist" in key:
        names = (
            "ALICE JOHNSON", "Bruno Garcia", "CHEN WEI", "Dana Okafor",
            "Elena Rossi", "Fatima Khan", "Gabriel Martin", "HANA SATO",
        )
        jobs = ("VP SALES", "customer success mgr", "CFO", "Sr. engineer")
        rows = []
        for index in range(1, 13):
            duplicate = index in {5, 10}
            base = index - 1 if duplicate else index
            rows.append((
                f"C-{index:03d}", names[(index - 1) % len(names)],
                f"person{base:02d}@example.com", "" if index in {3, 8} else f"+1415555{1000 + index}",
                "yes" if index in {6, 11} else "no", jobs[(index - 1) % len(jobs)],
                ("Northstar Systems", "Juniper Health", "Cobalt Works")[index % 3],
                f"2026-07-{(index % 28) + 1:02d}", "Send pricing recap" if index % 2 else "Book discovery call",
            ))
        return [
            ("contact_id", "name", "email", "phone", "opt_out", "job_title", "company", "last_activity", "next_step"),
            *rows,
        ]

    if "signup" in key:
        rows = []
        for month, month_factor in (("2026-05", 100), ("2026-06", 82)):
            for source_index, source in enumerate(("Organic", "Paid Search", "Partner"), start=1):
                for region_index, region in enumerate(("West", "Central", "East"), start=1):
                    count_value = month_factor + source_index * 9 + region_index * 4
                    if month == "2026-06" and source == "Paid Search" and region == "West":
                        count_value -= 46
                    rows.append((
                        f"{month}-{source_index}-{region_index}", f"{month}-15", source,
                        "Core Demo" if source != "Partner" else "Channel Launch", region, count_value,
                    ))
        return [("signup_id", "date", "source", "campaign", "region", "signups"), *rows]

    if "subscription" in key or "cohort" in key:
        rows = []
        for cohort_index, cohort in enumerate(("2026-01", "2026-02", "2026-03", "2026-04"), start=1):
            for month in range(6):
                retained = max(28, 100 - month * (7 + cohort_index * 2))
                rows.append((cohort, month, 100, retained, round(retained / 100, 2), ("Starter", "Growth")[cohort_index % 2]))
        return [("cohort_month", "months_since_signup", "signup_count", "paid_count", "retention_rate", "plan_tier"), *rows]

    if any(term in key for term in ("campaign", "linkedin ads", "google ads", "web analytics", "marketing kpi", "traffic by channel")):
        rows = []
        for week in range(1, 13):
            for channel_index, channel in enumerate(("Paid Search", "LinkedIn", "Email", "Organic"), start=1):
                spend = 1800 + week * 120 + channel_index * 250
                clicks = 320 + week * 17 + channel_index * 31
                leads = 22 + week + channel_index * 3
                rows.append((
                    f"2026-W{week + 18:02d}", channel, "Northstar Q3", spend, 18000 + week * 850,
                    clicks, leads, 5 + (week + channel_index) % 9, 8000 + week * 650 + channel_index * 900,
                ))
        return [("week", "channel", "campaign", "spend", "impressions", "clicks", "leads", "customers", "revenue"), *rows]

    if "donor" in key:
        return [
            ("donor_id", "Name", "Address", "gift_amount"),
            ("D-001", "Ada Lovelace", "12 Oak St, Cleveland, OH 44114", 500),
            ("D-002", "Grace Hopper", "9 Pine Avenue, Columbus, OH 43215", 750),
            ("D-003", "Prince", "Unparseable address", 250),
            ("D-004", "Katherine Johnson", "88 Lake Rd, Dayton, OH 45402", 1000),
        ]

    if "newsletter" in key or "member" in key:
        return [
            ("member_id", "name", "email", "phone", "Date Joined", "status"),
            ("M-001", "Ari Cole", "ari@example.com", "(415) 555-0101", "07/14/2026", "active"),
            ("M-002", "Bea Diaz", "bea.example.com", "415.555.0102", "14/07/2026", "active"),
            ("M-003", "Cal Wu", "cal@example.com", "+44 20 7946 0958", "July 15, 2026", "active"),
            ("M-004", "Dev Rao", "dev@example", "", "2026-07-16", "needs-review"),
        ]

    if any(term in key for term in ("dependency", "milestone", "timeline", "phase-plan", "plan-v")):
        version_shift = 14 if any(term in reference.casefold() for term in ("v5", "revised")) else 0
        rows = []
        for index, phase in enumerate(("Discovery", "Design", "Build", "Pilot", "Launch"), start=1):
            day = min(28, 3 + index * 4 + version_shift)
            rows.append((
                f"MS-{index:02d}", phase, owners[index % 4],
                f"2026-{9 if day < 25 else 10:02d}-{day if day < 25 else day - 20:02d}",
                "On track" if version_shift == 0 else "Slipped",
                "Vendor dependency" if version_shift and index in {3, 4} else "Approved sequence",
                "" if index == 2 else f"MS-{index - 1:02d}" if index > 1 else "",
            ))
        return [("milestone_id", "milestone", "owner", "due_date", "status", "reason", "depends_on"), *rows]

    if any(term in key for term in ("utility", "kwh", "electric")):
        rows = []
        for month in range(1, 13):
            for site_index, site in enumerate(("HQ", "Warehouse", "Support Center"), start=1):
                kwh = 8200 + month * 190 + site_index * 740
                rows.append((f"2025-{month:02d}", site, kwh, round(kwh * (0.14 + site_index * 0.01), 2)))
        return [("month", "site", "kwh", "cost"), *rows]

    if any(term in key for term in ("freight", "lane", "carrier", "contracted rates")):
        rows = []
        for index in range(1, min(count, 60) + 1):
            contracted = round(1.35 + (index % 5) * 0.17, 2)
            billed = contracted + (0.22 if index % 6 == 0 else 0)
            rows.append((
                f"F-{index:03d}", ("Meridian", "Northwind", "Atlas Freight")[index % 3],
                ("SFO-LAX", "AUS-DFW", "ORD-JFK")[index % 3], 300 + index * 18,
                contracted, billed, round((billed - contracted) * (300 + index * 18), 2),
            ))
        return [("shipment_id", "carrier", "lane", "miles", "contract_rate_per_mile", "billed_rate_per_mile", "overcharge"), *rows]

    if any(term in key for term in ("invoice", "payment", "bank statement", "chase statement", "amex", "payout", "receipt", "expense")):
        rows = []
        for index in range(1, min(count, 60) + 1):
            invoice_id = f"INV-{1000 + index}"
            amount = round(425 + index * 137.25, 2)
            paid = index % 5 not in {0, 1}
            if "payment" in reference.casefold() or "bank" in reference.casefold():
                status = "paid" if paid else "unmatched"
            else:
                status = "open" if not paid else "paid"
            rows.append((
                invoice_id, f"2026-{((item_index - 1) % 12) + 1:02d}-{(index % 27) + 1:02d}",
                ("Acme Cloud", "Northwind Freight", "Cobalt Office", "Juniper Telecom")[index % 4],
                f"Service charge, period {index}", amount, amount if index % 7 else amount + 125,
                status, f"2026-{((item_index + 1) % 12) + 1:02d}-{(index % 27) + 1:02d}",
                f"PO-{500 + index}", ("Software", "Freight", "Office", "Telecom")[index % 4],
            ))
        return [("invoice_id", "date", "vendor", "description", "amount", "matched_amount", "status", "due_date", "po_number", "category"), *rows]

    if any(term in key for term in ("budget", "actual", "cost center", "variance")):
        actual = "actual" in reference.casefold()
        rows = []
        for index, center in enumerate(("Sales", "Marketing", "Product", "Support", "G&A"), start=1):
            planned = 28000 + index * 6500
            amount = round(planned * (1 + (0.16 if index in {2, 4} else 0.04))) if actual else planned
            rows.append((f"CC-{index:02d}", center, "2026-06", amount, owners[index % 4], "Campaign overage" if actual and index == 2 else "Within plan"))
        return [("cost_center_id", "cost_center", "month", "amount", "owner", "explanation"), *rows]

    if any(term in key for term in ("sales", "revenue", "pipeline", "deal", "crm", "renewal", "account")):
        rows = []
        stages = ("Prospecting", "Discovery", "Evaluation", "Proposal", "Negotiation", "Closed Won")
        for index in range(1, min(count, 45) + 1):
            rows.append((
                f"D-{index:03d}", f"Account {index:02d}", f"Buyer {index:02d}", owners[index % 4],
                stages[index % len(stages)], ("West", "Central", "East")[index % 3],
                ("Q1", "Q2", "Q3", "Q4")[(index - 1) % 4], 12000 + index * 3100,
                f"2026-0{(index % 7) + 1}-{(index % 27) + 1:02d}",
                f"2026-{((index + 1) % 12) + 1:02d}-{(index % 27) + 1:02d}",
                "Review security terms" if index % 3 else "Schedule executive call",
                ("LinkedIn", "Email", "Partner")[index % 3],
            ))
        return [("deal_id", "account", "contact", "owner", "stage", "region", "quarter", "revenue", "last_activity", "close_date", "next_step", "source"), *rows]

    if any(term in key for term in ("ticket", "zendesk", "survey", "nps", "support", "refund")):
        rows = []
        themes = ("Billing", "Login", "Export", "Performance", "Permissions", "Refund")
        for index in range(1, min(count, 40) + 1):
            score = (2, 4, 6, 7, 8, 9, 10)[index % 7]
            rows.append((
                f"T-{index:03d}", themes[index % len(themes)], ("Starter", "Growth", "Enterprise")[index % 3],
                score, 25 + index * 6, f"Customer reports {themes[index % len(themes)].casefold()} friction",
                owners[index % 4], f"2026-07-{(index % 28) + 1:02d}", "open" if index % 4 else "resolved",
            ))
        return [("ticket_id", "theme", "plan_tier", "nps_score", "first_response_minutes", "comment", "owner", "created_date", "status"), *rows]

    if any(term in key for term in ("inventory", "warehouse", "sku", "allocation", "capacity")):
        rows = []
        system_offset = 0 if "system" in reference.casefold() else item_index * 3
        for index in range(1, 13):
            rows.append((
                f"SKU-{index:03d}", 100 + index * 9 + system_offset,
                7 + (index % 21), ("Warehouse West", "Warehouse Central", "Warehouse East")[item_index % 3],
                owners[index % 4], round(0.55 + (index % 6) * 0.12, 2),
            ))
        return [("sku", "units", "days_of_cover", "location", "owner", "allocation"), *rows]

    if any(term in key for term in ("comp_band", "comp-band", "comp bands", "headcount", "roster", "pay equity", "employee")):
        rows = []
        for index in range(1, min(count, 48) + 1):
            level = ("L2", "L3", "L4", "L5")[index % 4]
            band_min = 80000 + (index % 4) * 20000
            salary = band_min - 4500 if index % 11 == 0 else band_min + 3000 + index * 250
            rows.append((
                f"EMP-{index:03d}", ("Engineering", "Sales", "Marketing", "Support")[index % 4],
                level, ("Woman", "Man", "Nonbinary")[index % 3], 1 + index % 9,
                salary, band_min, band_min + 30000, "active" if index % 9 else "exited",
                "REQ-OPEN" if index % 13 == 0 else "",
            ))
        return [("employee_id", "department", "level", "gender", "tenure_years", "salary", "band_min", "band_max", "status", "open_req"), *rows]

    if any(term in key for term in ("asana", "project tracker", "launch tracker", "task due", "portfolio")):
        rows = []
        for index in range(1, 25):
            rows.append((
                f"TASK-{index:03d}", f"Launch work item {index:02d}", owners[index % 4],
                f"2026-08-{(index % 20) + 9:02d}", "complete" if index <= 9 else "open",
                ("Northstar Launch", "Billing Upgrade", "CRM Recovery")[index % 3],
                "2026-08-18" if index % 5 == 0 else "",
            ))
        return [("task_id", "task", "owner", "due_date", "status", "project", "revised_due_date"), *rows]

    if "vendor" in key or "rate" in key or "proposal" in key:
        rows = []
        for index in range(1, min(count, 30) + 1):
            alias = ("Acme Inc", "ACME, Inc.", "Acme Incorporated")[index % 3] if index <= 3 else f"Vendor {index:02d}"
            rows.append((f"V-{index:03d}", alias, 24000 + index * 1700, "99.9%", 30 + index, f"2027-{(index % 12) + 1:02d}-15", owners[index % 4]))
        return [("vendor_id", "vendor", "annual_cost", "sla", "implementation_days", "renewal_date", "owner"), *rows]

    rows = []
    statuses = ("confirmed", "open", "needs-review", "complete")
    for index in range(1, count + 1):
        rows.append((
            f"R-{index:03d}", f"Atlas record {index:02d}", owners[index % 4],
            statuses[index % 4], 1200 + index * 175, f"2026-07-{(index % 28) + 1:02d}",
            f"source-{index:02d}", "high" if index % 3 else "medium",
            "review evidence" if index % 4 == 2 else "confirm owner",
        ))
    return [("record_id", "name", "owner", "status", "amount", "event_date", "source", "confidence", "next_step"), *rows]


def task_source_context(row, reference, item_index=1, count=1):
    if row["id"] == 42:
        return """# Atlas Labs Equipment Safety Guide
Document ID: SAFE-OPS-042. Revision: 2026-07-15. Owner: Jo Chen.
## Before You Begin
WARNING BOX: Only trained staff may operate the packaging line.
Wear safety glasses, cut-resistant gloves, and closed-toe shoes.
## Numbered Shutdown Procedure
1. Press the red STOP button and wait for all conveyor motion to cease.
WARNING BOX 1: Do not reach across a moving conveyor.
2. Turn the main disconnect clockwise to OFF and attach lockout tag SAFE-17.
WARNING BOX 2: The disconnect remains energized until the indicator is dark.
3. Verify the amber power indicator is dark, then test the START control once.
WARNING BOX 3: If the conveyor moves, step away and call Facilities at extension 7712.
4. Clear loose material with the blue-handled brush; never use hands or compressed air.
WARNING BOX 4: Report damaged guards to Jo Chen before restarting equipment.
5. Remove the lockout tag only after the guard is secured and the work area is clear.
## Emergency Response
Call Security at extension 7000 for an injury, fire, or chemical release.
Record the incident in Atlas Safety Log within 30 minutes when conditions are safe.
## Restart Authorization
Jo Chen or the shift supervisor must sign the restart checklist.
"""

    if row["id"] == 117 and reference == "named competitor list":
        return """# Named competitors for the quarterly revenue comparison

Evidence date: 2026-08-08

Use these exact public-company competitors. Do not substitute products, private
companies, or similarly named businesses.

- Asana, Inc. (NYSE: ASAN)
- monday.com Ltd. (NASDAQ: MNDY)
- GitLab Inc. (NASDAQ: GTLB)

Comparison basis: total company revenue in each company's four most recently
reported fiscal quarters as of the evidence date. Preserve each fiscal-quarter label
and period end date. Use official investor-relations releases or SEC filings as the
primary sources. Atlas Labs values must be calculated from `inputs/records.csv`.
"""

    if row["id"] == 125 and reference == "current travel policy":
        return """# Atlas Labs Travel and Expense Policy

Policy version: 3.2
Effective date: 2025-01-01
Policy owner: Priya Shah, Head of People Operations
Approver: Rafael Ortiz, Chief Financial Officer

## Scope and authorization
This policy applies to employees traveling for approved Atlas Labs business. The
employee's manager must authorize overnight travel before booking. Travelers must use
the lowest reasonable fare and may not approve their own expense reports.

## Personal vehicle mileage
Approved business use of a personal vehicle for travel on or after 2025-01-01 is
reimbursed at $0.70 per business mile. Commuting between home and the employee's
regular work location is not reimbursable. Parking and tolls may be claimed separately
with itemized receipts.

## Meals
Reasonable actual meal costs while traveling overnight are reimbursable up to $65 per
traveler per calendar day. Alcohol and entertainment are not reimbursable. The cap is
not a per diem and unused amounts cannot be carried to another day.

## Lodging, receipts, and submission
Use preferred hotels when available. Itemized receipts are required for lodging and
for every other individual expense of $50 or more. Expense reports are due within 10
calendar days after travel ends and must state the business purpose, destination, and
dates. Finance may return incomplete or unsupported claims for correction.

## Exceptions
Rafael Ortiz must approve policy exceptions in writing before reimbursement. Preserve
all provisions other than the mileage rate, meal cap, policy version, and effective
date when issuing the requested update.
"""

    key = f"{row['category']} {row['task']} {reference}".casefold()
    base = fixture_context(row)
    details = [
        f"Source: {reference or 'task source'}",
        f"Record ID: TASK-{row['id']}-{item_index:03d}",
        f"Collection position: {item_index} of {count}",
    ]
    if row["id"] == 17:
        modified = task_17_modified_date(item_index)
        quarter = f"{modified.year}-Q{((modified.month - 1) // 3) + 1}"
        disposition = "archive" if modified < datetime(2025, 1, 1, tzinfo=timezone.utc) else "keep"
        details.extend([
            f"Modified date: {modified.date().isoformat()} UTC.",
            f"Quarter: {quarter}. Required disposition: {disposition}.",
            "The content metadata and filesystem modification time are intentionally identical.",
        ])
    elif any(term in key for term in ("incident", "outage", "maintenance")):
        details.extend([
            "Incident began 2026-07-14 09:12 PT and service recovered at 11:47 PT.",
            "API requests failed for 38 percent of active workspaces; no stored customer data was lost.",
            "A deployment exposed an unbounded database connection retry; blame is not assigned.",
            "Changes: capped retries, added saturation alerts, and required canary verification.",
            "Affected customers receive a 10 percent July service credit.",
        ])
    elif any(term in key for term in ("lease", "msa", "contract", "sow", "dpa", "nda", "agreement", "term sheet")):
        details.extend([
            "Counterparty: Northwind Logistics LLC. Effective date: 2026-01-01.",
            "Initial term ends 2027-12-31 and renews for one year unless notice is given 60 days before end.",
            "Termination for uncured material breach is allowed after 30 days; convenience termination is not allowed.",
            "Liability cap is fees paid in the prior 12 months, except confidentiality and IP indemnity.",
            "Security incidents require notice within 48 hours; customer data must be returned or deleted in 30 days.",
            "Year 1 rent is $18,500 monthly, escalating 3 percent annually; CAM is $4,200 monthly.",
        ])
    elif any(term in key for term in ("bank", "statement", "invoice", "receipt", "expense", "payout")):
        details.extend([
            f"Invoice ID: INV-{1000 + item_index}. Vendor: Northwind Freight.",
            f"Transaction date: 2026-{((item_index - 1) % 12) + 1:02d}-15.",
            f"Amount: ${425 + item_index * 137.25:,.2f}. Running balance: ${50000 - item_index * 911:,.2f}.",
            f"PO number: PO-{500 + item_index}. Category: Freight.",
        ])
    elif any(term in key for term in ("medical", "health plan", "benefit", "insurance")):
        plan = ("Bronze", "Silver", "Gold")[(item_index - 1) % 3]
        details.extend([
            f"Plan: {plan}. Monthly employee premium: ${310 + item_index * 95}.",
            f"Deductible: ${3500 - item_index * 650}. Out-of-pocket maximum: ${7600 - item_index * 500}.",
            f"Specialist copay: ${70 - item_index * 10}. Network providers: {12000 + item_index * 4500}.",
            "RX tiers: $15 generic, $45 preferred brand, $90 non-preferred, 30 percent specialty.",
        ])
    elif any(term in key for term in ("resume", "candidate", "interview", "hiring")):
        details.extend([
            f"Candidate: Morgan Candidate {item_index}. Current title: Senior Product Manager.",
            f"Experience: {4 + item_index % 9} years; B2B product experience: {2 + item_index % 6} years.",
            f"Location: {('San Francisco', 'New York', 'Austin', 'Remote US')[item_index % 4]}.",
            "Strengths: discovery research, analytics, cross-functional delivery. Gap: limited international launch work.",
        ])
    elif any(term in key for term in ("meeting", "notes", "minutes", "retro", "transcript", "status")):
        details.extend([
            f"Decision: approve pilot scope {item_index}; owner: Priya Shah; date: 2026-07-{(item_index % 28) + 1:02d}.",
            f"Action: validate migration data; owner: Rafael Ortiz; due: 2026-08-{(item_index % 20) + 1:02d}.",
            "Risk: vendor API readiness is amber. Ask: approve a two-week contingency.",
            "Recurring theme: acceptance criteria arrive late; the checklist change from sprint 19 stuck.",
        ])
    elif any(term in key for term in ("paper", "research", "analyst", "assessment", "report")):
        details.extend([
            f"Study sample: {180 + item_index * 37} B2B software users across 12 organizations.",
            "Method: preregistered longitudinal cohort with matched controls.",
            f"Effect size: {0.12 + item_index * 0.03:.2f}; confidence interval excludes zero for the primary outcome.",
            "Stated limitation: self-selection and a six-month follow-up constrain generalization.",
            f"Headline revenue: ${410000 + item_index * 27000}; growth: {8 + item_index} percent; churn: {5.4 - item_index * 0.1:.1f} percent.",
        ])
    elif any(term in key for term in ("w-9", "w9", "coi", "certificate")):
        details.extend([
            f"Legal name: Vendor Entity {item_index} LLC. TIN type: EIN. Address: {100 + item_index} Market St, Columbus, OH 43215.",
            f"Policy number: GL-{2026000 + item_index}. Carrier: Meridian Casualty. Limit: ${750000 if item_index % 7 == 0 else 2000000}.",
            f"Expiry: 2026-{8 + item_index % 4:02d}-{(item_index % 27) + 1:02d}. Signature date: {'missing' if item_index % 11 == 0 else '2026-01-10'}.",
        ])
    else:
        details.extend([
            f"Owner: {('Priya Shah', 'Rafael Ortiz', 'Jo Chen', 'Avery Lin')[item_index % 4]}.",
            f"Amount: ${1200 + item_index * 175}. Event date: 2026-07-{(item_index % 28) + 1:02d}.",
            f"Status: {('confirmed', 'open', 'needs-review', 'complete')[item_index % 4]}.",
            "Verified next step: validate the evidence and review with the named owner in seven days.",
        ])
    return base + "\n\n## Task-specific source evidence\n\n" + "\n".join(f"- {detail}" for detail in details) + "\n"


def source_references(task):
    matches = re.findall(
        r"(?<![A-Za-z0-9])(?:~\/|\/)?[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*"
        r"\.(?:csv|xlsx|xls|md|txt|docx|pptx|pdf|eml|html|png)",
        task,
        flags=re.IGNORECASE,
    )
    references = []
    for match in matches:
        clean = match.rstrip(".,:;").replace("~/", "").lstrip("/")
        if clean and clean not in references:
            references.append(clean)
    return references


def required_source_paths(row):
    paths = [
        "inputs/source-map.md",
        "inputs/evaluation-context.md",
    ]
    task_sources = [
        *(mapped_source_path(reference) for reference in source_references(row["task"])),
        *(spec[1] for spec in COLLECTION_SPECS.get(row["id"], [])),
        *(relative for _, relative in IMPLICIT_SOURCES.get(row["id"], [])),
    ]
    paths.extend(task_sources or ["inputs/records.csv"])
    if row["id"] == 125:
        paths.append("inputs/records.csv")
    task = row["task"].casefold()
    if "last quarter" in task and "memo" in task:
        paths.append("inputs/last-quarter-board-memo.md")
    if row["id"] == 5:
        paths.append("inputs/agenda.txt")
    return paths


def mapped_source_path(reference):
    clean = reference.replace("\\", "/").lstrip("./")
    return clean if clean.startswith("inputs/") else f"inputs/{clean}"


def xml_escape(text):
    return html.escape(str(text), quote=False)


def write_docx(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    paragraphs = "".join(
        f"<w:p><w:r><w:t>{xml_escape(line)}</w:t></w:r></w:p>"
        for line in text.splitlines() if line.strip()
    )
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "[Content_Types].xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/word/document.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
            '</Types>',
        )
        archive.writestr(
            "_rels/.rels",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            'Target="word/document.xml"/>'
            '</Relationships>',
        )
        archive.writestr(
            "word/document.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            f"<w:body>{paragraphs}</w:body></w:document>",
        )


def write_pptx(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "[Content_Types].xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/ppt/presentation.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
            '<Override PartName="/ppt/slides/slide1.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
            '</Types>',
        )
        archive.writestr(
            "_rels/.rels",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            'Target="ppt/presentation.xml"/>'
            '</Relationships>',
        )
        archive.writestr(
            "ppt/presentation.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
            'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
            '<p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>'
            '<p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/>'
            '</p:presentation>',
        )
        archive.writestr(
            "ppt/_rels/presentation.xml.rels",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
            'Target="slides/slide1.xml"/>'
            '</Relationships>',
        )
        archive.writestr(
            "ppt/slides/slide1.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
            'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/>'
            '<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
            '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Source packet"/>'
            '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/>'
            '<a:lstStyle/><a:p><a:r><a:rPr lang="en-US"/>'
            f'<a:t>{xml_escape(text)}</a:t></a:r><a:endParaRPr lang="en-US"/>'
            '</a:p></p:txBody></p:sp></p:spTree></p:cSld>'
            '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>',
        )


def write_xlsx(path, values=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if values is None:
        values = (
            ("Metric", "Q2", "Q3", "Owner"),
            ("Revenue", "500000", "540000", "Priya Shah"),
            ("Operating spend", "390000", "412000", "Rafael Ortiz"),
            ("Activation percent", "42", "49", "Priya Shah"),
            ("Northstar open days", "21", "38", "Jo Chen"),
        )
    rows = []
    for row_index, values_row in enumerate(values, start=1):
        cells = []
        for column_index, value in enumerate(values_row):
            column = chr(ord("A") + column_index)
            cells.append(
                f'<c r="{column}{row_index}" t="inlineStr"><is><t>{xml_escape(value)}</t></is></c>'
            )
        rows.append(f'<row r="{row_index}">{"".join(cells)}</row>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "[Content_Types].xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '</Types>',
        )
        archive.writestr(
            "_rels/.rels",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            'Target="xl/workbook.xml"/>'
            '</Relationships>',
        )
        archive.writestr(
            "xl/workbook.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="KPI Dashboard" sheetId="1" r:id="rId1"/></sheets>'
            '</workbook>',
        )
        archive.writestr(
            "xl/_rels/workbook.xml.rels",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            'Target="worksheets/sheet1.xml"/>'
            '</Relationships>',
        )
        archive.writestr(
            "xl/worksheets/sheet1.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            f'<sheetData>{"".join(rows)}</sheetData></worksheet>',
        )


def pdf_escape(text):
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def write_pdf(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [line.strip() for line in text.splitlines() if line.strip()][:30]
    content_lines = ["BT", "/F1 10 Tf", "54 742 Td"]
    for index, line in enumerate(lines):
        if index:
            content_lines.append("0 -18 Td")
        content_lines.append(f"({pdf_escape(line[:100])}) Tj")
    content_lines.append("ET")
    stream = "\n".join(content_lines).encode("latin-1", errors="replace")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream",
    ]
    payload = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for index, obj in enumerate(objects, start=1):
        offsets.append(len(payload))
        payload.extend(f"{index} 0 obj\n".encode() + obj + b"\nendobj\n")
    xref = len(payload)
    payload.extend(f"xref\n0 {len(objects) + 1}\n".encode())
    payload.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        payload.extend(f"{offset:010d} 00000 n \n".encode())
    payload.extend(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    )
    path.write_bytes(payload)


def write_png(path, width=1200, height=675):
    path.parent.mkdir(parents=True, exist_ok=True)
    row = b"\x00" + (b"\x26\x57\x8f" * width)
    raw = row * height

    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, level=1))
        + chunk(b"IEND", b"")
    )


def materialize_source(path, row, reference="", item_index=1, count=1):
    suffix = path.suffix.casefold()
    context = task_source_context(row, reference or path.name, item_index, count)
    values = task_table(row, reference or path.name, item_index, max(count, 12))
    if suffix == ".xlsx":
        write_xlsx(path, values)
    elif suffix == ".docx":
        write_docx(path, context)
    elif suffix == ".pptx":
        write_pptx(path, context)
    elif suffix == ".pdf":
        write_pdf(path, context)
    elif suffix == ".png":
        write_png(path, width=800 + (item_index % 6) * 160, height=600)
    elif suffix == ".csv":
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(csv_text(values), encoding="utf-8")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(context, encoding="utf-8")
    if row["id"] == 17:
        timestamp = task_17_modified_date(item_index).timestamp()
        os.utime(path, (timestamp, timestamp))


def task_17_modified_date(item_index):
    dates = (
        (2023, 2, 14),
        (2023, 5, 3),
        (2023, 11, 8),
        (2024, 1, 22),
        (2024, 4, 11),
        (2024, 10, 30),
        (2025, 2, 12),
        (2026, 7, 9),
    )
    year, month, day = dates[(item_index - 1) % len(dates)]
    return datetime(year, month, day, 12, tzinfo=timezone.utc)


def write_fixture(row, workspace):
    inputs = workspace / "inputs"
    inputs.mkdir(parents=True)
    context = fixture_context(row)
    (inputs / "evaluation-context.md").write_text(context, encoding="utf-8")
    (inputs / "records.csv").write_text(csv_text(task_table(row)), encoding="utf-8")

    mappings = []
    for reference in source_references(row["task"]):
        mapped = mapped_source_path(reference)
        path = workspace / mapped
        materialize_source(path, row, reference)
        mappings.append(f"- `{reference}` -> `{mapped}` (materialized evaluation source)")
    for description, relative in IMPLICIT_SOURCES.get(row["id"], []):
        materialize_source(workspace / relative, row, description)
        mappings.append(f"- `{description}` -> `{relative}` (materialized evaluation source)")
    for description, relative, count, extension in COLLECTION_SPECS.get(row["id"], []):
        directory = workspace / relative
        for index in range(1, count + 1):
            item = directory / f"item-{index:03d}{extension}"
            materialize_source(item, row, description, item_index=index, count=count)
        mappings.append(
            f"- `{description}` -> `{relative}` ({count} materialized `{extension}` sources)"
        )
    if "inputs/records.csv" in required_source_paths(row):
        mappings.append("- task records -> `inputs/records.csv` (materialized evaluation source)")
    if not mappings:
        mappings.append("- no additional task source required")
    if row["id"] == 5:
        (inputs / "agenda.txt").write_text(
            "item-003.docx\nitem-001.docx\nitem-005.docx\nitem-002.docx\nitem-004.docx\n",
            encoding="utf-8",
        )
    if "inputs/last-quarter-board-memo.md" in required_source_paths(row):
        prior_memo = inputs / "last-quarter-board-memo.md"
        prior_memo.write_text(
            "# Q2 Board Memo\n\n## Performance\nRevenue was $500,000.\n\n"
            "## Operations\nOperating spend was $390,000.\n\n"
            "## Accounts\nNorthstar had 21 open days.\n",
            encoding="utf-8",
        )
        mappings.append("- `last quarter's memo` -> `inputs/last-quarter-board-memo.md`")
    (inputs / "source-map.md").write_text(
        "# Source map\n\n" + "\n".join(mappings) + "\n",
        encoding="utf-8",
    )

    browser_path = None
    if row["capabilityNeeded"] in BROWSER_CAPABILITIES:
        browser_path = "inputs/browser.html"
        table = task_table(row, "authenticated browser", count=20)
        headers = "".join(f"<th>{html.escape(str(value))}</th>" for value in table[0])
        body = "".join(
            "<tr>" + "".join(f"<td>{html.escape(str(value))}</td>" for value in values) + "</tr>"
            for values in table[1:21]
        )
        page = (
            "<!doctype html><html><head><title>Atlas evaluation tenant</title></head><body>"
            f"<main><h1>{html.escape(row['category'])}</h1>"
            f"<p data-task-id=\"{row['id']}\">Controlled task {row['id']}</p>"
            f"<pre>{html.escape(context)}</pre>"
            f"<table><thead><tr>{headers}</tr></thead><tbody>{body}</tbody></table>"
            "</main></body></html>"
        )
        (workspace / browser_path).write_text(page, encoding="utf-8")
    return browser_path


def build_prompt(row):
    task = row["task"].strip()
    capability = row["capabilityNeeded"]
    if capability == "Scheduling":
        return f"""{task}

This is an end-to-end native desktop evaluation. Create and persist the requested
recurring automation now. Preserve the cadence and requested action from the original
prompt. Do not merely describe, propose, or draft the automation. Finish only after the
automation is visible in Quill Cowork's persisted automation state.
"""

    browser_instruction = ""
    if capability == "Browser pane":
        browser_instruction = (
            "First inspect the currently open Browser page with the browser inspection tool. "
            "It is the controlled evaluation source for the website or authenticated service. "
        )
    elif capability == "Web research":
        browser_instruction = (
            "Use the native web search and fetch tools against live public sources. Cite the "
            "fetched URL beside every externally sourced fact. Do not treat the local context "
            "packet as a substitute for live research. "
        )
    privacy_instruction = ""
    if capability == "Confidential":
        privacy_instruction = (
            "This run is in real Confidential mode. Keep all source and output handling inside "
            "that mode and do not use public browsing. "
        )
    artifact_instruction = FORMAT_INSTRUCTIONS[output_format(row)]
    pdf_tool_instruction = ""
    if output_format(row) == "pdf":
        pdf_tool_instruction = (
            "When combining PDF files or adding a contents page and bookmarks, use the native "
            "host.pdf.merge tool after producing the ordered inputs. "
        )
    required_inputs = ", ".join(f"`{path}`" for path in required_source_paths(row))
    task_specific_instruction = ""
    if row["id"] == 33:
        task_specific_instruction = (
            "Draft exactly three fully written emails for each of the six prospects (18 emails "
            "total). Group them by contact ID, number each prospect's emails 1 through 3, and "
            "include a concrete subject, greeting, body, call to action, and closing in every "
            "email. Personalize each first paragraph from that prospect's `booth-notes` value. "
            "Do not provide reusable templates or substitution tokens. "
        )
    elif row["id"] == 121:
        task_specific_instruction = (
            "Treat each monthly closing FX rate as USD per one unit of local currency, using "
            "the final published business-day observation in that calendar month. Show the "
            "observation date, currency, source URL, rate, local amount, conversion formula, and "
            "converted USD amount. Apply the rate at row level before calculating any totals. "
        )
    elif row["id"] == 117:
        task_specific_instruction = (
            "Use exactly Asana, Inc., monday.com Ltd., and GitLab Inc. from the named "
            "competitor list; do not substitute product competitors or other peers. Calculate "
            "Atlas Labs Q1 through Q4 revenue from `inputs/records.csv`. For each competitor, "
            "research total company revenue for its four most recently reported fiscal quarters "
            "as of 2026-08-08 using official investor-relations or SEC sources. Preserve the "
            "reported fiscal-quarter labels and period-end dates. Pass a focused query containing "
            "the company, fiscal quarters, and revenue to every `host.web.fetch` call; prefer one "
            "results-history or annual-report page per company over fetching one page per quarter. "
            "Include one comparison table whose body has exactly four company rows: Atlas Labs, "
            "Asana, Inc., monday.com Ltd., and GitLab Inc. Put the company name and all four raw "
            "numeric USD quarterly values in the same `<tr>` for each company. The first five "
            "cells in every company row must be company, oldest revenue, second-oldest revenue, "
            "third-oldest revenue, and newest revenue, in that order. Write each revenue as a "
            "full integer USD amount such as `$181,500,000`, never an M/B abbreviation; keep "
            "fiscal labels and period-end dates in the column headers or source notes. Put at "
            "least one source URL in that same row for every competitor. Do not split a company "
            "across quarter rows or use rowspans. Include an inline SVG chart or a functional canvas "
            "chart comparing "
            "all four series across oldest-to-newest reporting position; clearly disclose a log "
            "scale if one is needed to keep Atlas visible. Before finishing, inspect the saved "
            "HTML, verify all four same-row records and the chart, and remove checkpoint, progress, "
            "or future-tense completion language. "
        )
    elif row["id"] == 125:
        task_specific_instruction = (
            "Update the supplied current policy in full; do not replace it with a change memo or "
            "research log. Use the current IRS standard business mileage rate effective for 2026 "
            "from an official IRS source, cite the exact IRS URL next to the rate, and set the new "
            "$75 daily meal cap. Make both changes effective 2026-01-01, increment the policy "
            "version, preserve every unaffected provision and named owner/approver, and include a "
            "short revision history. Use `inputs/records.csv` to verify the before/after treatment "
            "of all five claims, including the pre-effective-date row. Do not call the company meal "
            "cap a GSA or IRS rate. Remove draft, checkpoint, pending, next-pass, and future-work "
            "language before readback. "
        )
    elif row["id"] == 126:
        task_specific_instruction = (
            "Use the official BLS CPI-U U.S. city average, All items, not seasonally "
            "adjusted series `CUUR0000SA0`. Use its annual-average indexes for 2023 and "
            "2024. For 2025, first check whether BLS publishes a calendar-year annual "
            "average. If it does not because a monthly observation is unavailable, compute "
            "the arithmetic mean of the published 2025 monthly indexes, state the observation "
            "count and missing month, and label the result an observed-month proxy, never an "
            "annual average. Use the latest published monthly 2026 index as the target "
            "2026-dollar benchmark. Explicitly name that 2026 month and disclose that it "
            "is a monthly benchmark rather than a completed annual average. Cite the exact "
            "official BLS URL next to the CPI figures. Restate every nominal revenue row in "
            "`inputs/records.csv` with `real revenue = nominal revenue x (latest 2026 CPI / "
            "that year's selected CPI basis index)`. Show nominal and real dollars, CPI basis, "
            "nominal and real year-over-year growth, and cumulative 2023-to-2025 growth. "
            "Keep full precision in calculations and round displayed dollars to the nearest "
            "dollar. Do not invent a 2025 missing-month value. Do not invent a full-year "
            "2026 CPI value. "
            "Every fiscal-year row must include its nominal revenue, selected CPI basis, "
            "recalculated real revenue, and growth result. After writing the deliverable, run "
            "a deterministic post-write validator that parses it, independently recalculates "
            "each real-revenue value from the stated full-precision CPI inputs, and rejects any "
            "repeated dollar amount or growth result that disagrees with the canonical result. "
            "Before readback, remove duplicate or malformed Markdown table headers. "
        )
    field_instruction = (
        "Because the requested deliverable is a reusable macro, named bracketed runtime "
        "fields such as `[Invoice Number]` are allowed. Document every runtime field, but "
        "do not leave generic TBD, TODO, insert, or unscoped placeholders."
        if row["id"] in REUSABLE_TEMPLATE_TASKS else
        "Do not leave template placeholders or blank fields."
    )
    return f"""{task}

This is an end-to-end native desktop evaluation using an isolated workspace. The
original prompt above is authoritative. All local files, folders, documents, exports,
and account records it references are materialized in this workspace and mapped in
`inputs/source-map.md`. Read every applicable source directly before acting. For this
task the required inputs are: {required_inputs}. The mapped files are present,
standards-complete, sufficient, and take the place of any path outside this isolated
workspace. Do not install dependencies.
{browser_instruction}{privacy_instruction}
Complete the requested analysis or transformation using those supplied records. Never
modify a real external account or anything outside the workspace. Represent requested
renames, deletions, messages, service updates, or other side effects as an exact action
log in the deliverable. Do not ask a follow-up question and do not stop at a proposal.
{task_specific_instruction}{pdf_tool_instruction}

Save the complete, decision-ready result to `{output_path(row)}`. Include specific
source facts, rows or calculations, owners, dates, uncertainties, and the actions taken
or simulated. {artifact_instruction} {field_instruction}
After writing, read the saved artifact back with the file tool to verify its contents and
format. A prose summary is not a substitute for the requested artifact.
"""


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool_payload(tool, field):
    try:
        value = json.loads(tool.get(field) or "{}")
    except (TypeError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def tool_succeeded(tool):
    if tool.get("status") not in {"done", "completed", "succeeded"}:
        return False
    output = tool_payload(tool, "outputJSON")
    return output.get("ok", True) is not False


def tool_path(tool):
    payload = tool_payload(tool, "inputJSON")
    value = payload.get("path") or payload.get("filePath") or payload.get("file_path") or ""
    return str(value).replace("\\", "/").lstrip("./")


def tool_command(tool):
    payload = tool_payload(tool, "inputJSON")
    value = payload.get("cmd") or payload.get("command") or payload.get("script") or ""
    return str(value).replace("\\", "/")


def tool_content(tool):
    payload = tool_payload(tool, "inputJSON")
    return str(payload.get("content") or "")


def tool_paths(tool, key):
    payload = tool_payload(tool, "inputJSON")
    value = payload.get(key)
    if isinstance(value, list):
        return [str(item).replace("\\", "/").lstrip("./") for item in value]
    if isinstance(value, str):
        return [value.replace("\\", "/").lstrip("./")]
    return []


def path_matches(actual, expected):
    actual = actual.rstrip("/")
    expected = expected.rstrip("/")
    return actual == expected or actual.endswith(f"/{expected}")


def shell_command_references_path(command, path):
    normalized_path = path.replace("\\", "/").strip("/")
    normalized_command = command.replace("\\", "/")
    unquoted_command = normalized_command.replace('"', "").replace("'", "")
    return normalized_path in normalized_command or normalized_path in unquoted_command


def shell_command_inspects_path(command, path):
    if not shell_command_references_path(command, path):
        return False
    original = command.lower().replace("\\", "/")
    normalized = original.replace('"', "").replace("'", "")
    normalized_path = path.replace("\\", "/").strip("/").lower()
    literal = rf"(?:['\"]){re.escape(normalized_path)}(?:['\"])"
    parser_call = re.compile(
        r"(?:load_workbook|zipfile(?:\.zipfile)?|pdfreader|pdfplumber\.open|"
        r"document|read_excel|read_csv|image\.open|et\.parse)"
        rf"\s*\([^)]*{re.escape(normalized_path)}"
    )
    pathlib_read = re.compile(
        rf"{re.escape(normalized_path)}[^;\n]{{0,120}}\.read_(?:text|bytes)\s*\("
    )
    command_readers = re.compile(
        r"(?:^|[;&|\s])(?:cat|head|tail|file|unzip|zipinfo|pdfinfo|pdftotext|"
        r"identify|sips|xmllint)(?:\s|$)"
        rf"[^;&|\n]*{re.escape(normalized_path)}"
    )
    direct_open = re.compile(
        rf"open\s*\(\s*{literal}\s*(?:\)|,\s*(?!['\"](?:w|a|x)b?['\"]))",
        flags=re.IGNORECASE,
    )
    if bool(
        parser_call.search(normalized)
        or pathlib_read.search(normalized)
        or command_readers.search(normalized)
        or direct_open.search(original)
    ):
        return True
    assignment = re.search(
        rf"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*{literal}",
        original,
        flags=re.IGNORECASE,
    )
    if not assignment:
        return False
    variable = re.escape(assignment.group(1))
    variable_reader = re.compile(
        rf"open\s*\(\s*{variable}\s*(?:\)|,\s*(?!['\"](?:w|a|x)b?['\"]))",
        flags=re.IGNORECASE,
    )
    return bool(variable_reader.search(original))


def shell_command_writes_path(command, path):
    if not shell_command_references_path(command, path):
        return False
    normalized = command.replace("\\", "/")
    normalized_path = path.replace("\\", "/").strip("/")
    literal = rf"(?:['\"]){re.escape(normalized_path)}(?:['\"])"
    direct_writers = re.compile(
        rf"(?:open\s*\(\s*{literal}\s*,\s*['\"](?:w|a|x)b?['\"]|"
        rf"(?:write_text|write_bytes|save|to_csv|to_excel|to_html)\s*\(\s*{literal}|"
        rf">\s*{literal}|"
        rf">>?\s*{re.escape(normalized_path)}(?=\s|$))",
        flags=re.IGNORECASE,
    )
    if direct_writers.search(normalized):
        return True
    assignment = re.search(
        rf"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*{literal}",
        normalized,
        flags=re.IGNORECASE,
    )
    if not assignment:
        return False
    variable = re.escape(assignment.group(1))
    variable_writers = re.compile(
        rf"(?:open\s*\(\s*{variable}\s*,\s*['\"](?:w|a|x)b?['\"]|"
        rf"(?:write_text|write_bytes|save|to_csv|to_excel|to_html)\s*\(\s*{variable}\b)",
        flags=re.IGNORECASE,
    )
    return bool(variable_writers.search(normalized))


def shell_command_executes_path(command, path):
    normalized = command.replace("\\", "/")
    normalized_path = path.replace("\\", "/").lstrip("./")
    quoted_path = rf"(?:['\"])?(?:\./)?{re.escape(normalized_path)}(?:['\"])?"
    interpreter = r"(?:python(?:3(?:\.\d+)?)?|bash|sh|zsh|node|ruby)"
    return bool(re.search(
        rf"(?:^|[;&|]\s*){interpreter}(?:\s+-[A-Za-z]+)*\s+{quoted_path}(?:\s|$)",
        normalized,
        flags=re.IGNORECASE,
    ))


def tool_output_text(tool):
    output = tool_payload(tool, "outputJSON")
    return str(output.get("stdout") or output.get("content") or "")


def package_text(path, prefixes):
    values = []
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if not name.endswith(".xml") or not any(name.startswith(prefix) for prefix in prefixes):
                continue
            try:
                root = ET.fromstring(archive.read(name))
            except ET.ParseError:
                continue
            values.extend(node.text for node in root.iter() if node.text and node.text.strip())
    return "\n".join(values)


def validate_artifact(path, extension):
    try:
        data = path.read_bytes()
    except OSError as error:
        return False, str(error), ""

    if extension == "csv":
        try:
            text = data.decode("utf-8-sig")
            rows = list(csv.reader(text.splitlines()))
        except (UnicodeDecodeError, csv.Error) as error:
            return False, f"invalid CSV: {error}", ""
        width = len(rows[0]) if rows else 0
        rectangular = width >= 2 and all(len(row) == width for row in rows if row)
        valid = len(rows) >= 2 and rectangular
        return valid, f"{len(rows)} rows x {width} columns", text

    if extension in {"xlsx", "docx"}:
        required = {
            "xlsx": {"[Content_Types].xml", "xl/workbook.xml"},
            "docx": {"[Content_Types].xml", "word/document.xml"},
        }[extension]
        try:
            with zipfile.ZipFile(path) as archive:
                names = set(archive.namelist())
                valid = required.issubset(names)
                if extension == "xlsx":
                    valid = valid and any(name.startswith("xl/worksheets/sheet") for name in names)
            text = package_text(path, ("xl/",)) if extension == "xlsx" else package_text(path, ("word/",))
        except (OSError, zipfile.BadZipFile) as error:
            return False, f"invalid {extension.upper()} package: {error}", ""
        return valid, f"{len(data)} bytes; {len(text)} extracted characters", text

    if extension == "pdf":
        valid = data.startswith(b"%PDF-") and b"%%EOF" in data[-2048:] and len(data) >= 500
        text = " ".join(
            value.decode("latin-1", errors="replace")
            for value in re.findall(rb"\(([^()]*)\)\s*Tj", data)
        )
        return valid, f"{len(data)} bytes with PDF signature", text

    if extension == "png":
        valid = data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 33
        width = height = 0
        if valid:
            width, height = struct.unpack(">II", data[16:24])
            valid = width >= 800 and height >= 400 and b"IEND" in data[-32:]
        return valid, f"{width}x{height}; {len(data)} bytes", ""

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        return False, f"invalid UTF-8 text: {error}", ""
    if extension == "html":
        valid = bool(re.search(r"<html\b", text, re.IGNORECASE)) and bool(
            re.search(r"<body\b", text, re.IGNORECASE)
        )
        return valid, f"{len(text)} characters with HTML document structure", text
    if extension == "mmd":
        valid = bool(re.search(r"(?m)^\s*(?:flowchart|graph|sequenceDiagram|classDiagram|stateDiagram)", text))
        return valid, f"{len(text)} characters of Mermaid", text
    return len(text.strip()) >= 200, f"{len(text)} Markdown characters", text


def xlsx_column_number(letters):
    number = 0
    for letter in letters.upper():
        number = number * 26 + ord(letter) - ord("A") + 1
    return number


def xlsx_column_name(number):
    name = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        name = chr(ord("A") + remainder) + name
    return name


def xlsx_sheet_cells(path):
    spreadsheet_namespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    document_relationship_namespace = (
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    )
    with zipfile.ZipFile(path) as archive:
        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        targets = {
            relationship.attrib["Id"]: relationship.attrib["Target"]
            for relationship in relationships
        }
        shared_strings = []
        if "xl/sharedStrings.xml" in archive.namelist():
            shared_root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            shared_strings = [
                "".join(node.text or "" for node in item.iter(f"{{{spreadsheet_namespace}}}t"))
                for item in shared_root.iter(f"{{{spreadsheet_namespace}}}si")
            ]

        sheets = []
        for sheet in workbook.iter(f"{{{spreadsheet_namespace}}}sheet"):
            relationship_id = sheet.attrib[f"{{{document_relationship_namespace}}}id"]
            target = targets[relationship_id]
            package_path = (
                target.lstrip("/")
                if target.startswith("/")
                else posixpath.normpath(posixpath.join("xl", target))
            )
            sheet_root = ET.fromstring(archive.read(package_path))
            cells = []
            for cell in sheet_root.iter(f"{{{spreadsheet_namespace}}}c"):
                coordinate = cell.attrib.get("r", "")
                match = re.fullmatch(r"\$?([A-Za-z]{1,3})\$?(\d+)", coordinate)
                if not match:
                    continue
                column = xlsx_column_number(match.group(1))
                row = int(match.group(2))
                formula_node = cell.find(f"{{{spreadsheet_namespace}}}f")
                formula = formula_node.text or "" if formula_node is not None else None
                value_node = cell.find(f"{{{spreadsheet_namespace}}}v")
                cell_type = cell.attrib.get("t")
                value = None
                if cell_type == "inlineStr":
                    value = "".join(
                        node.text or ""
                        for node in cell.iter(f"{{{spreadsheet_namespace}}}t")
                    )
                elif value_node is not None and value_node.text is not None:
                    raw_value = value_node.text
                    if cell_type == "s":
                        value = shared_strings[int(raw_value)]
                    elif cell_type in {"str", "e"}:
                        value = raw_value
                    elif cell_type == "b":
                        value = raw_value == "1"
                    else:
                        numeric = float(raw_value)
                        value = int(numeric) if numeric.is_integer() else numeric
                cells.append({
                    "coordinate": coordinate.replace("$", "").upper(),
                    "column": column,
                    "row": row,
                    "formula": formula,
                    "value": value,
                })
            sheets.append({"name": sheet.attrib["name"], "cells": cells})
    return sheets


def validate_budget_workbook(path):
    try:
        sheets = xlsx_sheet_cells(path)
    except (ET.ParseError, KeyError, IndexError, OSError, ValueError, zipfile.BadZipFile) as error:
        return False, f"could not inspect budget workbook: {error}"

    sheet_names = [sheet["name"].casefold() for sheet in sheets]
    missing_sheets = []
    if not any("assumption" in name for name in sheet_names):
        missing_sheets.append("assumptions")
    if not any("monthly" in name and "spend" in name for name in sheet_names):
        missing_sheets.append("monthly spend")
    has_quarterly_rollup = any("quarter" in name for name in sheet_names)
    has_quarterly_tabs = all(quarter in sheet_names for quarter in ("q1", "q2", "q3", "q4"))
    if not has_quarterly_rollup and not has_quarterly_tabs:
        missing_sheets.append("quarterly roll-up or Q1-Q4 tabs")

    source_rows = {
        "paid search": 30000,
        "paid social": 24000,
        "content and seo": 18000,
        "events and webinars": 18000,
        "lifecycle email": 15000,
        "partner and abm": 15000,
    }
    matched_source_rows = set()
    strings = set()
    formulas = []
    self_references = []
    invalid_references = []
    cells_by_sheet = {
        sheet["name"].casefold(): {
            cell["coordinate"]: cell for cell in sheet["cells"]
        }
        for sheet in sheets
    }
    qualified_reference = re.compile(
        r"(?:(?:'((?:[^']|'')+)'|([A-Za-z0-9_]+))!)"
        r"\$?([A-Za-z]{1,3})\$?(\d+)"
        r"(?:\s*:\s*\$?([A-Za-z]{1,3})\$?(\d+))?"
    )
    local_reference = re.compile(
        r"(?<![A-Za-z0-9_!:])\$?([A-Za-z]{1,3})\$?(\d+)"
        r"(?:\s*:\s*\$?([A-Za-z]{1,3})\$?(\d+))?"
    )

    def referenced_cells(sheet_name, match):
        min_column = xlsx_column_number(match.group(3))
        min_row = int(match.group(4))
        max_column = xlsx_column_number(match.group(5) or match.group(3))
        max_row = int(match.group(6) or match.group(4))
        for row_number in range(min(min_row, max_row), max(min_row, max_row) + 1):
            for column_number in range(min(min_column, max_column), max(min_column, max_column) + 1):
                yield f"{xlsx_column_name(column_number)}{row_number}"

    def validate_reference(owner, target_sheet, coordinates, display):
        target_cells = cells_by_sheet.get(target_sheet.casefold())
        if target_cells is None:
            invalid_references.append(f"{owner} -> missing sheet {target_sheet!r}")
            return
        for coordinate in coordinates:
            target = target_cells.get(coordinate)
            if target is None:
                invalid_references.append(f"{owner} -> missing {target_sheet}!{coordinate}")
            elif target["formula"] is None and isinstance(target["value"], str):
                invalid_references.append(
                    f"{owner} -> text {target_sheet}!{coordinate}={target['value']!r} via {display}"
                )

    for sheet in sheets:
        rows = {}
        for cell in sheet["cells"]:
            rows.setdefault(cell["row"], []).append(cell)
        for row in rows.values():
            row_strings = {
                value.strip().casefold()
                for cell in row
                if cell["formula"] is None
                and isinstance((value := cell["value"]), str)
            }
            strings.update(row_strings)
            row_numbers = {
                float(cell["value"]) for cell in row
                if isinstance(cell["value"], (int, float))
                and not isinstance(cell["value"], bool)
            }
            for channel, annual_budget in source_rows.items():
                if channel in row_strings and float(annual_budget) in row_numbers:
                    matched_source_rows.add(channel)

            for cell in row:
                formula = cell["formula"]
                if formula is None:
                    continue
                owner = f"{sheet['name']}!{cell['coordinate']}"
                formulas.append(owner)

                for known_name in sheet_names:
                    if " " in known_name and re.search(
                        rf"(?<!')\b{re.escape(known_name)}!",
                        formula,
                        re.IGNORECASE,
                    ):
                        invalid_references.append(
                            f"{owner} -> unquoted sheet name {known_name!r}"
                        )

                masked_formula = list(formula)
                for match in qualified_reference.finditer(formula):
                    target_sheet = (match.group(1) or match.group(2)).replace("''", "'")
                    validate_reference(
                        owner,
                        target_sheet,
                        referenced_cells(target_sheet, match),
                        match.group(0),
                    )
                    for index in range(match.start(), match.end()):
                        masked_formula[index] = " "

                for match in local_reference.finditer("".join(masked_formula)):
                    min_column = xlsx_column_number(match.group(1))
                    min_row = int(match.group(2))
                    max_column = xlsx_column_number(match.group(3) or match.group(1))
                    max_row = int(match.group(4) or match.group(2))
                    if (
                        min(min_column, max_column) <= cell["column"] <= max(min_column, max_column)
                        and min(min_row, max_row) <= cell["row"] <= max(min_row, max_row)
                    ):
                        self_references.append(
                            f"{sheet['name']}!{cell['coordinate']} -> {match.group(0)}"
                        )
                    coordinates = (
                        f"{xlsx_column_name(column_number)}{row_number}"
                        for row_number in range(min(min_row, max_row), max(min_row, max_row) + 1)
                        for column_number in range(min(min_column, max_column), max(min_column, max_column) + 1)
                    )
                    validate_reference(
                        owner,
                        sheet["name"],
                        coordinates,
                        match.group(0),
                    )

    missing_channels = sorted(set(source_rows) - matched_source_rows)
    missing_months = sorted(
        set(("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"))
        - strings
    )
    missing_quarters = sorted(
        set(("q1", "q2", "q3", "q4")) - strings - set(sheet_names)
    )
    valid = not any((
        missing_sheets,
        missing_channels,
        missing_months,
        missing_quarters,
        self_references,
        invalid_references,
    ))
    valid = valid and len(formulas) >= 12
    detail = (
        f"sheets={[sheet['name'] for sheet in sheets]}; formulas={len(formulas)}; "
        f"missing sheets={missing_sheets}; missing source rows={missing_channels}; "
        f"missing months={missing_months}; "
        f"missing quarters={missing_quarters}; self references={self_references[:8]}"
        f"; invalid references={invalid_references[:12]}"
    )
    return valid, detail


def validate_task_33_sequence(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        return False, f"could not read sequence: {error}"

    source = path.parents[1] / "inputs" / "conference-leads.csv"
    try:
        with source.open(encoding="utf-8", newline="") as stream:
            prospects = list(csv.DictReader(stream))
    except (OSError, csv.Error) as error:
        return False, f"could not read prospects: {error}"

    missing_sections = []
    missing_email_numbers = []
    missing_booth_anchors = []
    prospect_by_id = {prospect["contact_id"]: prospect for prospect in prospects}
    contact_ids = "|".join(re.escape(contact_id) for contact_id in prospect_by_id)
    section_heading = re.compile(
        rf"(?im)^\s*(?:#{{1,6}}\s+|\*\*)[^\n]{{0,80}}?\b({contact_ids})\b"
    )
    positions = []
    seen_ids = set()
    for match in section_heading.finditer(text):
        contact_id = match.group(1).upper()
        if contact_id in seen_ids:
            continue
        seen_ids.add(contact_id)
        positions.append((match.start(), contact_id, prospect_by_id[contact_id]))

    missing_sections.extend(
        contact_id for contact_id in prospect_by_id if contact_id not in seen_ids
    )

    positions.sort()
    for index, (start, contact_id, prospect) in enumerate(positions):
        end = positions[index + 1][0] if index + 1 < len(positions) else len(text)
        section = text[start:end]
        email_numbers = {
            int(number)
            for number in re.findall(r"(?i)\bemail\s*(?:#|no\.?\s*)?([123])\b", section)
        }
        subject_count = len(
            re.findall(
                r"(?im)^\s*(?:[-*+]\s+|\d+\.\s+)?(?:\*\*)?subject\b",
                section,
            )
        )
        if email_numbers != {1, 2, 3} or subject_count < 3:
            missing_email_numbers.append(
                f"{contact_id}: email numbers={sorted(email_numbers)}, subjects={subject_count}"
            )

        note_words = [
            word for word in normalized_words(prospect["booth-notes"])
            if len(word) >= 4 and word not in {"asked", "before", "three", "with"}
        ]
        required_note_words = set(note_words[:3])
        section_words = set(normalized_words(section))
        if len(required_note_words & section_words) < min(2, len(required_note_words)):
            missing_booth_anchors.append(
                f"{contact_id}: expected anchors={sorted(required_note_words)}"
            )

    placeholders = re.findall(
        r"\{[^{}\n]{1,80}\}|\[(?:your|insert|tbd|todo|first\s+name|name|company|date|"
        r"owner|sender|hook|time|relevant|value\s+prop|placeholder)[^\]\n]*\]",
        visible_prose(text),
        flags=re.IGNORECASE,
    )
    valid = not any((
        missing_sections,
        missing_email_numbers,
        missing_booth_anchors,
        placeholders,
        len(prospects) != 6,
    ))
    detail = (
        f"prospects={len(prospects)}; missing sections={missing_sections}; "
        f"incomplete sequences={missing_email_numbers}; missing booth anchors={missing_booth_anchors}; "
        f"placeholders={placeholders[:12]}"
    )
    return valid, detail


class _Task117TableParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tables = []
        self._table = None
        self._section = None
        self._row = None
        self._cell = None

    def handle_starttag(self, tag, attrs):
        tag = tag.casefold()
        if tag == "table" and self._table is None:
            self._table = {"rows": []}
        elif self._table is not None and tag in {"thead", "tbody", "tfoot"}:
            self._section = tag
        elif self._table is not None and tag == "tr" and self._row is None:
            self._row = {"section": self._section, "cells": []}
        elif self._row is not None and tag in {"td", "th"} and self._cell is None:
            self._cell = {"tag": tag, "text": [], "links": []}
        elif self._cell is not None and tag == "a":
            attributes = dict(attrs)
            if attributes.get("href"):
                self._cell["links"].append(attributes["href"])

    def handle_endtag(self, tag):
        tag = tag.casefold()
        if tag in {"td", "th"} and self._cell is not None and self._row is not None:
            self._cell["text"] = re.sub(
                r"\s+", " ", " ".join(self._cell["text"])
            ).strip()
            self._row["cells"].append(self._cell)
            self._cell = None
        elif tag == "tr" and self._row is not None and self._table is not None:
            self._table["rows"].append(self._row)
            self._row = None
        elif tag in {"thead", "tbody", "tfoot"} and self._table is not None:
            self._section = None
        elif tag == "table" and self._table is not None:
            self.tables.append(self._table)
            self._table = None
            self._section = None
            self._row = None
            self._cell = None

    def handle_data(self, data):
        if self._cell is not None:
            self._cell["text"].append(data)


def _task_117_company_rows(text):
    parser = _Task117TableParser()
    parser.feed(text)
    parser.close()

    comparison_table = None
    for table in parser.tables:
        if any(
            row["cells"]
            and row["cells"][0]["tag"] == "th"
            and row["cells"][0]["text"].strip().casefold() == "company"
            for row in table["rows"]
        ):
            comparison_table = table
            break
    if comparison_table is None:
        return []

    body_rows = [
        row for row in comparison_table["rows"] if row["section"] == "tbody"
    ]
    if body_rows:
        return body_rows
    return [
        row for row in comparison_table["rows"]
        if row["cells"] and row["cells"][0]["tag"] == "td"
    ]


def validate_task_117_revenue_chart(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        return False, f"could not read revenue chart: {error}"

    source = path.parents[1] / "inputs" / "records.csv"
    try:
        with source.open(encoding="utf-8", newline="") as stream:
            records = list(csv.DictReader(stream))
        atlas_totals = Counter()
        for record in records:
            atlas_totals[record["quarter"]] += int(record["revenue"])
    except (OSError, csv.Error, KeyError, TypeError, ValueError) as error:
        return False, f"could not recompute Atlas revenue: {error}"

    plain = html.unescape(re.sub(r"(?is)<[^>]+>", " ", text))
    compact_plain = re.sub(r"[$,\s]", "", plain).casefold()
    missing_totals = [
        f"{quarter}={atlas_totals.get(quarter, 0)}"
        for quarter in ("Q1", "Q2", "Q3", "Q4")
        if str(atlas_totals.get(quarter, 0)) not in compact_plain
    ]

    company_labels = {
        "Atlas Labs": "atlaslabs",
        "Asana, Inc.": "asanainc",
        "monday.com Ltd.": "mondaycomltd",
        "GitLab Inc.": "gitlabinc",
    }
    table_rows = _task_117_company_rows(text)
    missing_company_rows = []
    duplicate_company_rows = []
    incomplete_company_rows = []
    missing_row_citations = []
    table_series = []
    for company, normalized_name in company_labels.items():
        matching_rows = [
            row for row in table_rows
            if row["cells"]
            and re.sub(
                r"[^a-z0-9]+", "", row["cells"][0]["text"].casefold()
            ) == normalized_name
        ]
        if not matching_rows:
            missing_company_rows.append(company)
            continue
        if len(matching_rows) != 1:
            duplicate_company_rows.append(f"{company}: {len(matching_rows)} rows")
        row = matching_rows[0]
        cells = [cell["text"] for cell in row["cells"]]
        value_cells = cells[1:5]
        raw_usd_values = [
            re.sub(r"[$,\s]", "", value, flags=re.IGNORECASE)
            for value in value_cells
        ]
        if len(value_cells) != 4 or any(
            not re.fullmatch(r"(?:USD)?\d+", value, re.IGNORECASE)
            for value in raw_usd_values
        ):
            incomplete_company_rows.append(f"{company}: {value_cells}")
        else:
            table_series.append([int(value.removeprefix("USD")) for value in raw_usd_values])
        row_links = [link for cell in row["cells"] for link in cell["links"]]
        if company != "Atlas Labs" and not any(
            re.match(r"https?://", link, re.I) for link in row_links
        ):
            missing_row_citations.append(company)

    svg_shapes = len(re.findall(r"(?i)<(?:rect|path|polyline|line|circle)\b", text))
    has_svg_chart = bool(re.search(r"(?i)<svg\b", text)) and svg_shapes >= 4
    has_canvas_chart = bool(re.search(r"(?i)<canvas\b", text)) and bool(
        re.search(r"(?i)new\s+Chart\s*\(|getContext\s*\(|chart\.js", text)
    )
    missing_quarters = [
        quarter for quarter in ("Q1", "Q2", "Q3", "Q4")
        if not re.search(rf"\b{quarter}\b", plain, re.I)
    ]
    polyline_series = []
    for _, points_text in re.findall(
        r"(?is)<polyline\b[^>]*\bpoints\s*=\s*(['\"])(.*?)\1",
        text,
    ):
        numbers = [float(value) for value in re.findall(r"-?(?:\d+(?:\.\d*)?|\.\d+)", points_text)]
        if len(numbers) == 8:
            polyline_series.append([numbers[index] for index in range(1, 8, 2)])

    def direction_signature(values, invert=False):
        signature = []
        for previous, current in zip(values, values[1:]):
            delta = current - previous
            if abs(delta) <= 0.01:
                signature.append(0)
            elif invert:
                signature.append(-1 if delta > 0 else 1)
            else:
                signature.append(1 if delta > 0 else -1)
        return tuple(signature)

    svg_series_geometry = "not applicable"
    invalid_svg_series_geometry = False
    if polyline_series:
        table_directions = Counter(direction_signature(values) for values in table_series)
        chart_directions = Counter(
            direction_signature(y_values, invert=True) for y_values in polyline_series
        )
        invalid_svg_series_geometry = (
            len(table_series) != 4
            or len(polyline_series) != 4
            or table_directions != chart_directions
        )
        svg_series_geometry = (
            f"table={dict(table_directions)}; chart={dict(chart_directions)}"
        )

    valid = not any((
        missing_totals,
        missing_company_rows,
        duplicate_company_rows,
        incomplete_company_rows,
        missing_row_citations,
        missing_quarters,
        not (has_svg_chart or has_canvas_chart),
        invalid_svg_series_geometry,
    ))
    detail = (
        f"records={len(records)}; Atlas totals={dict(atlas_totals)}; "
        f"missing totals={missing_totals}; missing company rows={missing_company_rows}; "
        f"duplicate company rows={duplicate_company_rows}; "
        f"incomplete company rows={incomplete_company_rows}; "
        f"missing row citations={missing_row_citations}; missing quarters={missing_quarters}; "
        f"svg shapes={svg_shapes}; svg series geometry={svg_series_geometry}; "
        f"canvas chart={has_canvas_chart}"
    )
    return valid, detail


def validate_task_126_real_revenue(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        return False, f"could not read real-revenue analysis: {error}"

    normalized = re.sub(r"[$,\s]", "", text).casefold()
    compact_text = re.sub(r"\s+", " ", text)
    missing_years = [year for year in ("2023", "2024", "2025", "2026") if year not in text]
    missing_nominal_revenue = [
        value for value in ("4200000", "5100000", "6000000")
        if value not in normalized
    ]
    dollar_values = {
        int(value.replace(",", ""))
        for value in re.findall(r"\$\s*(\d[\d,]{5,})", text)
    }
    cpi_values = {}
    missing_cpi_years = []
    for year in (2023, 2024, 2025, 2026):
        candidates = []
        pattern = re.compile(
            rf"\b{year}\b[^\n]{{0,80}}?\b([23]\d{{2}}\.\d{{3,9}})\b"
        )
        for match in pattern.finditer(text):
            raw_value = match.group(1)
            try:
                candidates.append((len(raw_value.partition(".")[2]), Decimal(raw_value)))
            except InvalidOperation:
                continue
        if candidates:
            cpi_values[year] = max(candidates, key=lambda candidate: candidate[0])[1]
        else:
            missing_cpi_years.append(year)

    nominal_by_year = {2023: 4200000, 2024: 5100000, 2025: 6000000}
    expected_real_by_year = {}
    inconsistent_dollar_values = []
    expected_growth_percentages = []
    inconsistent_percentage_values = []
    if not missing_cpi_years:
        target_cpi = cpi_values[2026]
        adjusted_by_year = {}
        for year, nominal in nominal_by_year.items():
            adjusted = Decimal(nominal) * target_cpi / cpi_values[year]
            adjusted_by_year[year] = adjusted
            expected_real_by_year[year] = int(adjusted.quantize(
                Decimal("1"),
                rounding=ROUND_HALF_UP,
            ))
        allowed_values = set(nominal_by_year.values()) | set(expected_real_by_year.values())
        inconsistent_dollar_values = sorted(
            value for value in dollar_values
            if value >= 1_000_000
            and not any(abs(value - allowed) <= 1 for allowed in allowed_values)
        )
        expected_growth_percentages = [
            (Decimal(nominal_by_year[2024]) / nominal_by_year[2023] - 1) * 100,
            (Decimal(nominal_by_year[2025]) / nominal_by_year[2024] - 1) * 100,
            (Decimal(nominal_by_year[2025]) / nominal_by_year[2023] - 1) * 100,
            (adjusted_by_year[2024] / adjusted_by_year[2023] - 1) * 100,
            (adjusted_by_year[2025] / adjusted_by_year[2024] - 1) * 100,
            (adjusted_by_year[2025] / adjusted_by_year[2023] - 1) * 100,
        ]
        percentage_values = {
            Decimal(value)
            for value in re.findall(r"(?<![\d.])([+-]?\d+(?:\.\d+)?)\s*%", text)
        }
        inconsistent_percentage_values = sorted(
            value for value in percentage_values
            if not any(
                abs(value - expected) <= Decimal("0.02")
                for expected in expected_growth_percentages
            )
        )
    revenue_table_headers = [
        line for line in text.splitlines()
        if line.lstrip().startswith("|")
        and "year" in line.casefold()
        and "nominal" in line.casefold()
        and "real" in line.casefold()
    ]
    mislabeled_2025_average = bool(
        re.search(
            r"2025.{0,80}annual[- ]average\s*\([^)]*(?:11|partial|missing)",
            compact_text,
            re.I,
        )
        or re.search(
            r"2025.{0,120}annual[- ]average.{0,100}(?:uses|computed from).{0,10}11",
            compact_text,
            re.I,
        )
        or re.search(r"\ban annual[- ]average\s*\([^)]*11", compact_text, re.I)
    )
    checks = {
        "series": "cuur0000sa0" in text.casefold(),
        "official BLS URL": bool(re.search(r"https?://(?:[a-z0-9-]+\.)?bls\.gov/", text, re.I)),
        "annual-average basis": bool(re.search(r"annual[- ]average", text, re.I)),
        "2025 unavailable annual average": bool(
            re.search(
                r"2025.{0,100}annual[- ]average.{0,100}"
                r"(?:unavailable|not (?:available|published)|cannot be calculated)",
                compact_text,
                re.I,
            )
        ),
        "2025 observed-month proxy": bool(
            re.search(r"2025", text)
            and re.search(r"11[- ](?:month|observation)|11 (?:published|observed) months", text, re.I)
            and re.search(r"observed[- ]month proxy|partial[- ]year proxy", text, re.I)
            and re.search(r"october", text, re.I)
        ),
        "2025 basis is not mislabeled": not mislabeled_2025_average,
        "not seasonally adjusted basis": bool(re.search(r"not seasonally adjusted", text, re.I)),
        "2026 monthly benchmark disclosure": bool(
            re.search(r"2026", text)
            and re.search(r"monthly|month", text, re.I)
            and re.search(r"latest|benchmark", text, re.I)
        ),
        "real-dollar basis": bool(re.search(r"2026[- ]dollars|2026 dollars", text, re.I)),
        "adjustment formula": bool(
            re.search(r"real\s+revenue", text, re.I)
            and re.search(r"nominal\s+revenue", text, re.I)
            and ("/" in text or "÷" in text)
        ),
        "growth comparison": bool(re.search(r"year[- ]over[- ]year|yoy", text, re.I)),
        "cumulative growth comparison": bool(
            re.search(r"cumulative", text, re.I)
            and re.search(r"2023.{0,20}2025", compact_text, re.I)
        ),
        "three adjusted amounts": len(dollar_values) >= 6,
        "CPI values for deterministic recomputation": not missing_cpi_years,
        "internally consistent dollar calculations": not inconsistent_dollar_values,
        "internally consistent growth calculations": not inconsistent_percentage_values,
        "one well-formed revenue table": (
            len(revenue_table_headers) == 1
            and revenue_table_headers[0].count("|") >= 4
        ),
    }
    failed = [name for name, passed in checks.items() if not passed]
    valid = not missing_years and not missing_nominal_revenue and not failed
    detail = (
        f"missing years={missing_years}; missing nominal revenue={missing_nominal_revenue}; "
        f"failed checks={failed}; CPI values={cpi_values}; expected real={expected_real_by_year}; "
        f"inconsistent dollar values={inconsistent_dollar_values}; "
        f"inconsistent percentages={inconsistent_percentage_values}; "
        f"unique large dollar values={len(dollar_values)}"
    )
    return valid, detail


def visible_prose(text):
    text = re.sub(
        r"(?is)<(?:style|script|pre|code)\b[^>]*>.*?</(?:style|script|pre|code)\s*>",
        "",
        text,
    )
    lines = []
    in_fence = False
    for line in text.splitlines():
        trimmed = line.strip()
        if trimmed.startswith("```") or trimmed.startswith("~~~"):
            in_fence = not in_fence
            continue
        if not in_fence:
            lines.append(re.sub(r"`[^`]*`", "", line))
    return "\n".join(lines)


def unresolved_placeholders(row, text):
    prose = visible_prose(text)
    placeholders = re.findall(r"\{[^{}\n]{1,80}\}", prose)
    if row["id"] in REUSABLE_TEMPLATE_TASKS:
        bracket_pattern = (
            r"\[(?:(?:your|insert|tbd|todo|placeholder)\b[^\]\n]*|"
            r"(?:first\s+name|name|company|date|owner|sender|hook|time|relevant|"
            r"value\s+prop))\]"
        )
    else:
        bracket_pattern = (
            r"\[(?:your|insert|tbd|todo|first\s+name|name|company|date|owner|sender|"
            r"hook|time|relevant|value\s+prop|placeholder)[^\]\n]*\]"
        )
    placeholders.extend(re.findall(bracket_pattern, prose, flags=re.IGNORECASE))
    return placeholders


def grade(row, workspace, report, source_hashes):
    checks = []

    def add(name, passed, detail):
        checks.append({"name": name, "passed": bool(passed), "detail": detail})

    lifecycle_detail = "no report"
    if report:
        lifecycle_detail = (
            report.get("desktopCaptureError")
            or report.get("lastError")
            or report.get("stopReasonDetail")
            or (
                f"windowSource={report.get('windowSource')!r}; "
                f"workspaceWindowCount={report.get('workspaceWindowCount')!r}"
            )
        )
    add("desktop lifecycle", bool(report and report.get("ok")), lifecycle_detail)
    if row["capabilityNeeded"] == "Confidential":
        add("confidential mode", bool(report and report.get("isConfidential")), repr(report.get("isConfidential") if report else None))
        add(
            "confidential route pinned",
            bool(report and report.get("requestedModelID") == report.get("selectedModelID") != EXACT_MODEL),
            report.get("selectedModelID") if report else "no report",
        )
    else:
        add(
            "exact model",
            bool(report and report.get("requestedModelID") == EXACT_MODEL and report.get("selectedModelID") == EXACT_MODEL),
            report.get("selectedModelID") if report else "no report",
        )

    window_source = report.get("windowSource") if report else None
    workspace_window_count = report.get("workspaceWindowCount") if report else None
    add(
        "native physical window ownership",
        window_source in {"swiftui-scene", "eval-native-fallback"}
        and workspace_window_count == 1,
        f"windowSource={window_source!r}; workspaceWindowCount={workspace_window_count!r}",
    )

    screenshot = report.get("screenshot") if report else None
    add(
        "native desktop window screenshot",
        isinstance(screenshot, dict)
        and screenshot.get("distinctColorBuckets", 0) >= 14
        and Path(screenshot.get("path", "")).is_file(),
        repr(screenshot),
    )

    if row["capabilityNeeded"] == "Scheduling":
        automation = report.get("scheduledAutomation") if report else None
        add("persisted automation", isinstance(automation, dict) and bool(automation.get("id")), repr(automation))
        return checks, None

    tools = report.get("tools", []) if report else []
    successful = [tool for tool in tools if tool_succeeded(tool)]
    names = [tool.get("name") for tool in successful]
    read_paths = [
        tool_path(tool) for tool in successful if tool.get("name") == "host.file.read"
    ]
    batch_read_paths = [
        path
        for tool in successful if tool.get("name") == "host.file.read_many"
        for path in tool_paths(tool, "paths")
    ]
    add("source reads", len(read_paths + batch_read_paths) >= 2, repr(names))
    merge_input_paths = [
        path
        for tool in successful if tool.get("name") == "host.pdf.merge"
        for path in tool_paths(tool, "inputs")
    ]
    consumed_paths = read_paths + batch_read_paths + merge_input_paths
    shell_commands = [
        tool_command(tool) for tool in successful if tool.get("name") == "host.shell.run"
    ]
    unread_sources = []
    for path in required_source_paths(row):
        source = workspace / path
        if source.is_dir():
            members = [
                item.relative_to(workspace).as_posix()
                for item in source.rglob("*") if item.is_file()
            ]
            missing = [
                member for member in members
                if not any(path_matches(consumed, member) for consumed in consumed_paths)
            ]
            if missing and not any(
                shell_command_references_path(command, path)
                for command in shell_commands
            ):
                unread_sources.extend(missing)
        elif (
            not any(path_matches(consumed, path) for consumed in consumed_paths)
            and not any(
                shell_command_references_path(command, path)
                for command in shell_commands
            )
        ):
            unread_sources.append(path)
    add("mapped source consumption", not unread_sources, f"unconsumed {unread_sources[:20]}")
    target = output_path(row)
    writes = []
    written_scripts = {}
    for tool in successful:
        name = tool.get("name")
        direct_write = (
            tool.get("name") in {"host.file.write", "host.chart.render"}
            and tool_path(tool).endswith(target)
        )
        shell_write = (
            name == "host.shell.run"
            and (
                shell_command_references_path(tool_output_text(tool), target)
                or shell_command_writes_path(tool_command(tool), target)
            )
        )
        scripted_write = (
            name == "host.shell.run"
            and any(
                shell_command_executes_path(tool_command(tool), script_path)
                and shell_command_writes_path(script_content, target)
                for script_path, script_content in written_scripts.items()
            )
        )
        merged_write = (
            name == "host.pdf.merge"
            and any(path_matches(path, target) for path in tool_paths(tool, "output"))
        )
        if direct_write or shell_write or scripted_write or merged_write:
            writes.append(tool)
        if name == "host.file.write":
            written_scripts[tool_path(tool)] = tool_content(tool)
    reads = [tool for tool in successful if tool.get("name") == "host.file.read" and tool_path(tool).endswith(target)]
    shell_reads = [
        tool for tool in successful
        if tool.get("name") == "host.shell.run"
        and shell_command_inspects_path(tool_command(tool), target)
        and tool_output_text(tool).strip()
    ]
    add("artifact write", bool(writes), repr(names))
    add("artifact verification", bool(reads or shell_reads), repr(names))
    if row["capabilityNeeded"] == "Browser pane":
        add("browser inspection", "host.browser.inspect" in names, repr(names))
    if row["capabilityNeeded"] == "Web research":
        add("live web search", "host.web.search" in names, repr(names))
    add(
        "sources unchanged",
        all(path.exists() and sha256(path) == digest for path, digest in source_hashes.items()),
        "fixture hashes",
    )

    artifact = workspace / target
    extension = output_format(row)
    valid, format_detail, artifact_text = validate_artifact(artifact, extension)
    add("primary artifact format", valid, format_detail)
    if row["id"] == 19:
        budget_valid, budget_detail = validate_budget_workbook(artifact)
        add("budget workbook semantics", budget_valid, budget_detail)
    if row["id"] == 33:
        sequence_valid, sequence_detail = validate_task_33_sequence(artifact)
        add("complete personalized email sequences", sequence_valid, sequence_detail)
    if row["id"] == 117:
        chart_valid, chart_detail = validate_task_117_revenue_chart(artifact)
        add("quarterly revenue chart semantics", chart_valid, chart_detail)
    if row["id"] == 126:
        revenue_valid, revenue_detail = validate_task_126_real_revenue(artifact)
        add("real revenue trend semantics", revenue_valid, revenue_detail)
    verification_text = "\n".join(tool_output_text(tool) for tool in reads + shell_reads)
    combined_text = "\n".join(
        value for value in (artifact_text, verification_text, report.get("finalAnswer", "") if report else "")
        if value
    )
    if extension == "md":
        add(
            "substantive artifact",
            len(artifact_text) >= 600 and len(artifact_text.splitlines()) >= 10,
            f"{len(artifact_text)} chars",
        )
        add(
            "structured artifact",
            bool(re.search(r"(?m)^#{1,4}\s|^[-*]\s|^\|.+\|$", artifact_text)),
            "heading, list, or table",
        )
    elif extension != "png":
        add("substantive artifact", len(combined_text) >= 120, f"{len(combined_text)} extracted chars")
    matched = matched_task_terms(row, combined_text)
    required = min(2, len(task_terms(row)))
    if extension != "png":
        add("task coverage", len(matched) >= required, f"matched {matched}; required {required}")
    if extension != "png":
        grounded = matched_source_grounding_anchors(row, workspace, combined_text)
        add(
            "source grounding",
            len(grounded) >= 2,
            f"matched {grounded[:12]}; required 2 task-specific source anchors",
        )
    if row["capabilityNeeded"] == "Web research":
        citations = set(re.findall(r"https?://[^\s)>\]]+", combined_text))
        required_citations = minimum_source_citation_count(row)
        add(
            "source citations",
            len(citations) >= required_citations,
            f"{len(citations)} unique URLs; required {required_citations}",
        )
    placeholders = unresolved_placeholders(row, artifact_text)
    add("no template placeholders", not placeholders, repr(placeholders))
    return checks, artifact


def sanitize(value, secret):
    return value.replace(secret, "[REDACTED]")


def run_case(binary, row, root, key, timeout, keep_homes):
    case_dir = root / "runs" / str(row["id"])
    workspace = case_dir / "workspace"
    home = Path(tempfile.mkdtemp(prefix=f"quill-prior-{row['id']}-home-"))
    workspace.mkdir(parents=True)
    browser_path = write_fixture(row, workspace)
    prompt_path = case_dir / "prompt.txt"
    report_path = case_dir / "desktop-report.json"
    screenshot_path = case_dir / "desktop-window.png"
    stdout_path = case_dir / "stdout.txt"
    stderr_path = case_dir / "stderr.txt"
    prompt_path.write_text(build_prompt(row), encoding="utf-8")
    source_hashes = {path: sha256(path) for path in workspace.rglob("*") if path.is_file()}
    command = [
        str(binary), "--cowork-eval",
        "--cowork-eval-home", str(home),
        "--cowork-eval-workspace", str(workspace),
        "--cowork-eval-prompt-file", str(prompt_path),
        "--cowork-eval-report", str(report_path),
        "--cowork-eval-screenshot", str(screenshot_path),
        "--cowork-eval-model", EXACT_MODEL,
        "--cowork-eval-timeout-seconds", str(timeout),
        "--cowork-eval-max-tool-steps", "512",
    ]
    if browser_path:
        command.extend(["--cowork-eval-browser-path", browser_path])
    if row["capabilityNeeded"] == "Confidential":
        command.append("--cowork-eval-confidential")
    environment = os.environ.copy()
    environment["QUILLCODE_API_KEY"] = key
    environment.pop("TRUSTEDROUTER_API_KEY", None)
    environment.pop("QUILLCODE_USE_MOCK_LLM", None)

    started = time.monotonic()
    timed_out = False
    try:
        completed = subprocess.run(
            command, cwd=ROOT, env=environment, capture_output=True, text=True,
            timeout=timeout + 30, check=False,
        )
        exit_code, stdout, stderr = completed.returncode, completed.stdout, completed.stderr
    except subprocess.TimeoutExpired as error:
        timed_out = True
        exit_code = 124
        stdout, stderr = error.stdout or "", error.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        stderr += f"\nProcess timeout after {timeout + 30} seconds.\n"
    duration_ms = round((time.monotonic() - started) * 1000)
    stdout_path.write_text(sanitize(stdout, key), encoding="utf-8")
    stderr_path.write_text(sanitize(stderr, key), encoding="utf-8")
    report = read_json(report_path) if report_path.exists() else None
    checks, artifact = grade(row, workspace, report, source_hashes)
    passed = exit_code == 0 and not timed_out and all(check["passed"] for check in checks)

    if keep_homes:
        retained = case_dir / "home"
        shutil.move(str(home), retained)
        home_record = str(retained.relative_to(root))
    else:
        shutil.rmtree(home, ignore_errors=True)
        home_record = None
    return {
        "id": row["id"],
        "wave": row["wave"],
        "category": row["category"],
        "capability": row["capabilityNeeded"],
        "evidenceClass": evidence_class(row),
        "passed": passed,
        "exitCode": exit_code,
        "timedOut": timed_out,
        "durationMilliseconds": duration_ms,
        "usage": report.get("usage", {}) if report else {},
        "tools": [tool.get("name") for tool in report.get("tools", [])] if report else [],
        "checks": checks,
        "paths": {
            "workspace": str(workspace.relative_to(root)),
            "output": str(artifact.relative_to(root)) if artifact else None,
            "report": str(report_path.relative_to(root)) if report_path.exists() else None,
            "screenshot": str(screenshot_path.relative_to(root)) if screenshot_path.exists() else None,
            "stdout": str(stdout_path.relative_to(root)),
            "stderr": str(stderr_path.relative_to(root)),
            "home": home_record,
        },
    }


def write_summary(root, results):
    results = sorted(results, key=lambda item: item["id"])
    usage = {
        key: sum(item.get("usage", {}).get(key, 0) for item in results)
        for key in ("promptTokens", "completionTokens", "totalTokens")
    }
    evidence = Counter(item["evidenceClass"] for item in results)
    summary = {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "model": EXACT_MODEL,
        "confidentialModelPolicy": "TrustedRouter end-to-end encrypted route",
        "passed": sum(item["passed"] for item in results),
        "total": len(results),
        "usage": usage,
        "evidenceClasses": dict(sorted(evidence.items())),
        "results": results,
    }
    (root / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = [
        "# Prior-wave native Cowork evaluation", "",
        f"- Result: {summary['passed']}/{summary['total']} passed",
        f"- Standard model: `{EXACT_MODEL}`",
        "- Confidential tasks: TrustedRouter end-to-end encrypted model route",
        f"- Tokens: {usage['totalTokens']} total", "", "## Evidence classes", "",
    ]
    lines.extend(f"- `{name}`: {count}" for name, count in sorted(evidence.items()))
    failures = [item for item in results if not item["passed"]]
    if failures:
        lines.extend(["", "## Failures", ""])
        for item in failures:
            failed = ", ".join(check["name"] for check in item["checks"] if not check["passed"])
            lines.append(f"- {item['id']}: {failed}")
    (root / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return summary


def run_cases_serially(binary, rows, root, key, timeout, keep_homes):
    results = []
    for row in rows:
        case_id = row["id"]
        try:
            result = run_case(binary, row, root, key, timeout, keep_homes)
        except Exception as error:
            result = {
                "id": case_id, "wave": "unknown", "category": "unknown",
                "capability": "unknown", "evidenceClass": "unknown", "passed": False,
                "exitCode": None, "timedOut": False, "durationMilliseconds": 0,
                "usage": {}, "tools": [],
                "checks": [{"name": "runner exception", "passed": False, "detail": str(error)}],
                "paths": {},
            }
        results.append(result)
        status = "PASS" if result["passed"] else "FAIL"
        print(f"[{len(results)}/{len(rows)}] task {case_id}: {status}", flush=True)
    return results


def main():
    args = parse_args()
    if args.model != EXACT_MODEL:
        raise EvalError(f"Model must be exactly {EXACT_MODEL}")
    if args.workers != 1:
        raise EvalError("--workers must be 1 because simultaneous AppKit launches abort")
    if not 30 <= args.timeout <= 3_600:
        raise EvalError("--timeout must be between 30 and 3600 seconds")
    rows = select_cases(validate_catalog(read_json(args.catalog)), args.case_ids)
    if args.validate_only:
        print(json.dumps({"ok": True, "cases": len(rows), "model": EXACT_MODEL}, sort_keys=True))
        return 0
    if not args.binary.is_file():
        raise EvalError(f"Desktop binary not found: {args.binary}")
    key = load_api_key(args.key_file)
    root = artifact_root(args.artifact_dir)
    results = run_cases_serially(
        args.binary.resolve(), rows, root, key, args.timeout, args.keep_homes
    )
    summary = write_summary(root, results)
    print(f"Artifacts: {root}")
    print(f"Result: {summary['passed']}/{summary['total']} passed")
    return 0 if summary["passed"] == summary["total"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvalError as error:
        print(f"prior-wave-cowork-evals: {error}", file=sys.stderr)
        raise SystemExit(2)
