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
        XCTAssertTrue(html.contains(#"data-action="stage""#))
        XCTAssertTrue(html.contains(#"data-action="restore""#))
        XCTAssertTrue(html.contains(#"data-action="stage_hunk""#))
        XCTAssertTrue(html.contains(#"data-action="restore_hunk""#))
        XCTAssertTrue(html.contains("Package.swift"))
        XCTAssertTrue(html.contains("Confirm package tools version."))
        XCTAssertTrue(html.contains("Stage"))
        XCTAssertTrue(html.contains("Restore"))
        XCTAssertTrue(html.contains("1 file changed, +1 -0"))
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
}
