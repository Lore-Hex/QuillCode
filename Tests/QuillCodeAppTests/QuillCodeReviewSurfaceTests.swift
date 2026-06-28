import XCTest
@testable import QuillCodeApp

final class QuillCodeReviewSurfaceTests: XCTestCase {
    func testReviewSurfaceSummarizesFilesTotalsAndVisibility() {
        let firstFile = WorkspaceReviewFileSurface(
            path: "Sources/App.swift",
            insertions: 4,
            deletions: 1,
            hunks: 2
        )
        let secondFile = WorkspaceReviewFileSurface(
            path: "README.md",
            insertions: 1,
            deletions: 0,
            hunks: 1
        )

        let empty = WorkspaceReviewSurface()
        let review = WorkspaceReviewSurface(files: [firstFile, secondFile])

        XCTAssertFalse(empty.isVisible)
        XCTAssertEqual(empty.subtitle, "Latest git diff")
        XCTAssertTrue(review.isVisible)
        XCTAssertEqual(review.title, "Review changes")
        XCTAssertEqual(review.subtitle, "2 files changed, +5 -1")
        XCTAssertEqual(review.totalInsertions, 5)
        XCTAssertEqual(review.totalDeletions, 1)
        XCTAssertEqual(review.totalHunks, 3)
        XCTAssertEqual(review.badgeLabel, "3 hunks")
    }

    func testReviewSurfaceSummarizesPullRequestThreads() {
        let unresolved = WorkspacePullRequestReviewThreadSurface(
            id: "PRRT_one",
            isResolved: false,
            path: "Sources/App.swift",
            line: 42,
            comments: [
                WorkspacePullRequestReviewThreadCommentSurface(
                    id: "PRRC_one",
                    databaseID: 11,
                    author: "reviewer",
                    body: "Please extract this helper.\nThanks."
                )
            ],
            selector: "123"
        )
        let resolved = WorkspacePullRequestReviewThreadSurface(
            id: "PRRT_two",
            isResolved: true,
            isOutdated: true,
            path: "Tests/AppTests.swift",
            line: 18,
            startLine: 16
        )

        let review = WorkspaceReviewSurface(
            title: "Review threads",
            pullRequestThreads: [unresolved, resolved]
        )

        XCTAssertTrue(review.isVisible)
        XCTAssertEqual(review.subtitle, "2 review threads, 1 unresolved, 1 resolved")
        XCTAssertEqual(review.badgeLabel, "2 threads")
        XCTAssertEqual(unresolved.locationLabel, "Sources/App.swift:42")
        XCTAssertEqual(resolved.locationLabel, "Tests/AppTests.swift:16-18")
        XCTAssertEqual(unresolved.statusLabel, "Unresolved")
        XCTAssertEqual(resolved.statusLabel, "Resolved · outdated")
        XCTAssertEqual(unresolved.summaryText, "Please extract this helper. Thanks.")
        XCTAssertEqual(unresolved.authorLabel, "reviewer")
        XCTAssertEqual(unresolved.replyDraft, "/pr review-reply 123 11 ")
        XCTAssertEqual(unresolved.replyTarget?.commentID, 11)
        XCTAssertEqual(unresolved.replyTarget?.threadID, "PRRT_one")
        XCTAssertEqual(unresolved.replyTarget?.selector, "123")
        XCTAssertEqual(unresolved.replyRequest(body: "  Looks good now.  ")?.body, "Looks good now.")
        XCTAssertNil(unresolved.replyRequest(body: "  "))
        XCTAssertEqual(unresolved.actions.first?.kind, .resolve)
        XCTAssertEqual(unresolved.actions.first?.selector, "123")
        XCTAssertEqual(resolved.actions.first?.kind, .unresolve)
    }

    func testReviewSurfaceSummarizesPullRequestReviewDraft() {
        let approveDraft = WorkspacePullRequestReviewDraftSurface()
        let commentDraft = WorkspacePullRequestReviewDraftSurface(action: .comment, selector: "123")
        let requestChangesDraft = WorkspacePullRequestReviewDraftSurface(
            action: .requestChanges,
            body: "Please add tests."
        )

        let review = WorkspaceReviewSurface(pullRequestReviewDraft: commentDraft)

        XCTAssertTrue(review.isVisible)
        XCTAssertEqual(review.title, "Review pull request")
        XCTAssertEqual(review.subtitle, "Submit comment review through GitHub CLI")
        XCTAssertEqual(review.badgeLabel, "review draft")
        XCTAssertTrue(approveDraft.canSubmit)
        XCTAssertFalse(commentDraft.canSubmit)
        XCTAssertTrue(requestChangesDraft.canSubmit)
        XCTAssertEqual(commentDraft.normalizedSelector, "123")
        XCTAssertEqual(requestChangesDraft.normalizedBody, "Please add tests.")
        XCTAssertEqual(WorkspacePullRequestReviewActionKind.allCases.map(\.title), [
            "Approve",
            "Comment",
            "Request changes"
        ])
    }

    func testPullRequestReviewDraftCollectsInlineCommentsFromDiffLines() {
        let lineComment = WorkspaceReviewCommentSurface(comment: WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 42,
            lineKind: .insertion,
            text: "Cover this new branch."
        ))
        let rangeComment = WorkspaceReviewCommentSurface(comment: WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 50,
            endLineNumber: 52,
            lineKind: .deletion,
            text: "This deletion needs explanation."
        ))
        let fileComment = WorkspaceReviewCommentSurface(comment: WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            text: "File-level note stays local."
        ))
        let review = WorkspaceReviewSurface(files: [
            WorkspaceReviewFileSurface(
                path: "Sources/App.swift",
                insertions: 2,
                deletions: 1,
                hunks: 1,
                hunkItems: [
                    WorkspaceReviewHunkSurface(
                        id: "hunk-1",
                        path: "Sources/App.swift",
                        header: "@@ -40,12 +40,12 @@",
                        insertions: 1,
                        deletions: 1,
                        patch: "@@ -40,12 +40,12 @@",
                        lines: [
                            WorkspaceReviewLineSurface(
                                id: "line-42",
                                path: "Sources/App.swift",
                                hunkID: "hunk-1",
                                oldLineNumber: nil,
                                newLineNumber: 42,
                                kind: .insertion,
                                content: "newBranch()",
                                comments: [lineComment]
                            ),
                            WorkspaceReviewLineSurface(
                                id: "line-52",
                                path: "Sources/App.swift",
                                hunkID: "hunk-1",
                                oldLineNumber: 52,
                                newLineNumber: nil,
                                kind: .deletion,
                                content: "oldBranch()",
                                comments: [rangeComment]
                            )
                        ]
                    )
                ],
                comments: [fileComment]
            )
        ])

        let comments = WorkspacePullRequestReviewDraftCommentSurface.collect(from: review)

        XCTAssertEqual(comments.map(\.locationLabel), ["Sources/App.swift:42", "Sources/App.swift:50-52"])
        XCTAssertEqual(comments.map(\.side), ["RIGHT", "LEFT"])
        XCTAssertEqual(comments.map(\.body), ["Cover this new branch.", "This deletion needs explanation."])
        XCTAssertEqual(comments.map(\.isIncluded), [true, true])
    }

    func testPullRequestReviewDraftTracksSelectedInlineComments() throws {
        let skippedID = UUID()
        var draft = WorkspacePullRequestReviewDraftSurface(inlineComments: [
            WorkspacePullRequestReviewDraftCommentSurface(
                path: "Sources/App.swift",
                line: 42,
                body: "Keep this note."
            ),
            WorkspacePullRequestReviewDraftCommentSurface(
                id: skippedID,
                path: "Sources/App.swift",
                line: 50,
                body: "Skip this note."
            )
        ])

        draft.setInlineComment(id: skippedID, isIncluded: false)
        draft.updateInlineComment(id: draft.inlineComments[0].id, body: "  Keep this edited note.  ")

        XCTAssertEqual(draft.inlineCommentCount, 2)
        XCTAssertEqual(draft.selectedInlineCommentCount, 1)
        XCTAssertEqual(draft.selectedInlineComments.map(\.body), ["  Keep this edited note.  "])
        XCTAssertEqual(draft.selectedInlineComments.map(\.normalizedBody), ["Keep this edited note."])
        XCTAssertEqual(draft.subtitle, "Submit approve review with 1 of 2 inline notes")
        XCTAssertEqual(draft.submitSummary.status, .ready)
        XCTAssertEqual(draft.submitSummary.title, "Ready to submit")
        XCTAssertEqual(draft.submitSummary.detail, "Approve review for current pull request")
        XCTAssertEqual(draft.submitSummary.items, [
            "Action: Approve",
            "Target: current pull request",
            "Body: optional",
            "Inline notes: 1 selected, 1 skipped"
        ])
        XCTAssertTrue(draft.canSubmit)

        draft.updateInlineComment(id: draft.inlineComments[0].id, body: "  ")
        XCTAssertEqual(draft.invalidSelectedInlineComments.map(\.locationLabel), ["Sources/App.swift:42"])
        XCTAssertEqual(draft.submitSummary.status, .blocked)
        XCTAssertEqual(draft.submitSummary.title, "Needs attention")
        XCTAssertEqual(draft.submitSummary.detail, "Resolve required fields before submitting")
        XCTAssertEqual(draft.submitSummary.items, [
            "Action: Approve",
            "Target: current pull request",
            "Body: optional",
            "Inline notes: 1 selected, 1 skipped, 1 missing text",
            "1 selected inline note needs text"
        ])
        XCTAssertFalse(draft.canSubmit)

        draft.setInlineComment(id: draft.inlineComments[0].id, isIncluded: false)
        XCTAssertTrue(draft.canSubmit)

        draft.includeInlineComments = false
        XCTAssertTrue(draft.selectedInlineComments.isEmpty)
        XCTAssertEqual(draft.subtitle, "Submit approve review without inline notes")
        XCTAssertEqual(draft.submitSummary.items.last, "Inline notes: skipped 2")

        let encodedLegacyComment = """
        {
          "id": "\(skippedID.uuidString)",
          "path": "Sources/App.swift",
          "line": 50,
          "side": "RIGHT",
          "body": "Legacy draft note."
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(
            WorkspacePullRequestReviewDraftCommentSurface.self,
            from: encodedLegacyComment
        )
        XCTAssertTrue(decoded.isIncluded)
    }

    func testReviewFileAndHunkSurfacesExposeLabelsAndActions() {
        let hunk = WorkspaceReviewHunkSurface(
            id: "hunk-1",
            path: "Sources/App.swift",
            header: "@@ -1,2 +1,3 @@",
            insertions: 2,
            deletions: 1,
            patch: "@@ -1,2 +1,3 @@\n-old\n+new\n+line\n"
        )
        let file = WorkspaceReviewFileSurface(
            path: "Sources/App.swift",
            insertions: 2,
            deletions: 1,
            hunks: 1,
            isBinary: true,
            hunkItems: [hunk]
        )

        XCTAssertEqual(file.id, "Sources/App.swift")
        XCTAssertEqual(file.changeLabel, "+2 · -1 · 1 hunk · binary")
        XCTAssertEqual(file.actions.map(\.kind), [.stage, .restore])
        XCTAssertEqual(file.actions.map(\.id), [
            "stage:Sources/App.swift:file",
            "restore:Sources/App.swift:file"
        ])
        XCTAssertEqual(file.actions.map(\.kind.title), ["Stage", "Restore"])
        XCTAssertEqual(file.actions.map(\.kind.systemImage), [
            "plus.rectangle.on.folder",
            "arrow.uturn.backward"
        ])
        XCTAssertEqual(hunk.changeLabel, "+2 · -1")
        XCTAssertEqual(hunk.actions.map(\.id), [
            "stage_hunk:Sources/App.swift:hunk-1",
            "restore_hunk:Sources/App.swift:hunk-1"
        ])
        XCTAssertEqual(hunk.actions[0].patch, hunk.patch)
    }

    func testReviewLinesExposeMarkersAndDisplayLabels() {
        let context = WorkspaceReviewLineSurface(
            id: "line-context",
            path: "Sources/App.swift",
            hunkID: "hunk-1",
            oldLineNumber: 10,
            newLineNumber: 10,
            kind: .context,
            content: "let value = 1"
        )
        let insertion = WorkspaceReviewLineSurface(
            id: "line-insertion",
            path: "Sources/App.swift",
            hunkID: "hunk-1",
            oldLineNumber: nil,
            newLineNumber: 11,
            kind: .insertion,
            content: "let added = true"
        )
        let deletion = WorkspaceReviewLineSurface(
            id: "line-deletion",
            path: "Sources/App.swift",
            hunkID: "hunk-1",
            oldLineNumber: 12,
            newLineNumber: nil,
            kind: .deletion,
            content: "let removed = true"
        )

        XCTAssertEqual(context.kind.marker, " ")
        XCTAssertEqual(insertion.kind.marker, "+")
        XCTAssertEqual(deletion.kind.marker, "-")
        XCTAssertEqual(context.lineLabel, "10")
        XCTAssertEqual(insertion.lineLabel, "11")
        XCTAssertEqual(deletion.lineLabel, "12")
        XCTAssertEqual(context.displayLineNumber, 10)
        XCTAssertEqual(insertion.displayLineNumber, 11)
        XCTAssertEqual(deletion.displayLineNumber, 12)
    }

    func testReviewCommentSurfaceMapsLineRangeLabels() {
        let createdAt = Date(timeIntervalSince1970: 42)
        let fileComment = WorkspaceReviewCommentSurface(
            comment: WorkspaceReviewCommentState(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                path: "Sources/App.swift",
                text: "File-level note",
                createdAt: createdAt
            )
        )
        let lineComment = WorkspaceReviewCommentSurface(
            comment: WorkspaceReviewCommentState(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                path: "Sources/App.swift",
                lineNumber: 12,
                lineKind: .insertion,
                text: "Line note",
                createdAt: createdAt
            )
        )
        let rangeComment = WorkspaceReviewCommentSurface(
            comment: WorkspaceReviewCommentState(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
                path: "Sources/App.swift",
                lineNumber: 12,
                endLineNumber: 14,
                lineKind: .context,
                text: "Range note",
                createdAt: createdAt
            )
        )

        XCTAssertNil(fileComment.lineRangeLabel)
        XCTAssertEqual(lineComment.lineRangeLabel, "Line 12")
        XCTAssertEqual(rangeComment.lineRangeLabel, "Lines 12-14")
        XCTAssertEqual(rangeComment.createdAt, createdAt)
        XCTAssertEqual(rangeComment.lineKind, .context)
    }
}
