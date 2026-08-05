# Cline tool-excellence analysis → QuillCode plan

Analyzed 2026-08-04 from a shallow clone of github.com/cline/cline (post-SDK restructure:
`apps/vscode` extension + `sdk/packages/{core,shared,agents}`). Findings verified by reading the
actual sources; file references below are to that tree.

## Why Cline is "great at tools" — the real mechanics

Cline's reputation does not come from exotic tools — its tool *set* is ordinary (read/write/
replace_in_file/execute_command/browser/MCP). It comes from **feedback engineering**: what the
model is told when a tool call goes wrong, and how that message changes as failures accumulate.

### 1. Progressive, failure-count-aware error feedback (the standout)
`apps/vscode/src/core/prompts/responses.ts` — `writeToFileMissingContentError(relPath,
consecutiveFailures, contextUsagePercent)`:
- **1st failure**: diagnosis + gentle suggestions (skeleton first; prefer replace_in_file).
- **2nd failure**: "You must use a different strategy" + three enumerated alternatives.
- **3rd+**: "CRITICAL: You have failed N times. Do NOT retry write_to_file for this file again.
  Required action — choose ONE:" with concrete numbered strategies and size bounds
  ("no more than 50-100 lines per replace_in_file call").
- Blends in **context-window awareness**: past 50% usage it warns that output budget may be the
  cause and mandates smaller-output strategies.

The correction *teaches an alternative*, never just restates the rule. Every error message names
the exact tool and parameter syntax to use next (`replaceInFileMissingDiffError` embeds a full
SEARCH/REPLACE example; `executeCommandMissingCommandError` embeds a full XML example).

### 2. Graded loop detection: soft warn, then hard stop
`sdk/packages/core/src/runtime/safety/loop-detection.ts` — identical-call detection over a
canonical **key-sorted JSON signature**, with two thresholds (default soft=3, hard=5). At soft
the model gets "consider trying a different approach" and keeps going; at hard the run stops
with a clear reason. Escalation is graduated, not binary.

### 3. Session-level consecutive-mistake budget across categories
`sdk/packages/core/src/runtime/safety/mistake-tracker.ts` — one counter spanning
`api_error | invalid_tool_call | tool_execution_failed`; any successful step resets it. At the
limit, a host callback can inject recovery guidance (and reset) or stop with a message that
explicitly says **state was preserved and how to resume**. Per-step budgets alone can't see a
run that alternates failure *kinds*.

### 4. Context hygiene around tools
- `duplicateFileReadNotice`: a repeated file read is *replaced in history* with a one-line
  pointer to the latest read — precise dedup, cheaper than generic compaction.
- `contextTruncationNotice` tells the model exactly what was dropped and what was kept.
- `noToolsUsed()`: an automated, non-conversational retry message when a response contains no
  tool call, with explicit next-step menu (attempt_completion / ask_followup_question / next
  tool). Cline counts it as a mistake toward the budget.

### 5. Honest denial/interruption semantics
- Tool denied → the canonical string "The user denied this operation." — never euphemised.
- `.clineignore` block → names the blocking mechanism and the two honest ways forward.
- Interrupted tools are recorded in-history as "[tool] was interrupted and not executed" so the
  model never believes a cancelled call ran.

### 6. Conversation-boundary markers
`sdk/packages/shared/src/prompt/format.ts` — mode switches (plan↔act) are marked *in the
message stream* (`<mode_notice>`) at the exact boundary, with round-trip cancellation so a
plan→act→plan toggle before sending never emits a stale notice.

## What QuillCode already has (no action)
- Tolerant fuzzy apply_patch (≈ Cline's multi-tier SEARCH/REPLACE matcher).
- Flail detection on workspace deltas; repeated-call finalization; turn deadline (F20);
  promised-work/deferral/readiness guards (#1538/#1540); deliverable gate (F23/F25); citation
  gate (F29); model fallback (F22); async approval; auto-approval policy floors.
- Mode-aware prompt guidance (read-only/review) — static per-mode, see gap 5.

## Gaps → prioritized plan

1. **Escalating corrective prompts** (Cline #1) — HIGH, low risk. QuillCode's corrective
   re-prompts (malformed action, promised work, deliverable gate, citation gate) send the SAME
   text on every attempt. Add attempt-indexed escalation: final budgeted attempt switches to a
   directive form — "this is your Nth failed attempt; do NOT repeat the same response; choose
   ONE of: …" with gate-specific concrete alternatives (the escape hatch made explicit).
   → **Implemented in this PR** (`AgentCorrectionEscalation`).
2. **Soft-warning tier before repeated-call finalization** (Cline #2) — MEDIUM-HIGH. Today the
   second identical call finalizes immediately; a transient-failure retry is legitimate. Inject
   one "you already ran exactly this; try a different approach or finish" notice first,
   finalize on the next repeat. (Next PR.)
3. **Cross-category consecutive-mistake budget** (Cline #3) — MEDIUM. Aggregate malformed +
   denied + failed-tool streaks into one per-run counter with a preserved-state stop message.
   maxToolSteps bounds runaway today, but spends the whole step budget doing it. (Next PR.)
4. **Duplicate-file-read dedup** (Cline #4) — MEDIUM. On re-read of an unchanged file, replace
   the older read's content in the thread with a pointer notice. Pairs with existing compaction.
5. **Mode-switch notices** (Cline #6) — LOW-MED. Emit a one-line boundary notice into the next
   user message after a plan/read-only/review mode change, with round-trip cancellation.
6. **Context-usage-aware error guidance** (Cline #1's second axis) — LOW-MED. Thread current
   context-usage % into write-failure corrections ("output budget likely insufficient — write a
   skeleton, then extend in sections").

---

## Appendix: F21 (merge/extraction data-loss gate) — attempted twice, NOT shipped

The live failure is real: a twelve-month merge silently dropped months 5–12 (reported total
84,206.52 against a true 120,805.90), and a re-drive produced the right rows with a completely
empty amount column. The prompt rule shipped in #1543 reduced but did not close it. Two mechanical
gate designs were built, adversarially reviewed, and **both were rejected on their premise**.

**Draft 1 — "an empty column in an extraction output is lost data."** Review (18 agents, 3 lenses;
8/9 findings verified by compiling and executing the real source) killed it:
- The premise is false for ordinary output. No vendor gave a discount → the `discount` column is
  correctly empty; no source lists middle names → `middle` is correctly empty. Both were flagged.
- The escalated correction then told the model to *delete a column the user had asked for*.
- A path bug (absolute artifact path collapsed to a basename) made a subdirectory deliverable
  resolve to a same-named file at the workspace root — auditing, and offering to **overwrite**, a
  user's source file the run never wrote.

**Draft 2 — "an empty column whose header words appear in what the run READ is lost data."**
Provenance narrowing, harvesting a bounded vocabulary from read/shell/fetch output. Review round 2
(19 agents) killed it too:
- **Self-confirmation.** The system prompt *mandates* reading a written artifact back
  ("read the artifact back … to confirm it exists"). That read injects the deliverable's own header
  words into the vocabulary, so provenance collapses back to "any empty column" — the exact premise
  round 1 rejected. Reproduced end-to-end through the real `AgentRunner`.
- `host.file.search` echoes the model's own query into stdout, so grepping for a field name makes
  that field "source-backed" even with zero matches.
- Harness JSON envelope keys (`name`, `path`, `kind`, `query`, `matches`, `preview`) enter the
  vocabulary as if they were source text.
- For generic single-word headers (`date`, `total`, `notes`, `amount`) the requirement is close to
  vacuous anyway — and the correction then asserts a falsehood ("those field names DO appear in the
  source material"), pressuring the model to **fabricate values**. In a data-integrity gate that is
  the worst possible failure mode: it manufactures exactly the wrong numbers the program exists to
  prevent.

**Decision: do not ship.** Numeric reconciliation needs task semantics the runner does not have
(is an output row a source row, an aggregate, or a filtered subset?), and every cheap proxy tried
here fails worse than the defect. The prompt rule (#1543) stands; verification of merges stays with
the human or an explicit per-task check.

**Transferable lesson (already applied, see F32 below):** any invariant derived from the run's own
tool output can be poisoned by the run's own writing, because the product's prompt requires the
model to read its artifacts back. A gate's evidence must come from somewhere the model cannot
author.

---

## Appendix 2: two more Cline learnings, rejected on evidence (2026-08-05)

Before building either, the coworker corpus (120 most recent persisted runs in `~/.quillcode/threads`)
was measured. Both premises turned out to be false **for this codebase**, so neither shipped.

### Cross-category consecutive-mistake budget — REJECTED
Cline's `MistakeTracker` aggregates `api_error | invalid_tool_call | tool_execution_failed` into one
per-session counter, because a run alternating failure *kinds* never trips any single per-kind
budget. QuillCode has no such counter (only `promisedWorkCorrectionLimit` = 2,
`malformedActionCorrectionLimit` = 2, and `maxToolSteps`).

Measured: 11 of 120 runs mixed multiple failure categories, with exactly the predicted alternating
shape — `MEMMMM`, `EMMME`, `EEEMM` (M = malformed, E = empty response, D = denied).

But **every one of those runs succeeded**: a real final answer, the deliverable verified on disk, no
step ceiling, no flail stop. The existing per-category self-healing (F13 empty-response retry, F22
model fallback, F31 malformed-sample tolerance) already absorbs the churn. A Cline-style budget of
~3 consecutive mistakes would have **killed** runs that currently work — e.g. `MEMMMM` (23 tool
steps → a complete speaker brief) and `EEEEE` (23 steps → same). The mechanism's only effect here
would be premature stops on healthy runs.

### Duplicate-file-read dedup — REJECTED
Cline replaces a repeated file read in history with a one-line pointer to save context.

Measured: only **2 of 120 runs** (1%) re-read the same path at all, and both were a second read-back
of the run's *own* output (`contacts_clean.csv`, `speaker-brief.md`) — the artifact confirmation the
system prompt mandates. There is no context bloat to reclaim.

### Still unevaluated
Mode-switch notices and context-usage-aware write-failure guidance are interactive/desktop concerns;
the headless corpus contains no mode switches and no size-driven write failures, so there is no
evidence either way. They need interactive telemetry before they are worth building.

**Method note:** measuring first cost one thread scan. The F21 gate cost two full build-and-review
rounds to reach the same kind of "premise is false" verdict. Measure the corpus before building.
