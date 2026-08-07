#!/usr/bin/env python3
"""Drive all Wave 5 founder tasks through the native Cowork desktop controller."""

import argparse
import concurrent.futures
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_CATALOG = ROOT / "docs" / "founder-task-additions.json"
CASE_FIXTURE_CATALOG = ROOT / "docs" / "wave5-case-fixtures.json"
DEFAULT_BINARY = ROOT / ".build" / "debug" / "quill-code-desktop"
EXACT_MODEL = "deepseek/deepseek-v4-flash-0731"
EXPECTED_IDS = set(range(211, 311))
EXPECTED_CATEGORIES = {
    "Customer Discovery",
    "Founder Sales",
    "Product & Roadmap",
    "Launch & Growth",
    "Fundraising",
    "Finance & Runway",
    "Hiring & Team",
    "Investor & Board Updates",
    "Operations & Compliance",
    "Pricing & Competitive Intelligence",
}
KEY_FILES = (
    Path.home() / ".quillcode" / "secrets" / "trustedrouter_api_key",
    Path.home() / ".quill.code.keyfile",
)


class EvalError(RuntimeError):
    pass


def load_case_fixture_catalog():
    try:
        payload = json.loads(CASE_FIXTURE_CATALOG.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvalError(f"Cannot read case fixtures {CASE_FIXTURE_CATALOG}: {error}") from error
    raw_cases = payload.get("cases")
    if payload.get("version") != 1 or not isinstance(raw_cases, dict):
        raise EvalError("Wave 5 case fixtures must be version 1 with cases")
    try:
        return {int(case_id): fixture for case_id, fixture in raw_cases.items()}
    except (TypeError, ValueError) as error:
        raise EvalError("Wave 5 case fixture IDs must be numeric") from error


CASE_FIXTURES = load_case_fixture_catalog()


CATEGORY_FIXTURES = {
    "Customer Discovery": {
        "anchors": ["LedgerLoop", "Series A", "finance", "six hours", "Northstar"],
        "context": """# LedgerLoop customer discovery packet

LedgerLoop is a B2B SaaS close-operations product. The current ICP hypothesis is Series A B2B SaaS finance teams with 20-80 employees and a five-to-ten-day monthly close.

The three problem hypotheses are: handoffs across spreadsheets and Slack cost six hours per close; owners miss dependencies because there is no shared status; and controllers cannot explain late close work to the CFO. Do not treat these as proven.

Repeated evidence: Northstar Labs controller Maya Chen said, "I spend six hours chasing owners every close." Four of six Series A finance leads described missed dependencies. One growth-stage customer did not report this pain. Activated customers named a deadline-triggered need and completed the Close Checklist in 48 hours; churned customers expected automated bookkeeping and stalled during CSV mapping.

Unknowns: budget ownership below Series A, willingness to replace spreadsheets, and whether the pain recurs outside month-end. Research participants must consent to note-taking. Never invent a quote or missing fact.
""",
        "header": "record_id,segment,status,source,signal,quote,severity,owner\n",
        "rows": [
            f"I-{index:02d},{'Series A' if index <= 18 else 'Growth'},"
            f"{'activated' if index % 3 else 'churned'},interview,"
            f"{'missed dependency' if index % 2 else 'handoff chasing'},"
            f"{'I spend six hours chasing owners every close' if index == 1 else 'source note ' + str(index)},"
            f"{1 + index % 5},{'controller' if index % 2 else 'finance lead'}\n"
            for index in range(1, 26)
        ],
    },
    "Founder Sales": {
        "anchors": ["LedgerLoop", "Northstar Labs", "Maya Chen", "June 18", "$24,000"],
        "context": """# LedgerLoop founder-sales packet

LedgerLoop sells close-operations software to Series A B2B SaaS finance teams. Approved proof: Northstar Labs reduced owner-chasing from six hours to two hours over two closes. Never claim bookkeeping automation or a guaranteed close-time reduction.

Northstar Labs champion Maya Chen is Controller; economic buyer Rafael Ortiz is CFO. Verified priority: make dependency ownership visible before the June 18 board close. Open question: SSO timing. The proposed annual amount is $24,000. Founder owner is Jo. Desired next step is a 30-minute workflow validation with Rafael on June 12.

Pipeline rules: committed requires buyer-confirmed amount, date, and decision process; likely requires a champion and scheduled next step; upside lacks one of those; unqualified lacks verified pain. Close dates older than 21 days without activity are stale.
""",
        "header": "account,segment,trigger,champion,stage,amount,last_activity,close_date,outcome,objection\n",
        "rows": [
            f"Account {index:02d},Series A SaaS,{'new controller' if index % 2 else 'board close'},"
            f"{'reachable' if index % 3 else 'unknown'},"
            f"{'demo' if index % 4 else 'discovery'},{18000 + index * 500},2026-05-{(index % 28)+1:02d},"
            f"2026-0{6 + index % 2}-{(index % 27)+1:02d},{'won' if index % 7 == 0 else 'open'},"
            f"{'security review' if index % 5 == 0 else 'spreadsheet works'}\n"
            for index in range(1, 51)
        ],
    },
    "Product & Roadmap": {
        "anchors": [
            "LedgerLoop", "Close Checklist", "activation", "48 hours", "CSV mapping",
            "timezone", "Q3", "rollback owner",
        ],
        "context": """# LedgerLoop product packet

LedgerLoop's Close Checklist coordinates month-end owners and dependencies for Series A finance teams. Activation is completing the first checklist with three owners within 48 hours. Baseline activation is 42%.

Research evidence: four of six finance leads report missed dependencies; Northstar Labs cut owner-chasing from six to two hours. Beta blockers are unreliable CSV mapping and missing reminder timezone controls. Delight signal: controllers share the dependency view in CFO staff meetings. Non-goals this cycle: automated bookkeeping, ERP replacement, and custom reporting.

Current commitment: Northstar was told timezone-safe reminders are targeted for Q3, not promised for a date. Rollout must include event validation, migration dry run, support brief, rollback owner, and a seven-day review.
""",
        "header": "id,type,title,segment,frequency,severity,effort,evidence,status\n",
        "rows": [
            f"P-{index:02d},{'bug' if index % 3 == 0 else 'request'},"
            f"{'CSV mapping failure' if index % 5 == 0 else 'dependency reminder workflow'},Series A,"
            f"{2 + index % 8},{1 + index % 5},{1 + index % 8},source-{index:02d},open\n"
            for index in range(1, 21)
        ],
    },
    "Launch & Growth": {
        "anchors": ["LedgerLoop", "Close Checklist", "42%", "finance leaders", "six hours"],
        "context": """# LedgerLoop launch and growth packet

Product: LedgerLoop Close Checklist for Series A finance leaders. Positioning must focus on visible dependency ownership during month-end, not generic productivity. Approved proof: Northstar Labs reduced owner-chasing from six hours to two hours over two closes.

Current funnel: 1,200 qualified visits, 144 signups, 91 workspaces created, 60 checklists started, and 38 activated accounts. Activation means three owners complete the first checklist within 48 hours; baseline activation is 42%. Mobile traffic rose 30% while mobile signup conversion fell from 9% to 5%.

Customer questions cluster around spreadsheet migration, reminder control, audit history, security, and whether LedgerLoop replaces the ERP. It does not replace the ERP. Release owner is Priya; target launch is September 15; rollback trigger is more than 2% checklist-save errors for 15 minutes.
""",
        "header": "channel,audience,asset_or_page,visits,conversions,cost,question\n",
        "rows": [
            "founder-linkedin,finance leaders,dependency post,420,34,0,How do reminders work?\n",
            "partner-newsletter,controllers,migration guide,310,29,1200,Can I import a spreadsheet?\n",
            "search,month-end teams,close checklist page,470,28,2600,Does it replace our ERP?\n",
            "product,activated users,referral prompt,180,18,0,Can I invite an auditor?\n",
        ],
    },
    "Fundraising": {
        "anchors": ["LedgerLoop", "$54,000", "18%", "$820,000", "seed"],
        "context": """# LedgerLoop seed fundraising packet

LedgerLoop helps Series A B2B SaaS finance teams coordinate month-end dependencies. Founder insight came from 31 finance interviews. Current metrics: $54,000 MRR, 18% quarter-over-quarter MRR growth, 42% activation, 109% gross revenue retention, $820,000 cash, and $98,000 monthly net burn. The company is raising a $3.0M seed to reach $150,000 MRR and complete security readiness.

Approved customer proof: Northstar Labs reduced owner-chasing from six hours to two hours over two closes. The market-size model is an internal estimate and must be labeled as such. No patent, SOC 2 certification, profitability, or category-leader claim is supported.

Warm paths: operator Ana Wu can introduce Beacon Seed; customer Rafael Ortiz can reference the workflow. Potential portfolio conflict: Summit Ventures owns a board seat at CloseFlow. Counsel must review term-sheet and governance questions.
""",
        "header": "investor,stage,check_min,check_max,thesis,warm_path,conflict,last_contact,status\n",
        "rows": [
            f"Fund {index:02d},seed,{250000 + index*10000},{1000000 + index*50000},"
            f"{'B2B SaaS' if index % 2 else 'fintech infrastructure'},"
            f"{'Ana Wu' if index == 1 else 'none'},"
            f"{'CloseFlow' if index == 4 else 'none'},2026-0{4 + index % 3}-10,"
            f"{'meeting' if index % 4 == 0 else 'target'}\n"
            for index in range(1, 16)
        ],
    },
    "Finance & Runway": {
        "anchors": ["LedgerLoop", "820000", "54000", "98000", "payroll"],
        "context": """# LedgerLoop finance packet

All amounts are USD. Opening cash on 2026-05-01 was 918000. May cash receipts were 52000; payroll was 71000; non-payroll spend was 79000; ending cash was 820000; net burn was 98000. Current MRR is 54000.

Planned hires: product engineer starting October at 18000 monthly loaded cost and account executive starting December at 21000 monthly loaded cost. Vendor issues: DataGauge appears twice at 2400 monthly; RecruitFast has no owner and renews September 1; OldCRM has 11 unused seats at 120 each.

Collections: Northstar invoice INV-104 is 36 days overdue for 24000 with no dispute; Acme invoice INV-109 is 18 days overdue for 12000 with a tax-form dispute. Probability rules: committed 90%, likely 60%, upside 25%, unqualified 0%. State assumptions and do not manufacture missing months.
""",
        "header": "month,beginning_cash,cash_in,payroll,non_payroll,ending_cash,mrr,budget_burn\n",
        "rows": [
            "2026-03,1110000,45000,68000,71000,1016000,47000,132000\n",
            "2026-04,1016000,49000,70000,77000,918000,50000,140000\n",
            "2026-05,918000,52000,71000,79000,820000,54000,142000\n",
        ],
    },
    "Hiring & Team": {
        "anchors": ["LedgerLoop", "product engineer", "Rina Patel", "180 days", "0.35%"],
        "context": """# LedgerLoop hiring packet

LedgerLoop is hiring its first product engineer. Mission: make the Close Checklist reliable enough that finance teams trust it during month-end. Outcomes: by day 30 ship one instrumented bug fix; by day 90 own CSV mapping reliability; by day 180 raise activation from 42% to 55% without increasing save errors.

Competencies: product judgment, debugging, customer empathy, ownership, and clear written communication. Explicit non-requirements: finance degree, prior management, and a specific framework. Candidate Rina Patel led an import reliability project, but interviewers disagree on product discovery depth. Missing signal: operating directly with customers.

Offer scenarios: A is $175000 cash plus 0.35% equity; B is $190000 plus 0.20%; both use four-year vesting with a one-year cliff. Legal and tax review are required. Contractor Devon owns the reminder service documentation and costs 16000 monthly.
""",
        "header": "candidate_or_role,stage,competency,evidence,score,interviewer,open_question\n",
        "rows": [
            "Rina Patel,onsite,debugging,led import reliability project,4,Jo,none\n",
            "Rina Patel,onsite,product judgment,strong scoping example,4,Priya,customer depth\n",
            "Rina Patel,onsite,customer empathy,no direct example,2,Maya,needs signal\n",
            "Devon Lee,contractor,continuity,owns reminder service docs,4,Jo,classification review\n",
        ],
    },
    "Investor & Board Updates": {
        "anchors": ["LedgerLoop", "54000", "42%", "820000", "Close Checklist"],
        "context": """# LedgerLoop board packet

May results: MRR 54000 versus 50000 plan; activation 42% versus 50% plan; gross revenue retention 109%; ending cash 820000; net burn 98000 versus 90000 plan. Close Checklist save errors rose from 0.8% to 1.4% after the CSV mapping release.

Highlight: Northstar Labs expanded to a second finance workflow. Lowlight: the September 15 launch milestone is at risk because CSV mapping reliability missed its gate. Root cause supported by the incident review: delimiter detection lacked representative fixtures. Corrective action owner Priya; validation gate is below 1% save errors for seven days.

Board decisions requested: approve the product-engineer hire envelope and choose whether to delay the launch. Investor asks: introductions to Series A controllers and a security leader. Do not hide the activation miss or state an unsupported recovery date.
""",
        "header": "metric,april_actual,may_plan,may_actual,owner,explanation_status\n",
        "rows": [
            "MRR,50000,50000,54000,Jo,supported\n",
            "activation_percent,46,50,42,Priya,supported\n",
            "ending_cash,918000,828000,820000,Jo,supported\n",
            "save_error_percent,0.8,0.8,1.4,Priya,supported\n",
        ],
    },
    "Operations & Compliance": {
        "anchors": ["LedgerLoop", "SOC 2", "VantaCloud", "Avery", "September 30"],
        "context": """# LedgerLoop operations and compliance packet

LedgerLoop is a Delaware C corporation operating in California. Delaware franchise tax owner is Jo and the filing deadline is March 1. California payroll registration owner is Avery. Cyber insurance renews September 30 through broker Lin Park.

Security evidence: SSO is enforced for production; quarterly access reviews are documented for Q1 and Q2; backups are tested monthly. LedgerLoop is preparing for SOC 2 but is not certified. Unsupported claims: 24/7 security operations, annual penetration testing, and a zero-incident history.

Vendor VantaCloud processes account email and audit metadata, renews October 15, and lacks a current subprocessor list. Former contractor devon@example.test remains in the identity export; shared account finance-admin@example.test has no owner. Legal questions, contract liability, and employment classification must be routed to counsel.
""",
        "header": "item,owner,due_or_renewal,data_or_scope,evidence,status,risk\n",
        "rows": [
            "Delaware franchise tax,Jo,2027-03-01,corporate,incorporation packet,open,medium\n",
            "Cyber insurance,Avery,2026-09-30,insurance,current policy,open,high\n",
            "VantaCloud,Avery,2026-10-15,email and audit metadata,SOC report,review,high\n",
            "devon@example.test,none,immediate,production access,identity export,former worker,critical\n",
            "finance-admin@example.test,none,immediate,billing admin,identity export,shared,high\n",
        ],
    },
    "Pricing & Competitive Intelligence": {
        "anchors": ["LedgerLoop", "$499", "CloseFlow", "MonthEnd Pro", "42%"],
        "context": """# LedgerLoop pricing and competitive packet

LedgerLoop serves Series A B2B SaaS finance teams. Current pilot price is $499 per workspace per month with unlimited owner seats and email support. Gross margin is 82%; activation is 42%. Value evidence: Northstar Labs reduced owner-chasing from six hours to two hours over two closes.

CloseFlow current page dated 2026-07-15 lists Starter at $399 for five users and Scale at $899 for 20 users; its archived 2026-01-10 page listed Starter at $299 for five users and Pro at $699 for 15 users. MonthEnd Pro lists $79 per user monthly with a ten-user minimum and promotes ERP integrations. Spreadsheet templates are free but lack dependency audit history.

Win-loss evidence: six wins cite fast setup; four losses cite missing SSO; three losses cite price before workflow validation. Willingness-to-pay interviews range from $300 to $1200 monthly and are directional, not a pricing decision. Do not invent competitor capabilities.
""",
        "header": "source,source_date,target_user,package,price,limit,positioning,result_or_signal\n",
        "rows": [
            "CloseFlow current,2026-07-15,finance teams,Starter,399,5 users,close automation,competitor\n",
            "CloseFlow archive,2026-01-10,finance teams,Starter,299,5 users,close automation,competitor\n",
            "MonthEnd Pro current,2026-07-20,controllers,Standard,79,10 user minimum,ERP integrations,competitor\n",
            "LedgerLoop pilot,2026-08-01,Series A finance,Workspace,499,unlimited owners,dependency ownership,42% activation\n",
        ],
    },
}

CONCEPTS = (
    "pain point", "segment", "quote", "frequency", "severity", "unresolved question", "interview guide",
    "follow up", "note taking", "objection", "urgency", "workaround", "decision maker", "jobs to be done",
    "screening", "disqualifier", "assumption", "buying trigger", "success metric", "concierge test",
    "target account", "champion", "cold email", "mutual action plan", "pipeline", "forecast", "demo brief",
    "objection library", "rescue plan", "handoff", "win loss", "backlog", "acceptance criteria", "edge case",
    "instrumentation", "rollout", "roadmap", "mvp", "launch checklist", "beta", "release notes", "event",
    "customer commitment", "incident", "launch plan", "landing page", "growth experiment", "funnel",
    "content calendar", "referral", "product hunt", "seo", "activation email", "retrospective", "narrative",
    "investor", "pitch deck", "data room", "diligence", "term sheet", "runway", "cash", "burn", "vendor",
    "hiring", "unit economics", "gross margin", "acquisition cost", "payback", "collections", "cash control",
    "scorecard", "competenc", "reference check", "offer", "onboarding", "org design", "contractor", "kpi",
    "board", "variance", "action log", "consent", "compliance calendar", "security questionnaire", "vendor due",
    "soc 2", "contract redline", "privacy", "insurance", "incident response", "access review", "procurement",
    "competitor", "pricing", "packaging", "willingness to pay", "discount", "battlecard", "gross margin",
)

CONCEPT_ALIASES = {
    "cold email": ("cold email", "cold outreach", "outbound email"),
    "competitor": ("competitor", "competitive", "competition"),
    "customer commitment": (
        "customer commitment", "customer promise", "sales commitment", "customer-facing commitment",
    ),
    "event": ("event", "trigger"),
    "jobs to be done": ("jobs to be done", "jtbd", "functional job"),
    "landing page": ("landing page", "headline", "subhead", "call to action", "cta"),
    "target account": ("target account", "account prioritization", "priority account", "ranked account"),
    "variance": ("variance", "var vs", "vs plan"),
}

CASE_REQUIRED_OUTPUT_TERMS = {
    256: tuple(f"Fund {index:02d}" for index in range(1, 16)),
}

CASE_PRIMARY_OUTPUT_PATHS = {
    211: "outputs/customer-discovery-synthesis.md",
}

TASK_REFUSAL = re.compile(
    r"(?i)\b(?:i\s+(?:cannot|can't|am unable to)|we\s+(?:cannot|can't|are unable to)|unable to)\s+"
    r"(?:complete|finish|perform|fulfill|create|write|deliver)\s+"
    r"(?:this|the|your)\s+(?:requested\s+)?(?:task|request|work|analysis|deliverable|artifact|file|project)\b"
)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=SOURCE_CATALOG)
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--model", default=EXACT_MODEL)
    parser.add_argument("--case", action="append", dest="case_ids", default=[])
    parser.add_argument("--artifact-dir", type=Path)
    parser.add_argument("--key-file", type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--workers", type=int, default=3)
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
    if payload.get("version") != 1 or not isinstance(rows, list):
        raise EvalError("Wave 5 catalog must be version 1 with rows")
    ids = {row.get("ID") for row in rows}
    if ids != EXPECTED_IDS or len(rows) != 100:
        raise EvalError("Wave 5 catalog must contain IDs 211 through 310 exactly once")
    counts = Counter(row.get("Category") for row in rows)
    if set(counts) != EXPECTED_CATEGORIES or set(counts.values()) != {10}:
        raise EvalError("Wave 5 catalog must contain ten tasks in each of ten categories")
    for row in rows:
        task = row.get("Task (what the person types)")
        capability = row.get("Capability needed")
        if not isinstance(task, str) or not task.strip():
            raise EvalError(f"Task {row.get('ID')} has no prompt")
        if capability not in {"Multi-file artifacts", "Browser pane", "Files/Shell"}:
            raise EvalError(f"Task {row.get('ID')} has unsupported capability {capability}")
    return sorted(rows, key=lambda row: row["ID"])


def validate_case_fixtures():
    unknown = set(CASE_FIXTURES) - EXPECTED_IDS
    if unknown:
        raise EvalError(f"Unknown Wave 5 case fixture IDs: {sorted(unknown)}")
    for case_id, fixture in CASE_FIXTURES.items():
        if not isinstance(fixture, dict) or not isinstance(fixture.get("appendix"), str):
            raise EvalError(f"Case fixture {case_id} must contain an appendix")
        required = fixture.get("requiredOutputTerms", [])
        if not isinstance(required, list) or not all(isinstance(term, str) and term for term in required):
            raise EvalError(f"Case fixture {case_id} has invalid requiredOutputTerms")
        for artifact in fixture.get("additionalArtifacts", []):
            path = artifact.get("path") if isinstance(artifact, dict) else None
            minimum_lines = artifact.get("minimumLines") if isinstance(artifact, dict) else None
            if (
                not isinstance(path, str)
                or not path.startswith("outputs/")
                or ".." in Path(path).parts
                or not isinstance(minimum_lines, int)
                or minimum_lines < 1
            ):
                raise EvalError(f"Case fixture {case_id} has an invalid additional artifact")


def select_cases(rows, requested):
    if not requested:
        return rows
    try:
        ids = {int(value) for value in requested}
    except ValueError as error:
        raise EvalError("--case values must be numeric Wave 5 IDs") from error
    unknown = ids - EXPECTED_IDS
    if unknown:
        raise EvalError(f"Unknown Wave 5 IDs: {sorted(unknown)}")
    return [row for row in rows if row["ID"] in ids]


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
        path = ROOT / ".build" / "quillcode-validation" / "wave5-cowork" / stamp
    if path.exists() and (not path.is_dir() or any(path.iterdir())):
        raise EvalError(f"Artifact directory must be absent or empty: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def normalize(text):
    text = re.sub(r"(?<=\d)[,_](?=\d)", "", text.lower())
    return re.sub(r"[^a-z0-9$%]+", " ", text).strip()


def concept_matches(concept, normalized_output):
    aliases = CONCEPT_ALIASES.get(concept, (concept,))
    return any(normalize(alias) in normalized_output for alias in aliases)


def is_substantive(text):
    lines = text.splitlines()
    nonblank_lines = sum(bool(line.strip()) for line in lines)
    return len(text) >= 600 and (len(lines) >= 12 or nonblank_lines >= 3)


def contains_task_refusal(text):
    return bool(TASK_REFUSAL.search(text))


def contains_placeholder(text):
    if re.search(r"(?i)lorem ipsum", text):
        return True
    for match in re.finditer(r"\[([^\]\n]{0,120})\](?!\()", text):
        field = match.group(1).strip()
        if not field or field.lower() == "x":
            continue
        if re.fullmatch(r"\d+|\^[a-z0-9_.:-]+", field, re.IGNORECASE):
            continue
        return True
    return False


def task_concepts(task):
    normalized = normalize(task)
    return sorted({concept for concept in CONCEPTS if normalize(concept) in normalized})


def required_concept_matches(concept_count):
    if concept_count <= 0:
        return 0
    return min(concept_count, min(4, max(2, (concept_count + 1) // 2)))


def required_output_term_matches(case_id, text):
    fixture_required = CASE_FIXTURES.get(case_id, {}).get("requiredOutputTerms", ())
    required = CASE_REQUIRED_OUTPUT_TERMS.get(case_id, ()) + tuple(fixture_required)
    normalized_output = normalize(text)
    matched = [term for term in required if normalize(term) in normalized_output]
    return required, matched


def grounding_anchors(row):
    fixture_terms = CASE_FIXTURES.get(row["ID"], {}).get("requiredOutputTerms", ())
    return tuple(CATEGORY_FIXTURES[row["Category"]]["anchors"]) + tuple(fixture_terms)


def tool_payload(tool, field):
    raw = tool.get(field)
    if not isinstance(raw, str) or not raw.strip():
        return {}
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}


def tool_succeeded(tool):
    if tool.get("status") != "done":
        return False
    output = tool_payload(tool, "outputJSON")
    if output.get("ok") is False:
        return False
    if output.get("verdict") == "deny" or output.get("reviewOutcome") == "denied":
        return False
    return True


def unrecovered_tool_failures(tools):
    has_later_success = False
    failures = []
    for tool in reversed(tools):
        if tool_succeeded(tool):
            has_later_success = True
        elif not has_later_success:
            failures.append(tool)
    return list(reversed(failures))


def normalized_tool_path(value):
    if not isinstance(value, str):
        return ""
    return value.replace("\\", "/").removeprefix("./").rstrip("/")


def has_artifact_readback(tools, output_path):
    expected = normalized_tool_path(output_path)
    writes = []
    for index, tool in enumerate(tools):
        if not tool_succeeded(tool):
            continue
        name = tool.get("name")
        arguments = tool_payload(tool, "inputJSON")
        if name == "host.file.write":
            path = arguments.get("path") or arguments.get("filename")
            if normalized_tool_path(path) == expected:
                writes.append(index)
        elif name == "host.apply_patch" and expected in json.dumps(arguments):
            writes.append(index)
    if not writes:
        return False
    last_write = max(writes)
    for tool in tools[last_write + 1:]:
        if tool.get("name") != "host.file.read" or not tool_succeeded(tool):
            continue
        arguments = tool_payload(tool, "inputJSON")
        path = arguments.get("path") or arguments.get("filename")
        if normalized_tool_path(path) == expected:
            return True
    return False


def fixture_context(row):
    context = CATEGORY_FIXTURES[row["Category"]]["context"].strip()
    appendix = CASE_FIXTURES.get(row["ID"], {}).get("appendix")
    return f"{context}\n\n{appendix.strip()}\n" if appendix else f"{context}\n"


def primary_output_path(row):
    return CASE_PRIMARY_OUTPUT_PATHS.get(row["ID"], f"outputs/wave5-{row['ID']}.md")


def additional_artifacts(row):
    return CASE_FIXTURES.get(row["ID"], {}).get("additionalArtifacts", [])


def check_additional_artifact(workspace, artifact):
    artifact_path = workspace / artifact["path"]
    try:
        line_count = len(artifact_path.read_text(encoding="utf-8").splitlines())
    except OSError as error:
        return False, str(error)
    required = artifact["minimumLines"]
    return line_count >= required, f"{line_count} lines; required {required}"


def write_fixture(row, workspace):
    fixture = CATEGORY_FIXTURES[row["Category"]]
    context = fixture_context(row)
    inputs = workspace / "inputs"
    inputs.mkdir(parents=True)
    (inputs / "context.md").write_text(context, encoding="utf-8")
    (inputs / "data.csv").write_text(
        fixture["header"] + "".join(fixture["rows"]), encoding="utf-8"
    )
    browser_path = None
    if row["Capability needed"] == "Browser pane":
        browser_path = "inputs/browser.html"
        page = (
            "<!doctype html><html><head><title>LedgerLoop Wave 5 source packet</title></head><body>"
            f"<main><h1>{html.escape(row['Category'])} source packet</h1>"
            f"<pre>{html.escape(context)}</pre>"
            f"<p>Task ID: {row['ID']}</p></main></body></html>"
        )
        (workspace / browser_path).write_text(page, encoding="utf-8")
    return browser_path


def build_prompt(row):
    output_path = primary_output_path(row)
    extra_paths = [artifact["path"] for artifact in additional_artifacts(row)]
    extra_instruction = ""
    if extra_paths:
        quoted = ", ".join(f"`{path}`" for path in extra_paths)
        extra_instruction = f" Also create the required supporting artifact(s): {quoted}."
    capability_instruction = {
        "Browser pane": (
            "First inspect the currently open Browser page with the browser inspection tool. "
            "Also use the file read tool separately on `inputs/context.md` and "
            "`inputs/data.csv`. Do not use the shell tool or list the output directory; after "
            "those three source inspections, write the deliverable directly."
        ),
        "Files/Shell": (
            "Use the file read tool separately on `inputs/context.md` and `inputs/data.csv`, then "
            "use the shell tool for one concise calculation or validation of the numeric source data. "
            "Keep every temporary script and output inside the workspace, inspect the source "
            "schema first, and convert only fields known to be numeric. Do not execute a source "
            "path as a command or list the output directory; after a successful validation, write "
            "the deliverable directly."
        ),
        "Multi-file artifacts": (
            "Use the file read tool separately on `inputs/context.md` and `inputs/data.csv` "
            "before writing. Do not use the shell tool or list the output directory; after those "
            "two reads, write the deliverable directly."
        ),
    }[row["Capability needed"]]
    return f"""{row['Task (what the person types)']}

This is a fixture-backed evaluation. {capability_instruction}
Use only facts in those supplied sources. Do not inspect unrelated workspace files, browse the public web, or send anything externally. If a fact is absent, label it unknown instead of asking a follow-up question or inserting a placeholder. Do not leave bracketed fill-in fields in the completed artifact. When the requested deliverable is itself a reusable template, represent future-entry fields with blank lines, empty cells, or checkboxes instead of bracketed prompts. Never use `[their words]` or any other bracketed substitution token. Honor any deliverable filenames in the original request.

Save the complete primary deliverable to `{output_path}`.{extra_instruction} Make it decision-ready, source-grounded, and specific enough for a founder to use without another rewrite. After writing, read the saved primary file back to verify it.
"""


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def grade(row, workspace, report, source_hashes):
    output_path = primary_output_path(row)
    output = workspace / output_path
    checks = []

    def add(name, passed, detail):
        checks.append({"name": name, "passed": bool(passed), "detail": detail})

    add("desktop lifecycle", bool(report and report.get("ok")), report.get("lastError") if report else "no report")
    add(
        "exact model",
        bool(report and report.get("requestedModelID") == EXACT_MODEL and report.get("selectedModelID") == EXACT_MODEL),
        report.get("selectedModelID") if report else "no report",
    )
    tools = report.get("tools", []) if report else []
    tool_names = [tool.get("name") for tool in tools if tool_succeeded(tool)]
    add("source reads", tool_names.count("host.file.read") >= 2, repr(tool_names))
    add("artifact write", "host.file.write" in tool_names or "host.apply_patch" in tool_names, repr(tool_names))
    add("artifact verification", has_artifact_readback(tools, output_path), repr(tool_names))
    if row["Capability needed"] == "Browser pane":
        add("browser inspection", "host.browser.inspect" in tool_names, repr(tool_names))
    if row["Capability needed"] == "Files/Shell":
        add("shell validation", "host.shell.run" in tool_names, repr(tool_names))
    unrecovered = unrecovered_tool_failures(tools)
    add("tool failures recovered", not unrecovered, repr(unrecovered[-2:]))
    add("sources unchanged", all(path.exists() and sha256(path) == digest for path, digest in source_hashes.items()), "fixture hashes")

    try:
        text = output.read_text(encoding="utf-8")
    except OSError as error:
        text = ""
        add("primary artifact", False, str(error))
    else:
        add("primary artifact", True, f"{len(text)} characters")
    add("substantive", is_substantive(text), f"{len(text)} chars, {len(text.splitlines())} lines")
    add("structured", bool(re.search(r"(?m)^#{1,4}\s|^[-*]\s|^\|.+\|$", text)), "heading, list, or table")
    malformed = "\\n" in text
    add("decoded text", not malformed, "literal escaped newline" if malformed else "clean")
    placeholder = contains_placeholder(text)
    add("no placeholders", not placeholder, "placeholder found" if placeholder else "clean")
    normalized_output = normalize(text)
    anchors = grounding_anchors(row)
    matched_anchors = [anchor for anchor in anchors if normalize(anchor) in normalized_output]
    add("source grounding", len(matched_anchors) >= 2, repr(matched_anchors))
    concepts = task_concepts(row["Task (what the person types)"])
    matched_concepts = [concept for concept in concepts if concept_matches(concept, normalized_output)]
    required = required_concept_matches(len(concepts))
    add("task coverage", len(matched_concepts) >= required, f"matched {matched_concepts}; required {required} of {concepts}")
    required_terms, matched_terms = required_output_term_matches(row["ID"], text)
    if required_terms:
        add(
            "repeated item coverage",
            len(matched_terms) == len(required_terms),
            f"matched {len(matched_terms)} of {len(required_terms)} required items",
        )
    refusal = contains_task_refusal(text)
    add("no refusal", not refusal, "refusal language" if refusal else "clean")
    for artifact in additional_artifacts(row):
        passed, detail = check_additional_artifact(workspace, artifact)
        add(f"supporting artifact {artifact['path']}", passed, detail)
    return checks, output


def sanitize(value, secret):
    return value.replace(secret, "[REDACTED]")


def run_case(binary, row, root, key, timeout, keep_homes):
    case_dir = root / "runs" / str(row["ID"])
    workspace = case_dir / "workspace"
    home = Path(tempfile.mkdtemp(prefix=f"quill-wave5-{row['ID']}-home-"))
    workspace.mkdir(parents=True)
    browser_path = write_fixture(row, workspace)
    prompt = build_prompt(row)
    prompt_path = case_dir / "prompt.txt"
    report_path = case_dir / "desktop-report.json"
    stdout_path = case_dir / "stdout.txt"
    stderr_path = case_dir / "stderr.txt"
    prompt_path.write_text(prompt, encoding="utf-8")
    source_hashes = {path: sha256(path) for path in (workspace / "inputs").iterdir() if path.is_file()}
    command = [
        str(binary),
        "--cowork-eval",
        "--cowork-eval-home", str(home),
        "--cowork-eval-workspace", str(workspace),
        "--cowork-eval-prompt-file", str(prompt_path),
        "--cowork-eval-report", str(report_path),
        "--cowork-eval-model", EXACT_MODEL,
        "--cowork-eval-timeout-seconds", str(timeout),
    ]
    if browser_path:
        command.extend(["--cowork-eval-browser-path", browser_path])
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
    checks, output = grade(row, workspace, report, source_hashes)
    passed = exit_code == 0 and not timed_out and all(check["passed"] for check in checks)

    if keep_homes:
        retained = case_dir / "home"
        shutil.move(str(home), retained)
        home_record = str(retained.relative_to(root))
    else:
        shutil.rmtree(home, ignore_errors=True)
        home_record = None
    return {
        "id": row["ID"],
        "category": row["Category"],
        "capability": row["Capability needed"],
        "passed": passed,
        "exitCode": exit_code,
        "timedOut": timed_out,
        "durationMilliseconds": duration_ms,
        "usage": report.get("usage", {}) if report else {},
        "tools": [tool.get("name") for tool in report.get("tools", [])] if report else [],
        "checks": checks,
        "paths": {
            "workspace": str(workspace.relative_to(root)),
            "output": str(output.relative_to(root)),
            "report": str(report_path.relative_to(root)) if report_path.exists() else None,
            "stdout": str(stdout_path.relative_to(root)),
            "stderr": str(stderr_path.relative_to(root)),
            "home": home_record,
        },
    }


def write_summary(root, results):
    results = sorted(results, key=lambda item: item["id"])
    by_category = {}
    for category in sorted(EXPECTED_CATEGORIES):
        cases = [item for item in results if item["category"] == category]
        if cases:
            by_category[category] = {
                "passed": sum(item["passed"] for item in cases),
                "total": len(cases),
            }
    usage = {
        key: sum(item.get("usage", {}).get(key, 0) for item in results)
        for key in ("promptTokens", "completionTokens", "totalTokens")
    }
    summary = {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "model": EXACT_MODEL,
        "passed": sum(item["passed"] for item in results),
        "total": len(results),
        "usage": usage,
        "categories": by_category,
        "results": results,
    }
    (root / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = [
        "# Wave 5 Cowork evaluation",
        "",
        f"- Model: `{EXACT_MODEL}`",
        f"- Result: {summary['passed']}/{summary['total']} passed",
        f"- Tokens: {usage['totalTokens']} total ({usage['promptTokens']} input, {usage['completionTokens']} output)",
        "",
        "| Category | Passed | Total |",
        "|---|---:|---:|",
    ]
    lines.extend(f"| {name} | {score['passed']} | {score['total']} |" for name, score in by_category.items())
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
    if not 1 <= args.workers <= 4:
        raise EvalError("--workers must be between 1 and 4")
    if not 30 <= args.timeout <= 900:
        raise EvalError("--timeout must be between 30 and 900 seconds")
    validate_case_fixtures()
    rows = select_cases(validate_catalog(read_json(args.catalog)), args.case_ids)
    if len(rows) > 100:
        raise EvalError("Paid invocation fuse exceeded 100 cases")
    for row in rows:
        build_prompt(row)
        if row["Category"] not in CATEGORY_FIXTURES:
            raise EvalError(f"No fixture for {row['Category']}")
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
            executor.submit(
                run_case, args.binary.resolve(), row, root, key, args.timeout, args.keep_homes
            ): row["ID"]
            for row in rows
        }
        for future in concurrent.futures.as_completed(pending):
            result = future.result()
            results.append(result)
            state = "PASS" if result["passed"] else "FAIL"
            print(f"[{state}] {result['id']} ({result['durationMilliseconds']} ms)", flush=True)
    summary = write_summary(root, results)
    leaked = []
    secret_bytes = key.encode("utf-8")
    for path in root.rglob("*"):
        if path.is_file() and secret_bytes in path.read_bytes():
            leaked.append(str(path.relative_to(root)))
    if leaked:
        raise EvalError(f"API key leaked into eval artifacts: {leaked}")
    print(f"Evidence: {root}")
    print(f"Result: {summary['passed']}/{summary['total']} passed")
    return 0 if summary["passed"] == summary["total"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvalError as error:
        print(f"wave5-cowork-evals: {error}", file=sys.stderr)
        raise SystemExit(2)
