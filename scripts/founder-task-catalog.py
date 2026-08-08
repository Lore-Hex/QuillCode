#!/usr/bin/env python3
"""Generate and validate the YC-style founder task catalog addition."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / "docs" / "founder-task-additions.json"
SPREADSHEET_URL = (
    "https://docs.google.com/spreadsheets/d/"
    "1uq8uYGwoAxdwPcVn11nysjoozZjKY4acYZNVw-Hu5LM/edit?gid=0#gid=0"
)
START_ID = 211
EXPECTED_TASK_COUNT = 100
REVIEW_DATE = "2026-08-07"
WAVE = "Wave 5 - YC founder workflows"
STATUS = "Verified end-to-end"
EVIDENCE = (
    "PASS native Cowork UI (2026-08-07; deepseek/deepseek-v4-flash-0731): "
    "uninterrupted Wave 5 re-drive passed 100/100 with fixture-backed source-use, "
    "lifecycle, artifact-write, and readback checks; evidence "
    ".build/quillcode-validation/wave5-cowork/full-r74"
)
CAPABILITY_OVERRIDES = {
    230: "Files/Shell",
    233: "Files/Shell",
}


GROUPS = [
    {
        "category": "Customer Discovery",
        "role": "Founder / CEO",
        "capability": "Multi-file artifacts",
        "supply": "Interview transcripts, notes, ICP hypotheses, and any existing research taxonomy",
        "why": "Compresses raw customer evidence into decisions the founding team can review in one sitting",
        "tasks": [
            "Synthesize these 25 customer interviews into a ranked pain-point report by segment, with supporting quotes, frequency, severity, and unresolved questions. Save customer-discovery-synthesis.md.",
            "Create a 30-minute customer interview guide to test our ICP and top three problem hypotheses without leading the participant. Include follow-up probes and a note-taking template.",
            "Tag these lost-demo notes by primary objection, urgency, current workaround, decision maker, and next evidence needed. Produce lost-demo-patterns.csv and a one-page summary.",
            "Compare interviews from activated customers and customers who churned. Identify the five clearest differences in trigger, expectations, onboarding friction, and realized value.",
            "Turn this folder of feature requests into a jobs-to-be-done map. Separate requested solutions from underlying jobs and cite the source note for every job.",
            "Build a recruiting brief for 12 discovery interviews across our three target segments, including screening criteria, outreach copy, scheduling fields, and disqualifiers.",
            "Create an evidence map for our ten riskiest customer assumptions. Mark each assumption supported, contradicted, or unknown and link it to the interview evidence.",
            "Summarize this discovery call into problem, current alternatives, budget ownership, buying trigger, success metric, and follow-up questions. Do not infer missing facts.",
            "Produce a weekly customer-insight digest from these support tickets, sales calls, and interview notes. Deduplicate themes and separate anecdotes from repeated patterns.",
            "Design a two-week concierge test for this problem hypothesis, including participant criteria, manual workflow, success thresholds, daily observations, and a stop-or-continue decision rule.",
        ],
    },
    {
        "category": "Founder Sales",
        "role": "Founder-led Sales",
        "capability": "Browser pane",
        "supply": "CRM export, account notes, call transcripts, target profile, and approved messaging",
        "why": "Reduces founder time spent researching, updating, and following up on early sales opportunities",
        "tasks": [
            "Prioritize these 50 target accounts using our ICP, recent trigger events, likely pain, and reachable champion. Produce a scored account list with a reason for every rank.",
            "Draft five genuinely personalized cold emails for the highest-ranked accounts using only facts in the supplied research. Include one concise follow-up for each.",
            "Turn these discovery and demo notes into a mutual action plan with buyer owner, founder owner, milestone, date, dependency, and decision criterion.",
            "Rebuild this early-stage pipeline forecast from the CRM export. Separate committed, likely, upside, and unqualified revenue and flag every stale or unsupported close date.",
            "Prepare a demo brief for tomorrow's prospect: company context, participants, likely pains, proof points to show, questions to ask, landmines, and the desired next step.",
            "Draft same-day follow-up emails for these eight sales calls. Each email must recap verified priorities, answer open questions, and propose one concrete next step.",
            "Create a founder-sales objection library from these call transcripts. Group exact objections, diagnose the underlying concern, and write evidence-backed responses without inventing claims.",
            "Build a rescue plan for opportunities with no activity in 21 days. Recommend close, nurture, or re-engage and draft the appropriate message for each account.",
            "Create a clean handoff packet for the first account executive from the founder's notes, including account history, stakeholders, commitments, risks, and next actions.",
            "Run a win-loss review across closed opportunities. Quantify patterns by segment, source, competitor, objection, sales-cycle length, and founder action to change next month.",
        ],
    },
    {
        "category": "Product & Roadmap",
        "role": "Technical Founder",
        "capability": "Multi-file artifacts",
        "supply": "Roadmap, issue tracker export, customer evidence, product metrics, and engineering constraints",
        "why": "Turns scattered product evidence into scoped, testable priorities without another planning meeting",
        "tasks": [
            "Triage this combined bug, support, and feature-request backlog. Deduplicate items, link customer evidence, estimate impact and urgency, and propose the top ten next actions.",
            "Write a concise PRD for this workflow using the supplied research. Include user, problem, non-goals, acceptance criteria, edge cases, instrumentation, rollout, and open questions.",
            "Score these roadmap candidates using reach, impact, confidence, effort, strategic fit, and evidence quality. Show the math and identify assumptions that could change the ranking.",
            "Scope the smallest credible MVP for this idea. Separate must-have behavior, manual operations, deferred capabilities, technical spikes, and a two-week validation plan.",
            "Create a feature launch checklist spanning engineering, QA, migration, analytics, documentation, support, sales enablement, rollback, and post-launch review.",
            "Synthesize this beta feedback into blockers, usability friction, missing value, delight, and noise. Recommend ship, extend beta, narrow scope, or stop with evidence.",
            "Draft customer-facing release notes from these merged pull requests and issue links. Explain user value, limitations, migration steps, and known issues without exposing internal jargon.",
            "Design an instrumentation plan for the activation funnel. Define events, required properties, identity rules, success metrics, guardrails, dashboards, and validation queries.",
            "Compare customer commitments in these sales notes against the current roadmap. Flag conflicts, unowned promises, date risk, and language that needs correction.",
            "Convert this incident timeline and support fallout into product learnings. Propose prevention work, detection improvements, customer remediation, and roadmap tradeoffs.",
        ],
    },
    {
        "category": "Launch & Growth",
        "role": "Growth Founder",
        "capability": "Browser pane",
        "supply": "Product positioning, analytics export, channel history, customer language, and launch constraints",
        "why": "Lets a small team run disciplined growth experiments and launches from existing evidence",
        "tasks": [
            "Build a four-week launch plan for this product release with audience, message, channel, asset, owner, deadline, dependency, success metric, and rollback trigger.",
            "Rewrite this landing page from the customer research. Produce headline, subhead, problem, proof, workflow, objection handling, CTA, and three testable variants.",
            "Prioritize ten growth experiments by expected impact, confidence, effort, time to signal, and reversibility. Define the smallest test and pass-fail threshold for each.",
            "Diagnose this week's acquisition-to-activation funnel. Quantify the largest changes, segment the drop-offs, list plausible causes, and specify the next queries or experiments.",
            "Create a six-week founder-led content calendar from our customer questions and product insights. Include audience, angle, format, distribution, reuse plan, and measurable goal.",
            "Design a referral loop for our current product behavior. Specify trigger, incentive, sharing surface, abuse controls, attribution, and the metrics that prove incremental growth.",
            "Prepare a Product Hunt launch packet with positioning, maker comment, FAQ, response bank, launch-day schedule, outreach list structure, and post-launch follow-up.",
            "Build an SEO topic map from these customer questions and competitor pages. Cluster by intent, propose pillar and supporting pages, and flag claims requiring original evidence.",
            "Draft a seven-message activation email sequence tied to actual user milestones. Include audience rule, send timing, goal, copy, CTA, and suppression condition for each message.",
            "Run a post-launch retrospective from the plan, analytics, support log, and team notes. Separate outcomes from stories and recommend keep, change, stop, and investigate actions.",
        ],
    },
    {
        "category": "Fundraising",
        "role": "Founder / CEO",
        "capability": "Multi-file artifacts",
        "supply": "Pitch materials, metrics, investor notes, cap table assumptions, and company narrative",
        "why": "Produces consistent fundraising materials and follow-ups while keeping every claim traceable",
        "tasks": [
            "Turn these company notes and metrics into a seed fundraising narrative covering insight, problem, product, why now, traction, market, moat, team, and use of funds.",
            "Build a prioritized investor target list from the supplied fund profiles. Score stage, check size, thesis, relevant portfolio conflicts, warm paths, and likely fit.",
            "Audit this pitch deck for unsupported claims, inconsistent numbers, missing context, weak transitions, and likely partner objections. Produce a slide-by-slide fix list.",
            "Create a diligence-ready data-room index with requested artifact, owner, status, sensitivity, freshness date, investor visibility, and missing-item follow-up.",
            "Build a diligence Q&A bank from investor emails and meeting notes. Draft concise evidence-backed answers and mark every answer that needs founder, legal, or finance confirmation.",
            "Draft personalized investor outreach for the top 15 targets using only the supplied relationship and thesis evidence. Keep each note under 120 words.",
            "Clean this fundraising pipeline. Deduplicate investors, normalize stages, identify missing next steps, calculate funnel conversion, and flag stale conversations.",
            "Prepare a partner-meeting brief with attendee backgrounds, prior questions, likely objections, metric definitions, competitive framing, and the three outcomes we need.",
            "Draft customer-reference requests for fundraising. Match each investor concern to an appropriate customer, explain the ask, and minimize burden on the customer.",
            "Compare these term sheets across economics, control, dilution, option pool, liquidation, pro rata, governance, closing conditions, and questions for counsel. Do not give legal advice.",
        ],
    },
    {
        "category": "Finance & Runway",
        "role": "Founder / CEO",
        "capability": "Files/Shell",
        "supply": "Bank and accounting exports, budget, payroll plan, revenue assumptions, and current cash balance",
        "why": "Gives founders a reviewable cash picture and explicit assumptions without rebuilding spreadsheets manually",
        "tasks": [
            "Build a monthly runway model from these exports with beginning cash, cash in, payroll, non-payroll burn, ending cash, net burn, gross burn, and runway date.",
            "Explain actual versus budget burn for the last three months. Rank material variances, identify one-time versus recurring effects, and list decisions needed this week.",
            "Analyze vendor spend for duplicates, price increases, unused subscriptions, renewal dates, owner, cancellation risk, and the fastest credible savings opportunities.",
            "Model whether we can afford these planned hires. Show base, delayed-hiring, and no-hiring scenarios with cash-out date, milestones reached, and assumptions.",
            "Create bear, base, and upside cash scenarios from these revenue and expense assumptions. Highlight the five inputs with the largest runway sensitivity.",
            "Calculate unit economics by customer segment, including gross margin, acquisition cost, payback period, retention assumption, and contribution margin. Flag missing or unreliable inputs.",
            "Reconcile the CRM pipeline with the revenue forecast. Apply explicit probability rules, separate new and expansion revenue, and flag unsupported timing or amount assumptions.",
            "Build a collections plan for overdue invoices with customer, amount, age, owner, dispute status, next action, and a professional follow-up draft.",
            "Create a one-page finance summary for the board with cash, burn, runway, revenue, margin, budget variance, forecast change, risks, and decisions requested.",
            "Draft a lightweight cash-control checklist for a seed-stage company covering approvals, payment access, vendor changes, reimbursements, cards, payroll, reconciliation, and exception review.",
        ],
    },
    {
        "category": "Hiring & Team",
        "role": "Founder / CEO",
        "capability": "Multi-file artifacts",
        "supply": "Hiring plan, role context, candidate materials, interview notes, and company operating principles",
        "why": "Standardizes high-stakes people decisions while preserving the evidence behind each recommendation",
        "tasks": [
            "Create a role scorecard for our first product engineer with mission, outcomes at 30/90/180 days, competencies, interview evidence, and explicit non-requirements.",
            "Rewrite this job description for an early-stage hire. Make the actual problems, ownership, constraints, learning, compensation context, and selection process concrete.",
            "Prepare a candidate interview packet with resume evidence, role-specific questions, assigned competencies, follow-up probes, and prohibited or redundant questions.",
            "Synthesize these interviewer notes without averaging away disagreement. Score each competency, cite evidence, flag missing signals, and recommend advance, hold, or decline.",
            "Create a reference-check guide tailored to this candidate and role. Include relationship verification, specific claims to test, performance examples, weaknesses, and rehire question.",
            "Compare these offer scenarios across cash, equity, vesting, start date, level, runway impact, and internal consistency. Flag inputs that need legal or tax review.",
            "Build a 30/60/90-day onboarding plan for this first functional leader with context, relationships, systems, deliverables, decision rights, and founder check-ins.",
            "Propose an org design for the next 12 hires. Map company milestones to roles, sequencing, managers, spans, dependencies, and roles that should remain founder-owned.",
            "Turn these company principles into observable performance expectations for managers and individual contributors, with examples of strong and weak behavior.",
            "Assess whether to convert these contractors into employees. Compare scope, continuity, management need, cost, classification risk, knowledge concentration, and transition steps.",
        ],
    },
    {
        "category": "Investor & Board Updates",
        "role": "Founder / CEO",
        "capability": "Multi-file artifacts",
        "supply": "Prior updates, KPI exports, board materials, decisions, risks, and current company context",
        "why": "Keeps investor communication consistent, concise, and grounded in the same operating data",
        "tasks": [
            "Draft this month's investor update with highlights, lowlights, KPI changes, product, go-to-market, team, cash, asks, and a candid founder note.",
            "Create a board deck outline from these operating reviews. Put decisions before detail and include metrics, variances, strategic questions, risks, and requested approvals.",
            "Write KPI variance commentary for every metric that moved more than 10 percent. Separate measurement changes, seasonality, execution causes, and unknowns.",
            "Prepare answers to the 20 hardest board questions implied by these materials. Cite source data and mark any answer that cannot yet be supported.",
            "Build a board action log from these meeting notes with decision, owner, due date, status, dependency, and the exact follow-up needed before the next meeting.",
            "Turn weekly operating notes into a quarterly company narrative explaining what changed, why it changed, what we learned, and which bets come next.",
            "Draft a concise bad-news investor note about this missed milestone. State facts, impact, root cause, corrective action, leading indicators, and the specific help requested.",
            "Match our current hiring, customer, partnership, and fundraising asks to the most relevant investors based on their supplied backgrounds and networks.",
            "Prepare a board-consent agenda from these proposed actions. Separate discussion, approval, and information items and flag anything requiring counsel confirmation.",
            "Create an annual investor retrospective comparing original plan, actual outcomes, key decisions, capital efficiency, lessons, and the next year's explicit priorities.",
        ],
    },
    {
        "category": "Operations & Compliance",
        "role": "Founder Operations",
        "capability": "Multi-file artifacts",
        "supply": "Policies, contracts, vendor files, system inventories, deadlines, and owner information",
        "why": "Creates accountable operating controls and review queues without pretending to replace professional advice",
        "tasks": [
            "Build a company compliance calendar from these incorporation, tax, payroll, insurance, and reporting documents. Include jurisdiction, deadline, owner, dependency, and source.",
            "Draft responses to this customer security questionnaire using only supplied policies and architecture evidence. Mark unsupported answers and required security-owner review.",
            "Create a vendor due-diligence register with service, data accessed, business owner, contract term, security evidence, subprocessors, renewal, risk, and follow-up.",
            "Assess our SOC 2 readiness evidence against this control list. Map artifacts, owners, test frequency, gaps, remediation priority, and claims we must not make yet.",
            "Extract business issues from these customer contract redlines: economics, liability, data, security, support, termination, IP, and operational commitments. Route legal questions to counsel.",
            "Build a privacy data map from these system descriptions. Trace collection, purpose, storage, processors, access, retention, deletion, and unresolved ownership.",
            "Prepare an insurance renewal packet with current policies, limits, exclusions, claims, customer requirements, headcount, revenue, changes, and broker questions.",
            "Create an authorized, defensive 60-minute business-continuity tabletop for a seed-stage SaaS company responding to a service incident. Include scenario injects, roles, a decision log, stakeholder communications, recovery checks, and a debrief rubric. This is planning and documentation only; do not perform or describe offensive security actions.",
            "Run an access-review analysis from these identity exports. Flag former workers, dormant accounts, excessive roles, shared credentials, missing owners, and recommended revocations.",
            "Create a lightweight procurement workflow with intake fields, spend thresholds, security and legal routing, approval owners, renewal tracking, and an emergency exception path.",
        ],
    },
    {
        "category": "Pricing & Competitive Intelligence",
        "role": "Founder / CEO",
        "capability": "Browser pane",
        "supply": "Pricing pages, sales notes, usage data, customer research, and approved competitive sources",
        "why": "Connects pricing and positioning decisions to customer evidence, economics, and current market facts",
        "tasks": [
            "Build a competitor matrix from the supplied sources covering target user, core job, workflow, pricing, proof, integrations, constraints, and our defensible difference.",
            "Compare the current and archived pricing pages for these competitors. Report exact packaging, price, limit, and positioning changes with source date and URL.",
            "Propose three packaging options for our product using customer value, usage, support cost, gross margin, and sales motion. State tradeoffs and testable assumptions.",
            "Synthesize willingness-to-pay evidence from these interviews and sales calls. Separate stated budgets, anchors, procurement thresholds, objections, and observed purchase behavior.",
            "Analyze discounting across closed deals by segment, seller, contract term, stage, competitor, and outcome. Recommend approval rules and exceptions to investigate.",
            "Design enterprise add-ons for this product. Tie each add-on to a distinct buyer need, delivery cost, proof requirement, packaging boundary, and price test.",
            "Recommend usage thresholds for free, starter, team, and enterprise plans using this distribution. Show affected accounts, expansion opportunity, abuse risk, and migration concerns.",
            "Draft a pricing FAQ for sales and support covering value metric, limits, overages, trials, discounts, migration, cancellation, taxes, and claims that need confirmation.",
            "Run a competitor-specific win-loss analysis from these opportunities. Separate product gaps, positioning, trust, price, timing, relationship, and execution errors.",
            "Create a quarterly market brief from the supplied competitor updates, customer evidence, and category news. Identify signal, noise, implications, and three founder decisions.",
        ],
    },
]


def build_catalog() -> dict:
    rows = []
    for group in GROUPS:
        for task in group["tasks"]:
            task_id = START_ID + len(rows)
            rows.append(
                {
                    "ID": task_id,
                    "Wave": WAVE,
                    "Status": STATUS,
                    "Category": group["category"],
                    "Task (what the person types)": task,
                    "Role": group["role"],
                    "Capability needed": CAPABILITY_OVERRIDES.get(task_id, group["capability"]),
                    "They must supply": group["supply"],
                    "Why it saves time": group["why"],
                    "Evidence / gap": EVIDENCE,
                }
            )

    ids = [row["ID"] for row in rows]
    tasks = [row["Task (what the person types)"] for row in rows]
    category_counts = {
        group["category"]: sum(row["Category"] == group["category"] for row in rows)
        for group in GROUPS
    }
    if len(rows) != EXPECTED_TASK_COUNT:
        raise SystemExit(f"expected {EXPECTED_TASK_COUNT} tasks, found {len(rows)}")
    if ids != list(range(START_ID, START_ID + EXPECTED_TASK_COUNT)):
        raise SystemExit("founder task IDs must be contiguous from 211 through 310")
    if len(tasks) != len(set(tasks)):
        raise SystemExit("founder task prompts must be unique")
    if len(category_counts) != 10 or set(category_counts.values()) != {10}:
        raise SystemExit(f"expected ten balanced categories, found {category_counts}")

    return {
        "version": 1,
        "catalogSpreadsheetURL": SPREADSHEET_URL,
        "reviewDate": REVIEW_DATE,
        "startID": START_ID,
        "endID": START_ID + EXPECTED_TASK_COUNT - 1,
        "rowCount": EXPECTED_TASK_COUNT,
        "categoryCounts": category_counts,
        "rows": rows,
    }


def encoded_catalog() -> str:
    return json.dumps(build_catalog(), indent=2, ensure_ascii=True) + "\n"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    rendered = encoded_catalog()
    if arguments.check:
        if not arguments.output.exists() or arguments.output.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"{arguments.output} is stale; rerun without --check")
        print("Founder task catalog valid: 100 tasks, IDs 211-310, 10 balanced categories")
        return
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(rendered, encoding="utf-8")
    print(f"Wrote {arguments.output}: 100 tasks, IDs 211-310")


if __name__ == "__main__":
    main()
