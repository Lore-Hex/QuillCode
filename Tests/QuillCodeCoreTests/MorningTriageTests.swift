import XCTest
@testable import QuillCodeCore

/// Tests for the pure morning-triage core (issue #877): the verdict-stamp derivation from the persisted
/// Run Integrity record, the Attention ranking + selection cursor, and the persisted triage-state record.
/// Reviewers attack this with compiled repros, so the deterministic edges are asserted explicitly:
/// severity order, ties, empty section, j/k clamping, a/d no-op-on-empty, persistence round-trip, and
/// "no run → no stamp".
final class MorningTriageTests: XCTestCase {

    // MARK: - Fixtures

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", n))")!
    }

    /// A thread carrying a persisted RunIntegrity record with the given verdict (the ACTUAL persisted
    /// record, written the same way the app writes it).
    private func threadWithVerdict(
        _ verdict: RunIntegrityVerdict?,
        id threadID: UUID,
        title: String = "overnight run",
        updatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> ChatThread {
        var thread = ChatThread(id: threadID, title: title, updatedAt: updatedAt)
        if let verdict {
            let report = RunIntegrityReport(
                verdict: verdict,
                reasons: [RunIntegrityReason(rule: .standingTestFailure, detail: "make test exited 1")]
            )
            if let event = RunIntegrityRecord.event(for: report) {
                thread.events.append(event)
            }
        }
        return thread
    }

    private func attention(
        _ verdict: TriageVerdict,
        id threadID: UUID,
        updatedAt: TimeInterval = 1_000,
        unseen: Int = 0
    ) -> AttentionItem {
        AttentionItem(
            threadID: threadID,
            title: "t\(threadID.uuidString.suffix(2))",
            verdict: verdict,
            summary: "s",
            unseenCount: unseen,
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }

    // MARK: - Verdict stamp from the persisted record

    func testStampReadsPersistedRunIntegrityRecord() {
        let thread = threadWithVerdict(.red, id: id(1))
        let stamp = TriageStamp.derive(from: thread)
        XCTAssertEqual(stamp?.verdict, .red)
        XCTAssertEqual(stamp?.summary, "make test exited 1")
    }

    func testNoRunMeansNoStamp() {
        let thread = threadWithVerdict(nil, id: id(2))
        XCTAssertNil(TriageStamp.derive(from: thread))
    }

    func testStampMapsEachVerdict() {
        XCTAssertEqual(TriageStamp.derive(from: threadWithVerdict(.red, id: id(1)))?.verdict, .red)
        XCTAssertEqual(TriageStamp.derive(from: threadWithVerdict(.unverified, id: id(1)))?.verdict, .unverified)
        XCTAssertEqual(TriageStamp.derive(from: threadWithVerdict(.verified, id: id(1)))?.verdict, .verified)
    }

    func testVerdictSeverityAndNeedsAttention() {
        XCTAssertGreaterThan(TriageVerdict.red.severity, TriageVerdict.unverified.severity)
        XCTAssertGreaterThan(TriageVerdict.unverified.severity, TriageVerdict.verified.severity)
        XCTAssertTrue(TriageVerdict.red.needsAttention)
        XCTAssertTrue(TriageVerdict.unverified.needsAttention)
        XCTAssertFalse(TriageVerdict.verified.needsAttention)
    }

    // MARK: - Ranking

    func testRankingPutsRedBeforeUnverified() {
        let model = AttentionModel(items: [
            attention(.unverified, id: id(1)),
            attention(.red, id: id(2))
        ])
        XCTAssertEqual(model.items.map(\.verdict), [.red, .unverified])
    }

    func testRankingBreaksTiesByRecencyNewerFirst() {
        let older = attention(.red, id: id(1), updatedAt: 100)
        let newer = attention(.red, id: id(2), updatedAt: 200)
        let model = AttentionModel(items: [older, newer])
        XCTAssertEqual(model.items.map(\.threadID), [id(2), id(1)])
    }

    func testRankingIsTotalAndStableOnFullTies() {
        // Same severity + same timestamp → deterministic by threadID ascending.
        let a = attention(.unverified, id: id(3), updatedAt: 100)
        let b = attention(.unverified, id: id(1), updatedAt: 100)
        let model = AttentionModel(items: [a, b])
        XCTAssertEqual(model.items.map(\.threadID), [id(1), id(3)])
    }

    func testEmptyModelHasNoSelection() {
        let model = AttentionModel(items: [])
        XCTAssertTrue(model.isEmpty)
        XCTAssertNil(model.selectedThreadID)
        XCTAssertNil(model.selectedItem)
        XCTAssertNil(model.selectedIndex)
    }

    // MARK: - Selection cursor (j/k clamp)

    func testInitialSelectionIsFirstRow() {
        let model = AttentionModel(items: [
            attention(.unverified, id: id(1)),
            attention(.red, id: id(2))
        ])
        // Ranked: red(2) first.
        XCTAssertEqual(model.selectedThreadID, id(2))
    }

    func testMoveDownAdvancesAndClampsAtEnd() {
        var model = AttentionModel(items: [
            attention(.red, id: id(1), updatedAt: 300),
            attention(.red, id: id(2), updatedAt: 200),
            attention(.red, id: id(3), updatedAt: 100)
        ])
        XCTAssertEqual(model.selectedThreadID, id(1))
        model.moveDown()
        XCTAssertEqual(model.selectedThreadID, id(2))
        model.moveDown()
        XCTAssertEqual(model.selectedThreadID, id(3))
        // Clamps at the last row — no wrap, no out-of-range.
        model.moveDown()
        XCTAssertEqual(model.selectedThreadID, id(3))
    }

    func testMoveUpRetreatsAndClampsAtStart() {
        var model = AttentionModel(items: [
            attention(.red, id: id(1), updatedAt: 300),
            attention(.red, id: id(2), updatedAt: 200)
        ])
        model.moveDown()
        XCTAssertEqual(model.selectedThreadID, id(2))
        model.moveUp()
        XCTAssertEqual(model.selectedThreadID, id(1))
        // Clamps at the first row.
        model.moveUp()
        XCTAssertEqual(model.selectedThreadID, id(1))
    }

    func testMoveOnEmptyIsNoOp() {
        var model = AttentionModel(items: [])
        model.moveDown()
        model.moveUp()
        XCTAssertNil(model.selectedThreadID)
    }

    func testSelectPreservedAcrossRerankWhenStillPresent() {
        let items = [
            attention(.red, id: id(1), updatedAt: 300),
            attention(.red, id: id(2), updatedAt: 200)
        ]
        let model = AttentionModel(items: items, selectedThreadID: id(2))
        XCTAssertEqual(model.selectedThreadID, id(2))
    }

    func testSelectionFallsBackToFirstWhenSelectedGone() {
        let model = AttentionModel(items: [attention(.red, id: id(1))], selectedThreadID: id(99))
        XCTAssertEqual(model.selectedThreadID, id(1))
    }

    func testSelectByIDIgnoresUnknown() {
        var model = AttentionModel(items: [attention(.red, id: id(1)), attention(.red, id: id(2), updatedAt: 50)])
        model.select(id(99))
        XCTAssertEqual(model.selectedThreadID, id(1))
        model.select(id(2))
        XCTAssertEqual(model.selectedThreadID, id(2))
    }

    // MARK: - Triage state record (persistence)

    func testTriageStateDefaultsToPending() {
        let thread = threadWithVerdict(.red, id: id(1))
        XCTAssertEqual(ThreadTriageRecord.current(in: thread), .pending)
    }

    func testSetTriageStatePersistsAndReadsBack() {
        var thread = threadWithVerdict(.red, id: id(1))
        XCTAssertTrue(ThreadTriageRecord.set(.acknowledged, on: &thread))
        XCTAssertEqual(ThreadTriageRecord.current(in: thread), .acknowledged)
        XCTAssertFalse(ThreadTriageRecord.current(in: thread).isActionable)
    }

    func testSetTriageStateSurvivesReloadRoundTrip() throws {
        var thread = threadWithVerdict(.unverified, id: id(1))
        ThreadTriageRecord.set(.dismissed, on: &thread)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(thread)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(ChatThread.self, from: data)

        XCTAssertEqual(ThreadTriageRecord.current(in: reloaded), .dismissed)
        // And the run-integrity stamp still reads correctly alongside the triage record.
        XCTAssertEqual(TriageStamp.derive(from: reloaded)?.verdict, .unverified)
    }

    func testSetSameTriageStateIsIdempotentNoOp() {
        var thread = threadWithVerdict(.red, id: id(1))
        XCTAssertTrue(ThreadTriageRecord.set(.acknowledged, on: &thread))
        let before = thread.updatedAt
        XCTAssertFalse(ThreadTriageRecord.set(.acknowledged, on: &thread))
        XCTAssertEqual(thread.updatedAt, before, "re-recording the same state must not bump updatedAt")
    }

    func testChangingTriageStateReplacesPriorRecord() {
        var thread = threadWithVerdict(.red, id: id(1))
        ThreadTriageRecord.set(.acknowledged, on: &thread)
        ThreadTriageRecord.set(.dismissed, on: &thread)
        let records = thread.events.filter(ThreadTriageRecord.isRecord)
        XCTAssertEqual(records.count, 1, "only the latest triage record is kept")
        XCTAssertEqual(ThreadTriageRecord.current(in: thread), .dismissed)
    }

    func testTriageRecordDoesNotClobberIntegrityRecord() {
        var thread = threadWithVerdict(.red, id: id(1))
        ThreadTriageRecord.set(.acknowledged, on: &thread)
        // Both notices coexist on the thread.
        XCTAssertNotNil(RunIntegrityRecord.latest(in: thread))
        XCTAssertEqual(ThreadTriageRecord.current(in: thread), .acknowledged)
    }

    // MARK: - BLOCKER 1: a triaged thread that goes RED again re-surfaces

    /// Replace the thread's integrity record with a fresh one (a NEW run stamping the badge), exactly as
    /// `RunIntegrityRecord.record` does after a run finishes — a brand-new event id even for the same
    /// verdict.
    private func restampIntegrity(_ verdict: RunIntegrityVerdict, on thread: inout ChatThread) {
        let report = RunIntegrityReport(
            verdict: verdict,
            reasons: [RunIntegrityReason(rule: .standingTestFailure, detail: "make test exited 1")]
        )
        thread.events.removeAll(where: RunIntegrityRecord.isRecord)
        if let event = RunIntegrityRecord.event(for: report) {
            thread.events.append(event)
        }
    }

    func testAcknowledgedThreadThatGoesRedAgainReopensTriage() {
        var thread = threadWithVerdict(.red, id: id(1))
        // User acknowledges the current RED run — it leaves Attention.
        ThreadTriageRecord.set(.acknowledged, on: &thread)
        XCTAssertFalse(ThreadTriageRecord.needsAttention(in: thread))
        XCTAssertTrue(AttentionModel.build(from: [thread]).isEmpty)

        // Later the user reopens the thread and sends again; that run fails → a NEW integrity record
        // re-stamps RED. The stale acknowledgement must NOT keep hiding it.
        restampIntegrity(.red, on: &thread)
        XCTAssertTrue(
            ThreadTriageRecord.needsAttention(in: thread),
            "a thread that goes RED again after being acked must re-surface"
        )
        let model = AttentionModel.build(from: [thread])
        XCTAssertEqual(model.items.map(\.threadID), [id(1)])
    }

    func testDismissedThreadThatGetsNewVerdictReopensTriage() {
        var thread = threadWithVerdict(.unverified, id: id(1))
        ThreadTriageRecord.set(.dismissed, on: &thread)
        XCTAssertFalse(ThreadTriageRecord.needsAttention(in: thread))
        // A new run stamps a different verdict (also a fresh record id).
        restampIntegrity(.red, on: &thread)
        XCTAssertTrue(ThreadTriageRecord.needsAttention(in: thread))
        XCTAssertEqual(AttentionModel.build(from: [thread]).items.first?.verdict, .red)
    }

    func testAcknowledgementStillSilencesTheSameRun() {
        var thread = threadWithVerdict(.red, id: id(1))
        ThreadTriageRecord.set(.acknowledged, on: &thread)
        // No new run — the same integrity record stands. It must stay silenced.
        XCTAssertFalse(ThreadTriageRecord.needsAttention(in: thread))
        XCTAssertTrue(AttentionModel.build(from: [thread]).isEmpty)
    }

    func testReacknowledgingAfterReopenBindsToTheNewRun() {
        var thread = threadWithVerdict(.red, id: id(1))
        ThreadTriageRecord.set(.acknowledged, on: &thread)
        restampIntegrity(.red, on: &thread)
        XCTAssertTrue(ThreadTriageRecord.needsAttention(in: thread))
        // Acknowledge the NEW run — now it binds to the new record and silences again.
        XCTAssertTrue(ThreadTriageRecord.set(.acknowledged, on: &thread))
        XCTAssertFalse(ThreadTriageRecord.needsAttention(in: thread))
    }

    func testTriageBindingSurvivesReloadThenReopensOnNewRun() throws {
        var thread = threadWithVerdict(.red, id: id(1))
        ThreadTriageRecord.set(.acknowledged, on: &thread)

        // Reload: still silenced (same run).
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var reloaded = try decoder.decode(ChatThread.self, from: try encoder.encode(thread))
        XCTAssertFalse(ThreadTriageRecord.needsAttention(in: reloaded))

        // A new run after reload re-opens triage.
        restampIntegrity(.red, on: &reloaded)
        XCTAssertTrue(ThreadTriageRecord.needsAttention(in: reloaded))
    }

    func testAttentionUnseenNeverNegative() {
        let item = AttentionItem(
            threadID: id(1), title: "t", verdict: .red, summary: "s", unseenCount: -4,
            updatedAt: Date()
        )
        XCTAssertEqual(item.unseenCount, 0)
        XCTAssertNil(item.unseenLabel)
    }

    func testAttentionUnseenLabel() {
        let item = attention(.red, id: id(1), unseen: 3)
        XCTAssertEqual(item.unseenLabel, "3 new")
    }

    // MARK: - Return watermark (unseen count)

    private func threadWithMessages(_ count: Int, id threadID: UUID = UUID()) -> ChatThread {
        var thread = ChatThread(id: threadID)
        for i in 0..<count {
            thread.messages.append(ChatMessage(
                id: UUID(uuidString: "10000000-0000-0000-0000-0000000000\(String(format: "%02d", i))")!,
                role: i.isMultiple(of: 2) ? .user : .assistant,
                content: "turn \(i)"
            ))
        }
        return thread
    }

    func testUnseenCountZeroWhenNeverViewed() {
        let thread = threadWithMessages(3)
        XCTAssertEqual(ThreadReturnWatermarkRecord.unseenCount(in: thread), 0)
    }

    func testUnseenCountAfterMarkSeenThenGrowth() {
        var thread = threadWithMessages(3)
        XCTAssertTrue(ThreadReturnWatermarkRecord.markSeen(&thread))
        XCTAssertEqual(ThreadReturnWatermarkRecord.unseenCount(in: thread), 0)
        // Two more turns arrive.
        thread.messages.append(ChatMessage(role: .assistant, content: "new 1"))
        thread.messages.append(ChatMessage(role: .user, content: "new 2"))
        XCTAssertEqual(ThreadReturnWatermarkRecord.unseenCount(in: thread), 2)
    }

    func testUnseenCountStaleWatermarkIsZeroNeverNegative() throws {
        var thread = threadWithMessages(4)
        // Point the watermark at an item that isn't in the timeline.
        let payload = ThreadReturnWatermarkRecord.Payload(lastSeenItemID: "message-does-not-exist")
        let json = try JSONHelpers.encodePretty(payload)
        thread.events.append(ThreadEvent(
            kind: .notice,
            summary: ThreadReturnWatermarkRecord.eventSummary,
            payloadJSON: json
        ))
        XCTAssertEqual(ThreadReturnWatermarkRecord.unseenCount(in: thread), 0)
    }

    func testMarkSeenIsNoOpAtTailAndOnEmpty() {
        var thread = threadWithMessages(2)
        XCTAssertTrue(ThreadReturnWatermarkRecord.markSeen(&thread))
        XCTAssertFalse(ThreadReturnWatermarkRecord.markSeen(&thread), "already at tail")
        var empty = ChatThread()
        XCTAssertFalse(ThreadReturnWatermarkRecord.markSeen(&empty), "no messages")
    }

    func testWatermarkSurvivesReloadRoundTrip() throws {
        var thread = threadWithMessages(3)
        ThreadReturnWatermarkRecord.markSeen(&thread)
        thread.messages.append(ChatMessage(role: .assistant, content: "later"))

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(thread)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(ChatThread.self, from: data)
        XCTAssertEqual(ThreadReturnWatermarkRecord.unseenCount(in: reloaded), 1)
    }

    // MARK: - build(from:) integration

    func testBuildIncludesOnlyPendingAttentionThreads() {
        let redThread = threadWithVerdict(.red, id: id(1), updatedAt: Date(timeIntervalSince1970: 300))
        let unverifiedThread = threadWithVerdict(.unverified, id: id(2), updatedAt: Date(timeIntervalSince1970: 200))
        let verifiedThread = threadWithVerdict(.verified, id: id(3))
        let noRunThread = threadWithVerdict(nil, id: id(4))
        var acknowledgedRed = threadWithVerdict(.red, id: id(5))
        ThreadTriageRecord.set(.acknowledged, on: &acknowledgedRed)

        let model = AttentionModel.build(from: [
            verifiedThread, unverifiedThread, redThread, noRunThread, acknowledgedRed
        ])
        // Only the pending RED + UNVERIFIED threads, RED first.
        XCTAssertEqual(model.items.map(\.threadID), [id(1), id(2)])
        XCTAssertEqual(model.items.map(\.verdict), [.red, .unverified])
    }

    func testBuildComputesUnseenCountFromWatermark() {
        var thread = threadWithVerdict(.red, id: id(1))
        thread.messages.append(ChatMessage(role: .user, content: "go"))
        thread.messages.append(ChatMessage(role: .assistant, content: "started"))
        ThreadReturnWatermarkRecord.markSeen(&thread)
        thread.messages.append(ChatMessage(role: .assistant, content: "overnight update"))

        let model = AttentionModel.build(from: [thread])
        XCTAssertEqual(model.items.first?.unseenCount, 1)
        XCTAssertEqual(model.items.first?.unseenLabel, "1 new")
    }

    func testBuildEmptyWhenNothingNeedsAttention() {
        let model = AttentionModel.build(from: [
            threadWithVerdict(.verified, id: id(1)),
            threadWithVerdict(nil, id: id(2))
        ])
        XCTAssertTrue(model.isEmpty)
    }
}
