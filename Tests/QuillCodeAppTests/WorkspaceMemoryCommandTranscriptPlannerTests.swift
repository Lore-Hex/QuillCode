import XCTest
@testable import QuillCodeApp

final class WorkspaceMemoryCommandTranscriptPlannerTests: XCTestCase {
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
