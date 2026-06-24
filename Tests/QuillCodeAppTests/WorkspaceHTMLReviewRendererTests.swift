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
}
