import Foundation
@testable import QuillCodeCLI
import QuillCodeCore
import XCTest

final class MCPServerProgressProjectorTests: XCTestCase {
    func testAssistantDeltaTruncationPreservesCompleteUnicodeCharacters() throws {
        let baseline = ChatThread()
        var snapshot = baseline
        snapshot.messages = [ChatMessage(
            role: .assistant,
            content: String(repeating: "a", count: 32 * 1_024 - 1) + "🙂tail"
        )]
        var projector = MCPServerProgressProjector(
            cwd: URL(fileURLWithPath: "/workspace"),
            baseline: baseline
        )

        let event = try XCTUnwrap(projector.project(snapshot).first)
        let delta = try XCTUnwrap(event.message.objectValue?["delta"]?.stringValue)

        XCTAssertFalse(delta.contains("\u{FFFD}"))
        XCTAssertFalse(delta.contains("🙂"))
        XCTAssertTrue(delta.hasSuffix("\n[output truncated]"))
    }
}
