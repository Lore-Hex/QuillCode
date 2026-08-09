#!/usr/bin/env python3
"""Drive Waves 1-4 through the visible native Quill Cowork controller.

Every catalog prompt is preserved verbatim. The appended evaluation contract redirects
filesystem and authenticated-service side effects into an isolated per-case workspace,
while confidential and scheduling tasks exercise their real native product modes.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import hashlib
import html
import json
import os
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
    110, 117, 121, 124, 132, 136, 145, 147, 153, 163, 170, 177, 186,
    189, 193, 197, 198, 200, 204, 205, 207, 208, 209,
}
XLSX_TASKS = {19, 62, 63, 74, 158}
PDF_TASKS = {5, 42}
PNG_TASKS = {20}
HTML_TASKS = {40, 82}
DOCX_TASKS = {64}
MERMAID_TASKS = {28}

FORMAT_INSTRUCTIONS = {
    "csv": (
        "Write valid UTF-8 CSV with one header row and one data row per requested record. "
        "Keep prose out of the CSV and use explicit status or notes columns for uncertainty."
    ),
    "xlsx": (
        "Create a real Office Open XML workbook, not CSV or Markdown renamed to .xlsx. "
        "Include the requested sheets, formulas or rollups, and usable column headers."
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
        "inputs/records.csv",
    ]
    paths.extend(mapped_source_path(reference) for reference in source_references(row["task"]))
    paths.extend(spec[1] for spec in COLLECTION_SPECS.get(row["id"], []))
    task = row["task"].casefold()
    if "last quarter" in task and "memo" in task:
        paths.append("inputs/last-quarter-board-memo.md")
    return paths


def mapped_source_path(reference):
    clean = reference.replace("\\", "/").lstrip("./")
    return clean if clean.startswith("inputs/") else f"inputs/{clean}"


def xml_escape(text):
    return html.escape(text, quote=False)


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


def write_xlsx(path):
    path.parent.mkdir(parents=True, exist_ok=True)
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


def materialize_source(path, context, records, item_index=1):
    suffix = path.suffix.casefold()
    if suffix == ".xlsx":
        write_xlsx(path)
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
        path.write_text(records, encoding="utf-8")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(context, encoding="utf-8")


def write_fixture(row, workspace):
    inputs = workspace / "inputs"
    inputs.mkdir(parents=True)
    context = fixture_context(row)
    (inputs / "evaluation-context.md").write_text(context, encoding="utf-8")
    rows = [
        "record_id,name,owner,status,amount,event_date,source,confidence,next_step\n"
    ]
    statuses = ("confirmed", "open", "needs-review", "complete")
    for index in range(1, 41):
        status = statuses[index % len(statuses)]
        owner = ("Priya Shah", "Rafael Ortiz", "Jo Chen", "Avery Lin")[index % 4]
        rows.append(
            f"R-{index:03d},Atlas record {index:02d},{owner},{status},{1200 + index * 175},"
            f"2026-07-{(index % 28) + 1:02d},source-{index:02d},{'high' if index % 3 else 'medium'},"
            f"{'review evidence' if status == 'needs-review' else 'confirm owner'}\n"
        )
    records = "".join(rows)
    (inputs / "records.csv").write_text(records, encoding="utf-8")

    mappings = []
    for reference in source_references(row["task"]):
        mapped = mapped_source_path(reference)
        path = workspace / mapped
        materialize_source(path, context, records)
        mappings.append(f"- `{reference}` -> `{mapped}` (materialized evaluation source)")
    for description, relative, count, extension in COLLECTION_SPECS.get(row["id"], []):
        directory = workspace / relative
        for index in range(1, count + 1):
            item_context = (
                f"{context}\n\n## Collection record {index} of {count}\n\n"
                f"Record ID: TASK-{row['id']}-{index:03d}. Owner: "
                f"{('Priya Shah', 'Rafael Ortiz', 'Jo Chen', 'Avery Lin')[index % 4]}. "
                f"Amount: ${1200 + index * 175}. Event date: 2026-07-{(index % 28) + 1:02d}. "
                f"Status: {statuses[index % len(statuses)]}.\n"
            )
            item = directory / f"item-{index:03d}{extension}"
            materialize_source(item, item_context, records, item_index=index)
        mappings.append(
            f"- `{description}` -> `{relative}` ({count} materialized `{extension}` sources)"
        )
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
        page = (
            "<!doctype html><html><head><title>Atlas evaluation tenant</title></head><body>"
            f"<main><h1>{html.escape(row['category'])}</h1>"
            f"<p data-task-id=\"{row['id']}\">Controlled task {row['id']}</p>"
            f"<pre>{html.escape(context)}</pre>"
            "<table><thead><tr><th>Account</th><th>Status</th><th>Owner</th><th>Next step</th></tr></thead>"
            "<tbody><tr><td>Northstar</td><td>needs-review</td><td>Priya Shah</td>"
            "<td>Validate on 2026-08-22</td></tr><tr><td>Atlas Labs</td><td>confirmed</td>"
            "<td>Rafael Ortiz</td><td>Approve by 2026-09-15</td></tr></tbody></table>"
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
    return f"""{task}

This is an end-to-end native desktop evaluation using an isolated workspace. The
original prompt above is authoritative. All local files, folders, documents, exports,
and account records it references are materialized in this workspace and mapped in
`inputs/source-map.md`. Read that map, `inputs/evaluation-context.md`,
`inputs/records.csv`, and every mapped source path directly with the file tool before
acting. The mapped files are present, standards-complete, sufficient, and take the
place of any path outside this isolated workspace. Do not install dependencies.
{browser_instruction}{privacy_instruction}
Complete the requested analysis or transformation using those supplied records. Never
modify a real external account or anything outside the workspace. Represent requested
renames, deletions, messages, service updates, or other side effects as an exact action
log in the deliverable. Do not ask a follow-up question and do not stop at a proposal.
{pdf_tool_instruction}

Save the complete, decision-ready result to `{output_path(row)}`. Include specific
source facts, rows or calculations, owners, dates, uncertainties, and the actions taken
or simulated. {artifact_instruction} Do not leave template placeholders or blank fields.
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


def grade(row, workspace, report, source_hashes):
    checks = []

    def add(name, passed, detail):
        checks.append({"name": name, "passed": bool(passed), "detail": detail})

    add("desktop lifecycle", bool(report and report.get("ok")), report.get("lastError") if report else "no report")
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
    add("source reads", names.count("host.file.read") >= 2, repr(names))
    read_paths = [
        tool_path(tool) for tool in successful if tool.get("name") == "host.file.read"
    ]
    merge_input_paths = [
        path
        for tool in successful if tool.get("name") == "host.pdf.merge"
        for path in tool_paths(tool, "inputs")
    ]
    consumed_paths = read_paths + merge_input_paths
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
            if missing and not any(path in command for command in shell_commands):
                unread_sources.extend(missing)
        elif (
            not any(path_matches(consumed, path) for consumed in consumed_paths)
            and not any(path in command for command in shell_commands)
        ):
            unread_sources.append(path)
    add("mapped source consumption", not unread_sources, f"unconsumed {unread_sources[:20]}")
    target = output_path(row)
    writes = [
        tool for tool in successful
        if (tool.get("name") == "host.file.write" and tool_path(tool).endswith(target))
        or (tool.get("name") == "host.shell.run" and target in tool_command(tool))
        or (
            tool.get("name") == "host.pdf.merge"
            and any(path_matches(path, target) for path in tool_paths(tool, "output"))
        )
    ]
    reads = [tool for tool in successful if tool.get("name") == "host.file.read" and tool_path(tool).endswith(target)]
    add("artifact write", bool(writes), repr(names))
    add("artifact verification", bool(reads), repr(names))
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
    verification_text = "\n".join(tool_output_text(tool) for tool in reads)
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
    normalized = " ".join(normalized_words(combined_text))
    matched = [term for term in task_terms(row) if term in normalized]
    required = min(3, len(task_terms(row)))
    if extension != "png":
        add("task coverage", len(matched) >= required, f"matched {matched}; required {required}")
    grounded = sum(term in normalized for term in ("atlas", "priya", "rafael", "2026", "northstar"))
    if extension != "png":
        add("source grounding", grounded >= 2, f"matched {grounded} source anchors")
    if row["capabilityNeeded"] == "Web research":
        citations = re.findall(r"https?://[^\s)>\]]+", combined_text)
        add("source citations", len(set(citations)) >= 2, f"{len(set(citations))} unique URLs")
    placeholders = re.findall(
        r"\[(?:your|insert|tbd|todo|name|company|date|owner|placeholder)[^\]]*\]",
        combined_text,
        flags=re.IGNORECASE,
    )
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
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        pending = {
            executor.submit(run_case, args.binary.resolve(), row, root, key, args.timeout, args.keep_homes): row["id"]
            for row in rows
        }
        for future in concurrent.futures.as_completed(pending):
            case_id = pending[future]
            try:
                result = future.result()
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
