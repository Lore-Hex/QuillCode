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

    func testLastDiffDetectedForEveryMutatingTool() {
        // Every mutating tool the codebase can emit as a card — including the ones an earlier
        // name-list missed (revert_turn / restore / restore_hunk) — must count as a diff. Driven
        // by the shared risk-based predicate, so this stays correct as tools are added.
        let mutating = [
            "host.apply_patch",
            "host.file.write",
            "host.git.commit",
            "host.git.stage",
            "host.git.restore",
            "host.git.restore_hunk",
            "host.git.revert_turn",
            "host.shell.run",
            "apply_patch" // de-prefixed display title still resolves
        ]
        for name in mutating {
            let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
                card(id: "t1", title: name, status: .done)
            ]))
            XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-t1", "expected \(name) to be a diff turn")
        }
    }

    func testRevertTurnCardIsADiffAndAnchorsLastDiff() {
        // Regression: jumping to a just-reverted diff is a prime use of "Last diff". The revert is
        // recorded as a host.git.revert_turn card (a dynamic tool with no static definition).
        XCTAssertEqual(WorkspaceTurnRevertPlanner.revertTurnToolName, "host.git.revert_turn")
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "patch", title: "host.apply_patch", status: .done),
            card(id: "revert", title: WorkspaceTurnRevertPlanner.revertTurnToolName, status: .done)
        ]))
        XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-revert")
        XCTAssertTrue(anchors.hasDiff)
    }

    func testGitRestoreAndRestoreHunkAreDiffs() {
        for name in ["host.git.restore", "host.git.restore_hunk"] {
            let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
                card(id: "t1", title: name, status: .done)
            ]))
            XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-t1", "\(name) overwrites working-tree files")
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

    func testUnknownNonRegisteredToolWithFileArtifactIsNotADiff() {
        // We do NOT infer diffs from artifacts, and an unregistered (dynamic/MCP-shaped) name is
        // not trusted as mutating, so a read-capable tool that emits path artifacts cannot
        // masquerade as a write.
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
        // A patch (diff) precedes a failed READ (error, not a diff): the two anchors land on
        // different turns.
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.apply_patch", status: .done),
            card(id: "t2", title: "host.file.read", status: .failed)
        ]))
        XCTAssertEqual(anchors.lastErrorAnchorID, "timeline-tool-t2")
        XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-t1")
    }

    func testFailedWriteIsBothErrorAndDiff() {
        // A single failed write is both the last error and the last diff (it attempted a change).
        let anchors = TranscriptNavigationAnchors.derive(from: surface(toolCards: [
            card(id: "t1", title: "host.file.write", status: .failed)
        ]))
        XCTAssertEqual(anchors.lastErrorAnchorID, "timeline-tool-t1")
        XCTAssertEqual(anchors.lastDiffAnchorID, "timeline-tool-t1")
    }

    func testToolNameMatchingIsPrefixTolerantAndRejectsReadsAndNonTools() {
        XCTAssertTrue(TranscriptNavigationAnchors.isDiffProducingToolName("host.apply_patch"))
        XCTAssertTrue(TranscriptNavigationAnchors.isDiffProducingToolName("  apply_patch  "))
        XCTAssertTrue(TranscriptNavigationAnchors.isDiffProducingToolName("host.git.revert_turn"))
        XCTAssertFalse(TranscriptNavigationAnchors.isDiffProducingToolName("host.file.read"))
        // A non-tool card title (e.g. the orphan-card fallback) must not false-positive just
        // because it is not a registered read tool.
        XCTAssertFalse(TranscriptNavigationAnchors.isDiffProducingToolName("Tool"))
        XCTAssertFalse(TranscriptNavigationAnchors.isDiffProducingToolName("Approval needed"))
    }
}
