import Foundation
import XCTest
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopTranscriptExportCoordinatorTests: XCTestCase {
    func testSuggestedFileNameSanitizesConversationTitle() {
        XCTAssertEqual(
            QuillCodeDesktopTranscriptExportCoordinator.suggestedFileName(for: "Fix /Users/me/project: CI?"),
            "Fix-Users-me-project-CI.md"
        )
        XCTAssertEqual(
            QuillCodeDesktopTranscriptExportCoordinator.suggestedFileName(for: "   "),
            "Conversation.md"
        )
        XCTAssertEqual(
            QuillCodeDesktopTranscriptExportCoordinator.suggestedFileName(for: "Already.md"),
            "Already.md"
        )
    }

    func testBlankMarkdownDoesNotPresentDestination() throws {
        let destination = FakeMarkdownExportDestination(nextURL: URL(fileURLWithPath: "/tmp/ignored.md"))
        let coordinator = QuillCodeDesktopTranscriptExportCoordinator(destination: destination)

        let result = try coordinator.exportConversation(title: "Chat", markdown: "  \n\t")

        XCTAssertNil(result)
        XCTAssertEqual(destination.requests, [])
    }

    func testCancelledDestinationReturnsNil() throws {
        let destination = FakeMarkdownExportDestination(nextURL: nil)
        let coordinator = QuillCodeDesktopTranscriptExportCoordinator(destination: destination)

        let result = try coordinator.exportConversation(title: "Chat", markdown: "## User\n\nHi")

        XCTAssertNil(result)
        XCTAssertEqual(destination.requests.map(\.suggestedFileName), ["Chat.md"])
    }

    func testWritesMarkdownWithSuggestedFileName() throws {
        let url = URL(fileURLWithPath: "/tmp/QuillCode-export.md")
        let destination = FakeMarkdownExportDestination(nextURL: url)
        let coordinator = QuillCodeDesktopTranscriptExportCoordinator(destination: destination)

        let result = try coordinator.exportConversation(title: "Review diff", markdown: "## User\n\nRun tests")

        XCTAssertEqual(result, QuillCodeDesktopTranscriptExportResult(url: url))
        XCTAssertEqual(destination.requests, [
            FakeMarkdownExportDestination.Request(
                markdown: "## User\n\nRun tests",
                suggestedFileName: "Review diff.md"
            )
        ])
    }
}

@MainActor
private final class FakeMarkdownExportDestination: QuillCodeMarkdownExportDestination {
    struct Request: Equatable {
        var markdown: String
        var suggestedFileName: String
    }

    var requests: [Request] = []
    var nextURL: URL?

    init(nextURL: URL?) {
        self.nextURL = nextURL
    }

    func write(markdown: String, suggestedFileName: String) throws -> URL? {
        requests.append(Request(markdown: markdown, suggestedFileName: suggestedFileName))
        return nextURL
    }
}
