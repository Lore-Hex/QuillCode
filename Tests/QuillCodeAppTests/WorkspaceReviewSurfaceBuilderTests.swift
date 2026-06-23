import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceReviewSurfaceBuilderTests: XCTestCase {
    func testSurfaceSummarizesLatestSuccessfulDiff() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1111111..2222222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,2 +1,3 @@
        +let title = "QuillCode"
         import Foundation
        -let old = true
        +let old = false
        diff --git a/README.md b/README.md
        index 3333333..4444444 100644
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -Old README
        +New README
        """

        let review = try WorkspaceReviewSurfaceBuilder(
            toolCards: [diffCard(stdout: diff)],
            events: []
        ).surface()

        XCTAssertTrue(review.isVisible)
        XCTAssertEqual(review.files.map(\.path), ["Sources/App.swift", "README.md"])
        XCTAssertEqual(review.totalInsertions, 3)
        XCTAssertEqual(review.totalDeletions, 2)
        XCTAssertEqual(review.totalHunks, 2)
        XCTAssertEqual(review.subtitle, "2 files changed, +3 -2")
        XCTAssertEqual(review.files.first?.hunkItems.first?.lines.map(\.kind), [.insertion, .context, .deletion, .insertion])
    }

    func testSurfaceAttachesSortedMatchingReviewComments() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1 +1,2 @@
        +let title = "QuillCode"
         import Foundation
        """
        let laterFileComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            text: "Second file note.",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let earlierFileComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            text: "First file note.",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let matchingLineComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 1,
            lineKind: .insertion,
            text: "Keep the title.",
            createdAt: Date(timeIntervalSince1970: 30)
        )
        let rangeComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 1,
            endLineNumber: 2,
            text: "Title and import belong together.",
            createdAt: Date(timeIntervalSince1970: 40)
        )
        let wrongKindComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 1,
            lineKind: .deletion,
            text: "Should not attach to an insertion line."
        )
        let stalePathComment = WorkspaceReviewCommentState(path: "README.md", text: "No visible README diff.")

        let review = try WorkspaceReviewSurfaceBuilder(
            toolCards: [diffCard(stdout: diff)],
            events: [
                reviewCommentEvent(laterFileComment),
                reviewCommentEvent(matchingLineComment),
                reviewCommentEvent(stalePathComment),
                reviewCommentEvent(wrongKindComment),
                reviewCommentEvent(earlierFileComment),
                reviewCommentEvent(rangeComment),
                ThreadEvent(kind: .reviewComment, summary: "bad payload", payloadJSON: "{")
            ]
        ).surface()

        XCTAssertEqual(review.files.count, 1)
        XCTAssertEqual(review.files.first?.comments.map(\.text), ["First file note.", "Second file note."])
        let firstLineComments = review.files.first?.hunkItems.first?.lines.first?.comments ?? []
        XCTAssertEqual(firstLineComments.map(\.text), ["Keep the title.", "Title and import belong together."])
        XCTAssertEqual(firstLineComments.last?.lineRangeLabel, "Lines 1-2")
    }

    func testLatestFailedDiffHidesEarlierSuccessfulDiff() throws {
        let earlierSuccessfulCard = try diffCard(id: "diff-1", stdout: """
        diff --git a/A.swift b/A.swift
        --- a/A.swift
        +++ b/A.swift
        @@ -1 +1 @@
        -old
        +new
        """)
        let latestFailedCard = try diffCard(
            id: "diff-2",
            status: .failed,
            result: ToolResult(ok: false, error: "not a git repository")
        )

        let review = WorkspaceReviewSurfaceBuilder(
            toolCards: [earlierSuccessfulCard, latestFailedCard],
            events: []
        ).surface()

        XCTAssertFalse(review.isVisible)
        XCTAssertEqual(review.files, [])
    }

    func testMalformedOrUnsuccessfulDiffOutputReturnsEmptySurface() throws {
        let malformedReview = WorkspaceReviewSurfaceBuilder(
            toolCards: [
                ToolCardState(
                    id: "malformed",
                    title: "host.git.diff",
                    subtitle: "done",
                    status: .done,
                    outputJSON: "{"
                )
            ],
            events: []
        ).surface()
        let failedReview = try WorkspaceReviewSurfaceBuilder(
            toolCards: [diffCard(result: ToolResult(ok: false, error: "failed"))],
            events: []
        ).surface()
        let otherToolReview = try WorkspaceReviewSurfaceBuilder(
            toolCards: [
                ToolCardState(
                    id: "shell",
                    title: "host.shell.run",
                    subtitle: "done",
                    status: .done,
                    outputJSON: JSONHelpers.encodePretty(ToolResult(ok: true, stdout: "ignored"))
                )
            ],
            events: []
        ).surface()

        XCTAssertFalse(malformedReview.isVisible)
        XCTAssertFalse(failedReview.isVisible)
        XCTAssertFalse(otherToolReview.isVisible)
    }

    private func diffCard(
        id: String = "diff",
        status: ToolCardStatus = .done,
        stdout: String = "",
        result: ToolResult? = nil
    ) throws -> ToolCardState {
        let result = result ?? ToolResult(ok: true, stdout: stdout)
        return ToolCardState(
            id: id,
            title: "host.git.diff",
            subtitle: "done",
            status: status,
            outputJSON: try JSONHelpers.encodePretty(result)
        )
    }

    private func reviewCommentEvent(_ comment: WorkspaceReviewCommentState) throws -> ThreadEvent {
        ThreadEvent(
            kind: .reviewComment,
            summary: "Commented on \(comment.path)",
            payloadJSON: try JSONHelpers.encodePretty(comment)
        )
    }
}
