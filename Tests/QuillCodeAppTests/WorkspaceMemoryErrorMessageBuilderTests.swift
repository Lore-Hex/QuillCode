import XCTest
@testable import QuillCodeApp

final class WorkspaceMemoryErrorMessageBuilderTests: XCTestCase {
    func testUserFacingMessagePrefersLocalizedErrorDescription() {
        XCTAssertEqual(
            WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: MemoryNoteDeleteError.notFound),
            "Memory was not found. It may already have been removed."
        )
        XCTAssertEqual(
            WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: MemoryNoteWriteError.unavailable),
            "Memory saving is unavailable in this runtime."
        )
    }

    func testUserFacingMessageFallsBackToErrorDescription() {
        XCTAssertEqual(
            WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: PlainMemoryError()),
            "PlainMemoryError()"
        )
    }

    private struct PlainMemoryError: Error {}
}
