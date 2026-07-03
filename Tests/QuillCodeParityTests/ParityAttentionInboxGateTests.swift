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
