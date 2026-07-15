import XCTest
import QuillCodeCore
import QuillCodeReview
@testable import QuillCodeApp

final class WorkspaceReviewCommentPlannerTests: XCTestCase {
    func testFileCommentEventTrimsInputAndEncodesPayload() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let createdAt = Date(timeIntervalSince1970: 42)

        let event = try XCTUnwrap(WorkspaceReviewCommentPlanner.event(
            path: " hello.txt ",
            text: " Keep this wording direct. ",
            review: review(),
            id: id,
            createdAt: createdAt
        ))

        XCTAssertEqual(event.kind, .reviewComment)
        XCTAssertEqual(event.summary, "Commented on hello.txt")
        let comment = try XCTUnwrap(decodeComment(event))
        XCTAssertEqual(comment.id, id)
        XCTAssertEqual(comment.path, "hello.txt")
        XCTAssertNil(comment.lineNumber)
        XCTAssertNil(comment.endLineNumber)
        XCTAssertNil(comment.lineKind)
        XCTAssertEqual(comment.text, "Keep this wording direct.")
        XCTAssertEqual(comment.createdAt, createdAt)
    }

    func testLineCommentEventNormalizesRangeAndKeepsSummaryStable() throws {
        let event = try XCTUnwrap(WorkspaceReviewCommentPlanner.event(
            path: "hello.txt",
            lineNumber: 2,
            endLineNumber: 1,
            lineKind: nil,
            text: "Keep these lines together.",
            review: review()
        ))

        XCTAssertEqual(event.summary, "Commented on hello.txt:1-2")
        let comment = try XCTUnwrap(decodeComment(event))
        XCTAssertEqual(comment.lineNumber, 1)
        XCTAssertEqual(comment.endLineNumber, 2)
        XCTAssertNil(comment.lineKind)
    }

    func testLineKindMustMatchStartingLine() {
        XCTAssertNotNil(WorkspaceReviewCommentPlanner.event(
            path: "hello.txt",
            lineNumber: 1,
            lineKind: .insertion,
            text: "Check inserted line.",
            review: review()
        ))
        XCTAssertNil(WorkspaceReviewCommentPlanner.event(
            path: "hello.txt",
            lineNumber: 1,
            lineKind: .deletion,
            text: "Wrong line kind.",
            review: review()
        ))
    }

    func testRejectsInvalidOrStaleComments() {
        XCTAssertNil(WorkspaceReviewCommentPlanner.event(path: "", text: "Comment.", review: review()))
        XCTAssertNil(WorkspaceReviewCommentPlanner.event(path: "hello.txt", text: "   ", review: review()))
        XCTAssertNil(WorkspaceReviewCommentPlanner.event(path: "README.md", text: "Stale file.", review: review()))
        XCTAssertNil(WorkspaceReviewCommentPlanner.event(
            path: "hello.txt",
            lineNumber: 0,
            text: "Invalid zero line.",
            review: review()
        ))
        XCTAssertNil(WorkspaceReviewCommentPlanner.event(
            path: "hello.txt",
            lineNumber: nil,
            endLineNumber: 2,
            text: "Partial range.",
            review: review()
        ))
        XCTAssertNil(WorkspaceReviewCommentPlanner.event(
            path: "hello.txt",
            lineNumber: 1,
            endLineNumber: 4,
            text: "Missing line.",
            review: review()
        ))
    }

    func testCodeReviewFindingEventPreservesTypedMetadata() throws {
        let createdAt = Date(timeIntervalSince1970: 42)
        let finding = WorkspaceCodeReviewFinding(
            priority: .p1,
            title: "Avoid stale cache reads",
            body: "The cache is read after invalidation and can return an obsolete value.",
            path: "Sources/Cache.swift",
            line: 18,
            endLine: 21
        )

        let event = WorkspaceReviewCommentPlanner.event(for: finding, createdAt: createdAt)

        XCTAssertEqual(event.kind, .reviewComment)
        XCTAssertEqual(event.summary, "P1 finding in Sources/Cache.swift")
        let comment = try XCTUnwrap(decodeComment(event))
        XCTAssertEqual(comment.source, .codeReview)
        XCTAssertEqual(comment.priority, .p1)
        XCTAssertEqual(comment.title, "Avoid stale cache reads")
        XCTAssertEqual(comment.text, finding.body)
        XCTAssertEqual(comment.path, finding.path)
        XCTAssertEqual(comment.lineNumber, 18)
        XCTAssertEqual(comment.endLineNumber, 21)
        XCTAssertEqual(comment.createdAt, createdAt)
    }

    private func review() -> WorkspaceReviewSurface {
        GitDiffReviewParser.parse("""
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1,2 @@
        +new
         old
        """)
    }

    private func decodeComment(_ event: ThreadEvent) -> WorkspaceReviewCommentState? {
        guard let payloadJSON = event.payloadJSON else { return nil }
        return try? JSONHelpers.decode(WorkspaceReviewCommentState.self, from: payloadJSON)
    }
}
