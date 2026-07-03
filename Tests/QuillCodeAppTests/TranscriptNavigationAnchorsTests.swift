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

    func testSuccessfulReadWithPathArtifactIsNotADiff() {
        // host.file.read returns the read file's absolute path as an artifact, which the artifact
        // classifier labels `.file`. It must NOT be treated as a diff (it read, did not write).
        let fileArtifact = ToolArtifactState(value: "/repo/src/main.swift")
        XCTAssertEqual(fileArtifact.kind, .file)
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.file.read", status: .done, artifacts: [fileArtifact])
        ]))
        XCTAssertNil(anchors.lastDiffAnchorID, "a successful read is not a diff")
        XCTAssertFalse(anchors.hasDiff)
    }

    func testReadOnlyListAndSearchWithPathArtifactsAreNotDiffs() {
        // list/search emit a path-per-entry; none of these are diffs.
        for name in ["host.file.list", "host.file.search"] {
            let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
                card(
                    id: "t1",
                    title: name,
                    status: .done,
                    artifacts: [ToolArtifactState(value: "/repo/a.swift"), ToolArtifactState(value: "/repo/b.swift")]
                )
            ]))
            XCTAssertNil(anchors.lastDiffAnchorID, "\(name) is read-only and must not be a diff")
        }
    }

    func testReadOnlySessionKeepsDiffAffordanceDisabled() {
        // A whole session that only read/listed/searched (all carrying path artifacts) has NO diff.
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.file.list", status: .done, artifacts: [ToolArtifactState(value: "/repo/src")]),
            card(id: "t2", title: "host.file.search", status: .done, artifacts: [ToolArtifactState(value: "/repo/src/x.swift")]),
            card(id: "t3", title: "host.file.read", status: .done, artifacts: [ToolArtifactState(value: "/repo/src/x.swift")])
        ]))
        XCTAssertNil(anchors.lastDiffAnchorID)
        XCTAssertFalse(anchors.hasDiff)
    }

    func testDiffThenReadJumpsToTheDiffNotTheRead() {
        // The regression: [apply_patch, then a successful read carrying a path artifact]. The diff
        // anchor must stay on the patch — the later read must not overwrite it.
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "patch", title: "host.apply_patch", status: .done),
            card(id: "read", title: "host.file.read", status: .done, artifacts: [ToolArtifactState(value: "/repo/src/main.swift")])
        ]))
        XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-patch")
    }

    func testUnknownToolWithFileArtifactIsNotADiff() {
        // We intentionally do NOT infer diffs from artifacts for tools outside the known set, so a
        // future read-capable tool that emits path artifacts cannot masquerade as a write.
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.custom.generate", status: .done, artifacts: [ToolArtifactState(value: "/repo/src/main.swift")])
        ]))
        XCTAssertNil(anchors.lastDiffAnchorID)
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
