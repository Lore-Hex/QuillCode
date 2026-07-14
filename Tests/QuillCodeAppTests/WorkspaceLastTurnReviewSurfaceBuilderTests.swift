import XCTest
@testable import QuillCodeApp
import QuillCodeCore
import QuillCodeTools

final class WorkspaceLastTurnReviewSurfaceBuilderTests: XCTestCase {
    func testBuildsNewestTurnFromRecordedPatchesAndCoalescesRepeatedFiles() throws {
        let user = ChatMessage(role: .user, content: "Edit the title", createdAt: date(100))
        let thread = ChatThread(title: "T", messages: [user], events: [
            patchEvent(firstPatch, at: 110),
            patchEvent(secondPatch, at: 120)
        ])

        let surface = WorkspaceLastTurnReviewSurfaceBuilder(thread: thread).surface()

        XCTAssertEqual(surface.activeScope, .lastTurn)
        XCTAssertEqual(surface.lastTurnMessageID, user.id)
        XCTAssertEqual(surface.files.count, 1)
        XCTAssertEqual(surface.files.first?.path, "Sources/App.swift")
        XCTAssertEqual(surface.files.first?.insertions, 2)
        XCTAssertEqual(surface.files.first?.deletions, 2)
        XCTAssertEqual(surface.files.first?.hunkItems.count, 2)
        XCTAssertEqual(Set(surface.files.first?.hunkItems.map(\.id) ?? []).count, 2)
        XCTAssertEqual(surface.files.first?.actions(in: .lastTurn).map(\.kind), [.open])
        XCTAssertEqual(surface.wholeDiffActions.map(\.kind), [.revertTurn])
        XCTAssertEqual(surface.wholeDiffActions.first?.path, "")
    }

    func testCoalescedFileUsesTheLatestPatchReadabilityState() {
        let user = ChatMessage(role: .user, content: "Replace the file", createdAt: date(100))
        let thread = ChatThread(title: "T", messages: [user], events: [
            patchEvent(deletionPatch, at: 110),
            patchEvent(recreationPatch, at: 120)
        ])

        let surface = WorkspaceLastTurnReviewSurfaceBuilder(thread: thread).surface()

        XCTAssertEqual(surface.files.count, 1)
        XCTAssertEqual(surface.files.first?.path, "Sources/App.swift")
        XCTAssertEqual(surface.files.first?.isDeleted, false)
        XCTAssertNil(surface.files.first?.unreadableReason)
    }

    func testEmptyNewestTurnDoesNotShowAnOlderTurnPatch() {
        let oldUser = ChatMessage(role: .user, content: "Edit", createdAt: date(100))
        let latestUser = ChatMessage(role: .user, content: "Explain", createdAt: date(300))
        let thread = ChatThread(title: "T", messages: [oldUser, latestUser], events: [
            patchEvent(firstPatch, at: 110),
            toolEvent(name: ToolDefinition.fileRead.name, arguments: ["path": "Sources/App.swift"], at: 310)
        ])

        let surface = WorkspaceLastTurnReviewSurfaceBuilder(thread: thread).surface()

        XCTAssertEqual(surface.activeScope, .lastTurn)
        XCTAssertEqual(surface.subtitle, "No changes in the last turn")
        XCTAssertTrue(surface.files.isEmpty)
        XCTAssertNil(surface.lastTurnMessageID)
        XCTAssertTrue(surface.wholeDiffActions.isEmpty)
    }

    func testDisclosesPartialProvenanceAndKeepsRemoteComparisonReadOnly() {
        let user = ChatMessage(role: .user, content: "Edit", createdAt: date(100))
        let thread = ChatThread(title: "T", messages: [user], events: [
            patchEvent(firstPatch, at: 110),
            toolEvent(name: ToolDefinition.fileWrite.name, arguments: ["path": "Other.txt", "content": "x"], at: 120)
        ])

        let surface = WorkspaceLastTurnReviewSurfaceBuilder(
            thread: thread,
            allowsRevert: false
        ).surface()

        XCTAssertEqual(surface.scopeNotice, WorkspaceLastTurnReviewSurfaceBuilder.partialProvenanceNotice)
        XCTAssertNil(surface.lastTurnMessageID)
        XCTAssertTrue(surface.wholeDiffActions.isEmpty)
    }

    private func patchEvent(_ patch: String, at seconds: TimeInterval) -> ThreadEvent {
        toolEvent(name: ToolDefinition.applyPatch.name, arguments: ["patch": patch], at: seconds)
    }

    private func toolEvent(
        name: String,
        arguments: [String: String],
        at seconds: TimeInterval
    ) -> ThreadEvent {
        let call = ToolCall(name: name, argumentsJSON: ToolArguments.json(arguments))
        return ThreadEvent(
            kind: .toolQueued,
            createdAt: date(seconds),
            summary: "\(name) queued",
            payloadJSON: try? JSONHelpers.encodePretty(call.redactedForTranscript())
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private var firstPatch: String {
        """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1 +1 @@
        -let title = "Old"
        +let title = "QuillCode"
        """
    }

    private var secondPatch: String {
        """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -2 +2 @@
        -let count = 1
        +let count = 2
        """
    }

    private var deletionPatch: String {
        """
        diff --git a/Sources/App.swift b/Sources/App.swift
        deleted file mode 100644
        --- a/Sources/App.swift
        +++ /dev/null
        @@ -1 +0,0 @@
        -let title = "Old"
        """
    }

    private var recreationPatch: String {
        """
        diff --git a/Sources/App.swift b/Sources/App.swift
        new file mode 100644
        --- /dev/null
        +++ b/Sources/App.swift
        @@ -0,0 +1 @@
        +let title = "New"
        """
    }
}
