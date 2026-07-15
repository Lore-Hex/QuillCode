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
        XCTAssertEqual(review.activeScope, .unstaged)
        XCTAssertEqual(review.files.first?.hunkItems.first?.lines.map(\.kind), [.insertion, .context, .deletion, .insertion])
    }

    func testSurfaceDerivesStagedScopeAndKeepsEmptyDiffVisible() throws {
        let review = try WorkspaceReviewSurfaceBuilder(
            toolCards: [diffCard(staged: true)],
            events: []
        ).surface()

        XCTAssertTrue(review.isVisible)
        XCTAssertEqual(review.activeScope, .staged)
        XCTAssertEqual(review.availableScopes, [.unstaged, .staged, .commit, .branch, .lastTurn])
        XCTAssertEqual(review.subtitle, "No staged changes")
        XCTAssertTrue(review.files.isEmpty)
    }

    func testSurfacePreservesHistoricalComparisonReference() throws {
        let commitReview = try WorkspaceReviewSurfaceBuilder(
            toolCards: [diffCard(arguments: ["commit": "abc123"])],
            events: []
        ).surface()
        let branchReview = try WorkspaceReviewSurfaceBuilder(
            toolCards: [diffCard(arguments: ["baseBranch": "origin/main"])],
            events: []
        ).surface()

        XCTAssertEqual(commitReview.activeSelection, .commit("abc123"))
        XCTAssertEqual(commitReview.subtitle, "No changes in commit abc123")
        XCTAssertEqual(branchReview.activeSelection, .branch("origin/main"))
        XCTAssertEqual(branchReview.subtitle, "No changes against origin/main")
    }

    func testHistoricalComparisonActionsAreReadOnly() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1 +1 @@
        -let old = true
        +let old = false
        """
        let review = try WorkspaceReviewSurfaceBuilder(
            toolCards: [diffCard(stdout: diff, arguments: ["commit": "HEAD"])],
            events: []
        ).surface()
        let file = try XCTUnwrap(review.files.first)
        let hunk = try XCTUnwrap(file.hunkItems.first)

        XCTAssertEqual(file.actions(in: .commit).map(\.kind), [.open])
        XCTAssertTrue(hunk.actions(in: .commit).isEmpty)
        XCTAssertEqual(file.actions(in: .branch).map(\.kind), [.open])
        XCTAssertTrue(hunk.actions(in: .branch).isEmpty)
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

    func testSurfaceMarksDeletedFilesUnreadable() throws {
        let diff = """
        diff --git a/Sources/Removed.swift b/Sources/Removed.swift
        deleted file mode 100644
        index 1111111..0000000
        --- a/Sources/Removed.swift
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -let removed = true
        -print(removed)
        """

        let review = try WorkspaceReviewSurfaceBuilder(
            toolCards: [diffCard(stdout: diff)],
            events: []
        ).surface()
        let file = try XCTUnwrap(review.files.first)

        XCTAssertEqual(file.path, "Sources/Removed.swift")
        XCTAssertTrue(file.isDeleted)
        XCTAssertEqual(file.changeLabel, "+0 · -2 · 1 hunk · deleted")
        XCTAssertEqual(file.unreadableReason, "Deleted file")
        XCTAssertEqual(file.actions.map(\.kind), [.stage, .restore])
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
        XCTAssertEqual(review.scopeNotice, "Couldn't load this review: not a git repository")
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

    func testSurfaceSummarizesLatestSuccessfulPullRequestReviewThreads() throws {
        let review = try WorkspaceReviewSurfaceBuilder(
            toolCards: [
                pullRequestReviewThreadsCard(stdout: pullRequestReviewThreadsOutput(), selector: "123")
            ],
            events: []
        ).surface()

        XCTAssertTrue(review.isVisible)
        XCTAssertEqual(review.title, "Review threads")
        XCTAssertEqual(review.subtitle, "2 review threads, 1 unresolved, 1 resolved")
        XCTAssertEqual(review.badgeLabel, "2 threads")
        XCTAssertEqual(review.pullRequestThreads.map(\.id), ["PRRT_one", "PRRT_two"])
        XCTAssertEqual(review.pullRequestThreads.first?.locationLabel, "Sources/App.swift:42")
        XCTAssertEqual(review.pullRequestThreads.first?.summaryText, "Extract this helper.")
        XCTAssertEqual(review.pullRequestThreads.first?.authorLabel, "reviewer")
        XCTAssertEqual(review.pullRequestThreads.first?.actions.first?.selector, "123")
        XCTAssertEqual(review.pullRequestThreads.last?.statusLabel, "Resolved · outdated")
        XCTAssertEqual(review.files, [])
    }

    func testSurfaceCombinesDiffAndPullRequestReviewThreads() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1 +1,2 @@
        +let title = "QuillCode"
         import Foundation
        """

        let review = try WorkspaceReviewSurfaceBuilder(
            toolCards: [
                pullRequestReviewThreadsCard(stdout: pullRequestReviewThreadsOutput(), selector: "123"),
                diffCard(stdout: diff)
            ],
            events: []
        ).surface()

        XCTAssertEqual(review.files.map(\.path), ["Sources/App.swift"])
        XCTAssertEqual(review.pullRequestThreads.count, 2)
        XCTAssertEqual(review.badgeLabel, "1 hunk · 2 threads")
        XCTAssertEqual(review.subtitle, "1 file changed, +1 -0")
    }

    func testLatestFailedPullRequestReviewThreadsHidesEarlierThreadSurface() throws {
        let review = try WorkspaceReviewSurfaceBuilder(
            toolCards: [
                pullRequestReviewThreadsCard(id: "threads-1", stdout: pullRequestReviewThreadsOutput()),
                pullRequestReviewThreadsCard(
                    id: "threads-2",
                    status: .failed,
                    result: ToolResult(ok: false, error: "gh failed")
                )
            ],
            events: []
        ).surface()

        XCTAssertFalse(review.isVisible)
        XCTAssertEqual(review.pullRequestThreads, [])
    }

    private func diffCard(
        id: String = "diff",
        status: ToolCardStatus = .done,
        stdout: String = "",
        staged: Bool = false,
        arguments: [String: Any]? = nil,
        result: ToolResult? = nil
    ) throws -> ToolCardState {
        let result = result ?? ToolResult(ok: true, stdout: stdout)
        let inputJSON = arguments.map(ToolArguments.json)
            ?? (staged ? ToolArguments.json(["staged": true]) : "{}")
        return ToolCardState(
            id: id,
            title: "host.git.diff",
            subtitle: "done",
            status: status,
            inputJSON: inputJSON,
            outputJSON: try JSONHelpers.encodePretty(result)
        )
    }

    private func pullRequestReviewThreadsCard(
        id: String = "threads",
        status: ToolCardStatus = .done,
        stdout: String = "",
        selector: String? = nil,
        result: ToolResult? = nil
    ) throws -> ToolCardState {
        let result = result ?? ToolResult(ok: true, stdout: stdout)
        let input = selector.map { ToolArguments.json(["selector": $0]) } ?? "{}"
        return ToolCardState(
            id: id,
            title: "host.git.pr.review_threads",
            subtitle: "done",
            status: status,
            inputJSON: input,
            outputJSON: try JSONHelpers.encodePretty(result)
        )
    }

    private func pullRequestReviewThreadsOutput() -> String {
        """
        {
          "data": {
            "repository": {
              "pullRequest": {
                "reviewThreads": {
                  "nodes": [
                    {
                      "id": "PRRT_one",
                      "isResolved": false,
                      "isOutdated": false,
                      "path": "Sources/App.swift",
                      "line": 42,
                      "startLine": null,
                      "comments": {
                        "nodes": [
                          {
                            "id": "PRRC_one",
                            "databaseId": 171,
                            "body": "Extract this helper.",
                            "author": { "login": "reviewer" }
                          }
                        ]
                      }
                    },
                    {
                      "id": "PRRT_two",
                      "isResolved": true,
                      "isOutdated": true,
                      "path": "Tests/AppTests.swift",
                      "line": 18,
                      "startLine": 16,
                      "comments": {
                        "nodes": [
                          {
                            "id": "PRRC_two",
                            "databaseId": 172,
                            "body": "Covered now.",
                            "author": { "login": "maintainer" }
                          }
                        ]
                      }
                    }
                  ]
                }
              }
            }
          }
        }
        """
    }

    private func reviewCommentEvent(_ comment: WorkspaceReviewCommentState) throws -> ThreadEvent {
        ThreadEvent(
            kind: .reviewComment,
            summary: "Commented on \(comment.path)",
            payloadJSON: try JSONHelpers.encodePretty(comment)
        )
    }
}
