import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceHTMLReviewRendererTests: XCTestCase {
    func testHTMLRendererIncludesGitReviewPane() throws {
        let diff = """
        diff --git a/Package.swift b/Package.swift
        --- a/Package.swift
        +++ b/Package.swift
        @@ -1 +1,2 @@
        +// QuillCode
         import PackageDescription
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let comment = WorkspaceReviewCommentState(path: "Package.swift", text: "Confirm package tools version.")
        let thread = ChatThread(
            title: "Git diff",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Package.swift", payloadJSON: try JSONHelpers.encodePretty(comment))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="review-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="review-file""#))
        XCTAssertTrue(html.contains(#"data-testid="review-action""#))
        XCTAssertTrue(html.contains(#"data-testid="review-hunk""#))
        XCTAssertTrue(html.contains(#"data-testid="review-line""#))
        XCTAssertTrue(html.contains(#"data-testid="review-comment""#))
        XCTAssertTrue(html.contains(#"data-action="open""#))
        XCTAssertTrue(html.contains(#"data-action="stage""#))
        XCTAssertTrue(html.contains(#"data-action="restore""#))
        XCTAssertTrue(html.contains(#"data-action="stage_hunk""#))
        XCTAssertTrue(html.contains(#"data-action="restore_hunk""#))
        XCTAssertTrue(html.contains("Package.swift"))
        XCTAssertTrue(html.contains("Confirm package tools version."))
        XCTAssertTrue(html.contains("Open"))
        XCTAssertTrue(html.contains("Stage"))
        XCTAssertTrue(html.contains("Restore"))
        XCTAssertTrue(html.contains("1 file changed, +1 -0"))
    }

    func testHTMLRendererExplainsUnreadableReviewFiles() {
        let review = WorkspaceReviewSurface(files: [
            WorkspaceReviewFileSurface(
                path: "Assets/logo.png",
                insertions: 0,
                deletions: 0,
                hunks: 0,
                isBinary: true
            )
        ])

        let html = WorkspaceHTMLReviewRenderer.render(review)

        XCTAssertTrue(html.contains(#"data-testid="review-file-unreadable">Binary file"#))
        XCTAssertFalse(html.contains(#"data-action="open""#))
        XCTAssertTrue(html.contains(#"data-action="stage""#))
        XCTAssertTrue(html.contains(#"data-action="restore""#))
    }

    func testHTMLRendererIncludesPullRequestReviewThreads() throws {
        let review = WorkspaceReviewSurface(
            title: "Review threads",
            pullRequestThreads: [
                WorkspacePullRequestReviewThreadSurface(
                    id: "PRRT_one",
                    isResolved: false,
                    path: "Sources/App.swift",
                    line: 42,
                    comments: [
                        WorkspacePullRequestReviewThreadCommentSurface(
                            id: "PRRC_one",
                            databaseID: 171,
                            author: "reviewer",
                            body: "Please extract this helper."
                        )
                    ]
                )
            ]
        )

        let html = WorkspaceHTMLReviewRenderer.render(review)

        XCTAssertTrue(html.contains(#"data-testid="pr-review-threads""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread-status""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread-location""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread-comment""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread-reply""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread-reply-form""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread-reply-input""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread-reply-cancel""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread-reply-submit""#))
        XCTAssertTrue(html.contains(#"data-comment-id="171""#))
        XCTAssertTrue(html.contains(#"data-comment-id="171" hidden"#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-thread-action""#))
        XCTAssertTrue(html.contains(#"data-action="resolve""#))
        XCTAssertTrue(html.contains("Sources/App.swift:42"))
        XCTAssertTrue(html.contains("Please extract this helper."))
        XCTAssertTrue(html.contains("1 review thread, 1 unresolved, 0 resolved"))
    }

    func testHTMLRendererIncludesPullRequestReviewDraft() throws {
        let review = WorkspaceReviewSurface(
            pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface(
                action: .comment,
                inlineComments: [
                    WorkspacePullRequestReviewDraftCommentSurface(
                        path: "Sources/App.swift",
                        line: 42,
                        body: "Cover this branch."
                    ),
                    WorkspacePullRequestReviewDraftCommentSurface(
                        path: "Sources/Skipped.swift",
                        line: 7,
                        body: "Skip this branch.",
                        isIncluded: false
                    ),
                    WorkspacePullRequestReviewDraftCommentSurface(
                        path: "Sources/Empty.swift",
                        line: 9,
                        body: "   "
                    )
                ]
            )
        )

        let html = WorkspaceHTMLReviewRenderer.render(review)

        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-action""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-selector""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-body""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-cancel""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-submit" disabled"#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-include-inline-comments""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-inline-comment""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-inline-comment-toggle""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-inline-comment-move-up""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-inline-comment-move-down""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-inline-comment-body""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-inline-comment-warning""#))
        XCTAssertTrue(html.contains(#"aria-label="Move inline note at Sources/App.swift:42 up""#))
        XCTAssertTrue(html.contains(#"aria-label="Move inline note at Sources/Empty.swift:9 down""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-inline-comment-move-up" aria-label="Move inline note at Sources/App.swift:42 up" data-comment-id=""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-inline-comment-move-down" aria-label="Move inline note at Sources/Empty.swift:9 down" data-comment-id=""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-summary" data-status="blocked""#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-summary-title">Needs attention"#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-summary-detail">Resolve required fields before submitting"#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-summary-item">Action: Comment"#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-summary-item">Target: current pull request"#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-summary-item">Body: required"#))
        XCTAssertTrue(html.contains(#"data-testid="pr-review-draft-summary-item">Inline notes: 2 selected, 1 skipped, 1 missing text"#))
        XCTAssertTrue(html.contains("Include 2 of 3 inline review notes"))
        XCTAssertTrue(html.contains("Skipped"))
        XCTAssertTrue(html.contains("Sources/App.swift:42"))
        XCTAssertTrue(html.contains("Cover this branch."))
        XCTAssertTrue(html.contains("Submit comment"))
    }
}
