import XCTest
@testable import QuillCodeApp

final class WorkspaceMemoryCommandTranscriptPlannerTests: XCTestCase {
    func testMemorySavedTranscriptUsesSharedSummary() {
        let transcript = WorkspaceMemoryCommandTranscriptPlanner.memorySaved(
            userText: "/remember Prefer small reviewable commits",
            noteTitle: "Small Commits"
        )

        XCTAssertEqual(transcript.userText, "/remember Prefer small reviewable commits")
        XCTAssertEqual(transcript.title, "Memory: Small Commits")
        XCTAssertEqual(
            transcript.assistantText,
            "Saved memory: Small Commits. It will be included as background context in future turns."
        )
        XCTAssertEqual(
            WorkspaceMemoryCommandTranscriptPlanner.memorySavedSummary(noteTitle: "Small Commits"),
            "Saved memory: Small Commits"
        )
    }

    func testMemoryNotSavedTranscriptPreservesFailureMessage() {
        XCTAssertEqual(
            WorkspaceMemoryCommandTranscriptPlanner.memoryNotSaved(
                userText: "/remember",
                message: "Nothing to remember."
            ),
            WorkspaceLocalCommandTranscript(
                userText: "/remember",
                assistantText: "Nothing to remember.",
                title: "Memory not saved"
            )
        )
    }

    func testMemoryForgottenTranscriptUsesSharedSummary() {
        let transcript = WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten(
            userText: "Forget memory: Preferences",
            noteTitle: "Preferences"
        )

        XCTAssertEqual(transcript.userText, "Forget memory: Preferences")
        XCTAssertEqual(transcript.title, "Forgot memory: Preferences")
        XCTAssertEqual(
            transcript.assistantText,
            "Forgot memory: Preferences. It will no longer be included as background context."
        )
        XCTAssertEqual(
            WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary(noteTitle: "Preferences"),
            "Forgot memory: Preferences"
        )
    }

    func testMemoryNotDeletedTranscriptPreservesFailureMessage() {
        XCTAssertEqual(
            WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted(
                userText: "Forget memory",
                message: "Memory was not found. It may already have been removed."
            ),
            WorkspaceLocalCommandTranscript(
                userText: "Forget memory",
                assistantText: "Memory was not found. It may already have been removed.",
                title: "Memory not deleted"
            )
        )
    }
}
