import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class TranscriptNavigationAnchorsTests: XCTestCase {
    private func card(
        id: String,
        title: String,
        status: ToolCardStatus,
        artifacts: [ToolArtifactState] = []
    ) -> ToolCardState {
        ToolCardState(id: id, title: title, subtitle: "", status: status, artifacts: artifacts)
    }

    private func surface(messages: [(ChatRole, String)] = [], toolCards: [ToolCardState]) -> TranscriptSurface {
        TranscriptSurface(
            messages: messages.map { MessageSurface(message: ChatMessage(role: $0.0, content: $0.1)) },
            toolCards: toolCards
        )
    }

    func testNoErrorOrDiffYieldsNilAnchors() {
        let anchors = TranscriptNavigationAnchors.derive(
            from: surface(toolCards: [card(id: "t1", title: "host.file.read", status: .done)])
        )
        XCTAssertNil(anchors.lastErrorAnchorID)
        XCTAssertNil(anchors.lastDiffAnchorID)
        XCTAssertFalse(anchors.hasError)
        XCTAssertFalse(anchors.hasDiff)
    }

    func testEmptyTranscriptYieldsNilAnchors() {
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: []))
        XCTAssertNil(anchors.lastErrorAnchorID)
        XCTAssertNil(anchors.lastDiffAnchorID)
    }

    func testLastErrorPicksMostRecentFailedCard() {
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.shell.run", status: .failed),
            card(id: "t2", title: "host.shell.run", status: .done),
            card(id: "t3", title: "host.shell.run", status: .failed)
        ]))
        // Most recent failure is t3.
        XCTAssertEqual(anchors.lastErrorAnchorID, "timeline-tool-t3")
        XCTAssertTrue(anchors.hasError)
    }

    func testLastDiffDetectedFromApplyPatchAndFileWriteAndCommit() {
        for name in ["host.apply_patch", "host.file.write", "host.git.commit", "apply_patch", "Edit", "Write"] {
            let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
                card(id: "t1", title: name, status: .done)
            ]))
            XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-t1", "expected \(name) to be a diff turn")
        }
    }

    func testLastDiffDetectedFromFileArtifactFallback() {
        // A tool name we don't recognize, but it emitted a file artifact => still a diff turn.
        let fileArtifact = ToolArtifactState(value: "/repo/src/main.swift")
        XCTAssertEqual(fileArtifact.kind, .file)
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.custom.generate", status: .done, artifacts: [fileArtifact])
        ]))
        XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-t1")
    }

    func testNonDiffToolWithUrlArtifactIsNotADiff() {
        let urlArtifact = ToolArtifactState(value: "https://example.com/report")
        XCTAssertEqual(urlArtifact.kind, .url)
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.web.fetch", status: .done, artifacts: [urlArtifact])
        ]))
        XCTAssertNil(anchors.lastDiffAnchorID)
    }

    func testLastDiffPicksMostRecentAmongMany() {
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.apply_patch", status: .done),
            card(id: "t2", title: "host.file.read", status: .done),
            card(id: "t3", title: "host.file.write", status: .done)
        ]))
        XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-t3")
    }

    func testErrorAndDiffAreIndependentAnchors() {
        // A failed write is BOTH the last error and the last diff.
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.apply_patch", status: .done),
            card(id: "t2", title: "host.shell.run", status: .failed)
        ]))
        XCTAssertEqual(anchors.lastErrorAnchorID, "timeline-tool-t2")
        XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-t1")
    }

    func testToolNameMatchingIsCaseInsensitiveAndPrefixTolerant() {
        XCTAssertTrue(TranscriptNavigationAnchors.isDiffProducingToolName("HOST.APPLY_PATCH"))
        XCTAssertTrue(TranscriptNavigationAnchors.isDiffProducingToolName("  apply_patch  "))
        XCTAssertFalse(TranscriptNavigationAnchors.isDiffProducingToolName("host.file.read"))
    }
}
