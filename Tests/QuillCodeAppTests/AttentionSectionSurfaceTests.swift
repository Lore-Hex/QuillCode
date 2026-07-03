import XCTest
import QuillCodeCore
@testable import QuillCodeApp

/// App-layer tests for the morning-triage Attention surface + HTML rendering + model actions (issue
/// #877). The pure ranking/selection/triage semantics are covered in QuillCodeCoreTests; here we verify
/// the surface projection, the model action wiring (which persists), and that native + HTML render off
/// the same shared model.
@MainActor
final class AttentionSectionSurfaceTests: XCTestCase {

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", n))")!
    }

    private func threadWithVerdict(
        _ verdict: RunIntegrityVerdict,
        id threadID: UUID,
        title: String,
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> ChatThread {
        var thread = ChatThread(id: threadID, title: title, updatedAt: updatedAt)
        let report = RunIntegrityReport(
            verdict: verdict,
            reasons: [RunIntegrityReason(rule: .standingTestFailure, detail: "make test exited 1")]
        )
        if let event = RunIntegrityRecord.event(for: report) {
            thread.events.append(event)
        }
        return thread
    }

    private func model(_ threads: [ChatThread], selected: UUID? = nil) -> QuillCodeWorkspaceModel {
        QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: threads, selectedThreadID: selected))
    }

    // MARK: - Surface projection

    func testSectionSurfaceRanksAndProjectsRows() {
        let surface = model([
            threadWithVerdict(.unverified, id: id(1), title: "yellow run", updatedAt: Date(timeIntervalSince1970: 200)),
            threadWithVerdict(.red, id: id(2), title: "red run", updatedAt: Date(timeIntervalSince1970: 100))
        ]).surface()
        let attention = surface.sidebar.attention
        XCTAssertEqual(attention.rows.map(\.title), ["red run", "yellow run"])
        XCTAssertEqual(attention.rows.first?.badgeLabel, "RED")
    }

    func testEmptySectionSurfaceWhenNothingNeedsAttention() {
        let surface = model([threadWithVerdict(.verified, id: id(1), title: "clean")]).surface()
        XCTAssertTrue(surface.sidebar.attention.isEmpty)
    }

    // MARK: - Model actions (persist + surface)

    func testAcknowledgeRemovesFromAttentionAndPersists() {
        let m = model([
            threadWithVerdict(.red, id: id(1), title: "red a", updatedAt: Date(timeIntervalSince1970: 300)),
            threadWithVerdict(.red, id: id(2), title: "red b", updatedAt: Date(timeIntervalSince1970: 200))
        ], selected: id(1))
        XCTAssertEqual(m.surface().sidebar.attention.rows.count, 2)

        m.attentionAcknowledgeSelected()
        let after = m.surface().sidebar.attention
        XCTAssertEqual(after.rows.count, 1)
        XCTAssertEqual(after.rows.first?.threadID, id(2))
        // Persisted on the thread.
        let thread = m.root.threads.first { $0.id == id(1) }!
        XCTAssertEqual(ThreadTriageRecord.current(in: thread), .acknowledged)
    }

    func testDismissRemovesFromAttention() {
        let m = model([threadWithVerdict(.unverified, id: id(1), title: "y")], selected: id(1))
        m.attentionDismissSelected()
        XCTAssertTrue(m.surface().sidebar.attention.isEmpty)
        XCTAssertEqual(ThreadTriageRecord.current(in: m.root.threads[0]), .dismissed)
    }

    func testTriageNoOpOnEmptyAttention() {
        let m = model([threadWithVerdict(.verified, id: id(1), title: "clean")], selected: id(1))
        // Nothing to triage — must not crash or mutate.
        m.attentionAcknowledgeSelected()
        m.attentionDismissSelected()
        m.attentionMoveDown()
        m.attentionMoveUp()
        XCTAssertTrue(m.surface().sidebar.attention.isEmpty)
    }

    func testOpenDigestSurfacesDigestAndCloseClearsIt() {
        let m = model([threadWithVerdict(.red, id: id(1), title: "red")], selected: nil)
        XCTAssertNil(m.surface().attentionDigest)
        m.openAttentionDigest(for: id(1))
        let digest = m.surface().attentionDigest
        XCTAssertEqual(digest?.threadID, id(1))
        XCTAssertEqual(digest?.verdict, .red)
        m.closeAttentionDigest()
        XCTAssertNil(m.surface().attentionDigest)
    }

    func testMoveDownClampsAcrossModel() {
        let m = model([
            threadWithVerdict(.red, id: id(1), title: "a", updatedAt: Date(timeIntervalSince1970: 300)),
            threadWithVerdict(.red, id: id(2), title: "b", updatedAt: Date(timeIntervalSince1970: 200))
        ], selected: id(1))
        m.attentionMoveDown()
        XCTAssertEqual(m.attentionModel.selectedThreadID, id(2))
        m.attentionMoveDown() // clamp
        XCTAssertEqual(m.attentionModel.selectedThreadID, id(2))
    }

    // MARK: - HTML render parity of shape

    func testHTMLRendererEmitsAttentionSection() {
        var thread = threadWithVerdict(.red, id: id(2), title: "overnight red")
        thread.messages.append(ChatMessage(role: .user, content: "go"))
        thread.messages.append(ChatMessage(role: .assistant, content: "started"))
        ThreadReturnWatermarkRecord.markSeen(&thread)
        thread.messages.append(ChatMessage(role: .assistant, content: "new turn"))

        let html = WorkspaceHTMLRenderer.render(model([thread]).surface())
        XCTAssertTrue(html.contains(#"data-testid="attention-section""#))
        XCTAssertTrue(html.contains(#"data-testid="attention-verdict" data-verdict="red""#))
        XCTAssertTrue(html.contains("RED"))
        XCTAssertTrue(html.contains(#"data-testid="attention-unseen""#))
        XCTAssertTrue(html.contains("1 new"))
    }

    func testHTMLRendererOmitsAttentionSectionWhenEmpty() {
        let html = WorkspaceHTMLRenderer.render(model([threadWithVerdict(.verified, id: id(1), title: "clean")]).surface())
        XCTAssertFalse(html.contains(#"data-testid="attention-section""#))
    }

    func testDigestHTMLRendersVerdictReasonsAndSeam() {
        // A real standing test failure so RunIntegrityScanner produces reasons for the card body.
        var thread = ChatThread(id: id(2), title: "overnight red")
        let call = ToolCall(name: RunIntegrityScanner.shellRunToolName, argumentsJSON: #"{"cmd":"make test"}"#)
        let fail = ToolResult(ok: false, stdout: "", stderr: "1 failing", exitCode: 1, error: nil)
        thread.events.append(ThreadEvent(kind: .toolQueued, summary: "\(call.name) queued", payloadJSON: (try? JSONHelpers.encodePretty(call)) ?? "{}"))
        thread.events.append(ThreadEvent(kind: .toolRunning, summary: "\(call.name) running"))
        thread.events.append(ThreadEvent(kind: .toolFailed, summary: "\(call.name) failed", payloadJSON: (try? JSONHelpers.encodePretty(fail)) ?? "{}"))
        thread.messages.append(ChatMessage(role: .user, content: "go"))
        thread.messages.append(ChatMessage(role: .assistant, content: "Left a failing test."))
        RunIntegrityRecord.record(into: &thread)
        ThreadReturnWatermarkRecord.markSeen(&thread)
        thread.messages.append(ChatMessage(role: .assistant, content: "wrap up"))
        thread.messages.append(ChatMessage(role: .assistant, content: "final"))

        let m = model([thread])
        m.openAttentionDigest(for: id(2))
        let html = WorkspaceHTMLRenderer.render(m.surface())
        XCTAssertTrue(html.contains(#"data-testid="attention-digest""#))
        XCTAssertTrue(html.contains(#"data-testid="attention-digest-verdict" data-verdict="red""#))
        XCTAssertTrue(html.contains(#"data-testid="attention-digest-seam""#))
        XCTAssertTrue(html.contains(#"data-testid="attention-digest-reasons""#))
        XCTAssertTrue(html.contains(#"data-command-id="attention-acknowledge""#))
        XCTAssertTrue(html.contains(#"data-command-id="attention-dismiss""#))
    }
}
