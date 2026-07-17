import XCTest
import QuillCodeCore

/// Native ↔ HTML ↔ harness parity gate for the morning-triage inbox (issue #877).
///
/// This batch has repeatedly shipped bugs where the HTML harness diverged from the native Swift model
/// and the Playwright E2E passed while native was broken. This gate defends against that by asserting
/// that all three surfaces agree on the load-bearing constants and semantics:
/// - the verdict raw values and severity ordering,
/// - the Attention section / row / digest testids and data attributes,
/// - the j/k/Enter/a/d triage command IDs.
///
/// It reads the actual sources (the Swift core, the Swift HTML renderer, and the committed harness
/// index.html) so a change to one surface that isn't mirrored in the others fails here — the same
/// mechanism #878's parity gates used.
final class ParityAttentionInboxGateTests: QuillCodeParityTestCase {

    private func harnessText() throws -> String {
        try String(
            contentsOf: Self.packageRoot().appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
    }

    // MARK: - Verdict + severity agreement

    func testVerdictRawValuesAndSeverityAgreeAcrossSurfaces() throws {
        // The Swift source of truth.
        XCTAssertEqual(TriageVerdict.red.rawValue, "red")
        XCTAssertEqual(TriageVerdict.unverified.rawValue, "unverified")
        XCTAssertEqual(TriageVerdict.verified.rawValue, "verified")
        XCTAssertGreaterThan(TriageVerdict.red.severity, TriageVerdict.unverified.severity)
        XCTAssertGreaterThan(TriageVerdict.unverified.severity, TriageVerdict.verified.severity)
        XCTAssertFalse(TriageVerdict.verified.needsAttention)

        // The harness must mirror the same severity map + badge labels + attention predicate.
        let harness = try harnessText()
        Self.assertSource(harness, containsAll: [
            "const triageSeverity = { red: 2, unverified: 1, verified: 0 };",
            "const triageBadgeLabel = { red: 'RED', unverified: 'UNVERIFIED', verified: 'VERIFIED' };",
            "function verdictNeedsAttention(verdict) {",
            "verdict === 'red' || verdict === 'unverified'"
        ])
    }

    // MARK: - Ranking semantics agreement

    func testRankingIsSeverityThenRecencyThenIDInBothSurfaces() throws {
        // Native: RED before UNVERIFIED, newer before older on ties.
        let older = AttentionItem(threadID: uuid(1), title: "a", verdict: .red, summary: "", unseenCount: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let newer = AttentionItem(threadID: uuid(2), title: "b", verdict: .red, summary: "", unseenCount: 0, updatedAt: Date(timeIntervalSince1970: 200))
        let yellow = AttentionItem(threadID: uuid(3), title: "c", verdict: .unverified, summary: "", unseenCount: 0, updatedAt: Date(timeIntervalSince1970: 300))
        let ranked = AttentionModel.rank([yellow, older, newer])
        XCTAssertEqual(ranked.map(\.threadID), [uuid(2), uuid(1), uuid(3)])

        // Harness: the same three-key comparator (severity desc, updatedAt desc, threadID asc).
        let harness = try harnessText()
        Self.assertSource(harness, containsAll: [
            "triageSeverity[rhs.verdict] - triageSeverity[lhs.verdict]",
            "lhs.updatedAt < rhs.updatedAt ? 1 : -1",
            "lhs.threadID < rhs.threadID ? -1 : (lhs.threadID > rhs.threadID ? 1 : 0)"
        ])
    }

    // MARK: - Testids + data attributes agreement

    func testAttentionTestidsMatchBetweenHTMLRendererAndHarness() throws {
        let renderer = try Self.appSourceText(named: "WorkspaceHTMLSidebarThreadRenderer.swift")
        let workspaceRenderer = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let harness = try harnessText()

        let sectionTestids = [
            #"data-testid="attention-section""#,
            #"data-testid="attention-row""#,
            #"data-testid="attention-verdict""#,
            #"data-testid="attention-title""#,
            #"data-testid="attention-unseen""#
        ]
        for testid in sectionTestids {
            Self.assertSource(renderer, contains: testid)
            Self.assertSource(harness, contains: testid)
        }

        // Raw-HTML digest elements: identical `data-testid="…"` literals in both surfaces.
        let digestRawTestids = [
            "attention-digest",
            "attention-digest-verdict",
            "attention-digest-title",
            "attention-digest-seam",
            "attention-digest-outcome",
            "attention-digest-reasons"
        ]
        for testid in digestRawTestids {
            Self.assertSource(workspaceRenderer, contains: #"data-testid="\#(testid)""#)
            Self.assertSource(harness, contains: #"data-testid="\#(testid)""#)
        }

        // Digest action buttons route through the shared HTML button primitive in Swift (so they carry
        // hit-target markers), hence `testID: "…"`; the harness emits the same `data-testid`.
        let digestButtonTestids = [
            "attention-digest-close",
            "attention-digest-acknowledge",
            "attention-digest-dismiss"
        ]
        for testid in digestButtonTestids {
            Self.assertSource(workspaceRenderer, contains: #"testID: "\#(testid)""#)
            Self.assertSource(harness, contains: #"data-testid="\#(testid)""#)
        }
    }

    // MARK: - Triage command IDs agreement

    func testTriageCommandIDsMatchAcrossSurfaces() throws {
        let commandPlan = try Self.appSourceText(named: "WorkspaceCommandPlan.swift")
        let harness = try harnessText()

        let commands = [
            "attention-next",
            "attention-previous",
            "attention-open",
            "attention-acknowledge",
            "attention-dismiss"
        ]
        for command in commands {
            // Native raw-value enum case.
            Self.assertSource(commandPlan, contains: "= \"\(command)\"")
            // Harness runCommand branch + routable allowlist.
            Self.assertSource(harness, contains: "'\(command)'")
        }
        // The Enter/j/k/a/d key routing table in the harness must map to these commands.
        Self.assertSource(harness, containsAll: [
            "j: 'attention-next'",
            "k: 'attention-previous'",
            "a: 'attention-acknowledge'",
            "d: 'attention-dismiss'",
            "enter: 'attention-open'"
        ])
    }

    // MARK: - Triage-key focus guard (BLOCKER-3 divergence defense)

    func testHarnessTriageKeysDoNotFireInEditableFieldsAndAreSectionScoped() throws {
        let harness = try harnessText()
        // The triage guard must be its OWN function, NOT a reuse of focusAllowsTabShortcut (which treats
        // the composer as shortcut-allowed — the exact bug). It must block INPUT / TEXTAREA / SELECT /
        // contentEditable, require the section to have rows, and (MINOR parity) be scoped to the
        // Attention section's context rather than firing for ANY non-editable focus.
        Self.assertSource(harness, containsAll: [
            "function attentionTriageContextIsActive()",
            "if (!attentionTriageContextIsActive()) return false;",
            "active.isContentEditable",
            "tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT'",
            "if (!attentionRows().length) return false;",
            #"document.querySelector('[data-testid="sidebar"]')"#,
            "sidebar.contains(active)"
        ])
        // Fail-on-revert: the triage keydown handler must NOT gate on focusAllowsTabShortcut (the buggy
        // guard that let the keys fire in the composer).
        let triageHandler = try slice(
            of: harness,
            from: "function handleAttentionTriageKeydown(event) {",
            to: "\n    }"
        )
        Self.assertSource(triageHandler, excludes: "focusAllowsTabShortcut")
    }

    // MARK: - Cursor is preview-only (the "cursoring zeroes badges" MAJOR defense)

    func testCursorMovementIsDecoupledFromSelectionInBothSurfaces() throws {
        // Native: attentionMoveDown/Up route through setAttentionCursor, which sets the dedicated
        // attentionCursorID field — NOT selectThread (which would advance the outgoing watermark).
        let modelSource = try Self.appSourceText(named: "WorkspaceModelMorningTriage.swift")
        Self.assertSource(modelSource, contains: "private func setAttentionCursor(_ threadID: UUID?) {")
        let setCursorBody = try slice(
            of: modelSource,
            from: "private func setAttentionCursor(_ threadID: UUID?) {",
            to: "\n    }"
        )
        Self.assertSource(setCursorBody, contains: "attentionCursorID = threadID")
        Self.assertSource(setCursorBody, excludes: "selectThread(")

        // The surface builds the Attention cursor from attentionCursorID, not the workspace selection
        // (and only from durable threads — ephemeral confidential/side chats never surface in Attention).
        let builder = try Self.appSourceText(named: "WorkspaceNavigationSurfaceBuilder.swift")
        Self.assertSource(builder, contains: "AttentionModel.build(from: durableThreads, selectedThreadID: attentionCursorID)")

        // Harness: cursor movement sets state.attentionCursorID and does NOT selectThread.
        let harness = try harnessText()
        let selectRelative = try slice(
            of: harness,
            from: "function attentionSelectRelative(delta) {",
            to: "\n    }"
        )
        Self.assertSource(selectRelative, contains: "state.attentionCursorID = rows[clamped].threadID;")
        // Must not CALL selectThread (a comment may mention it; a call has a paren).
        Self.assertSource(selectRelative, excludes: "selectThread(")
        // And the harness derives unseen from a watermark (so Playwright can catch a badge-zeroing bug),
        // advancing it only on a genuine leave.
        Self.assertSource(harness, containsAll: [
            "function attentionUnseenCount(item)",
            "function attentionMarkThreadSeen(threadID)",
            "if (outgoing) attentionMarkThreadSeen(outgoing);"
        ])
    }

    /// Extract the substring from the first occurrence of `from` up to the next occurrence of `to`.
    private func slice(of source: String, from: String, to: String) throws -> String {
        guard let start = source.range(of: from) else {
            XCTFail("expected harness to contain: \(from)")
            return ""
        }
        guard let end = source.range(of: to, range: start.upperBound..<source.endIndex) else {
            XCTFail("expected \(to) after \(from)")
            return ""
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    // MARK: - Triage state agreement

    func testTriageStatesMatchAcrossSurfaces() throws {
        XCTAssertEqual(ThreadTriageState.pending.rawValue, "pending")
        XCTAssertEqual(ThreadTriageState.acknowledged.rawValue, "acknowledged")
        XCTAssertEqual(ThreadTriageState.dismissed.rawValue, "dismissed")
        let harness = try harnessText()
        Self.assertSource(harness, containsAll: ["'pending'", "'acknowledged'", "'dismissed'"])
    }

    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", n))")!
    }
}
