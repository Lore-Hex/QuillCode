import XCTest
@testable import QuillCodeCore

final class ThreadRuntimeContextTests: XCTestCase {
    func testSideConversationContextIsSessionOnlyAcrossCoding() throws {
        let parentID = UUID()
        let thread = ChatThread(
            title: "Side",
            runtimeContext: .sideConversation(parentThreadID: parentID)
        )

        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(ChatThread.self, from: data)

        XCTAssertTrue(thread.runtimeContext.isEphemeral)
        XCTAssertEqual(thread.runtimeContext.sideConversationParentThreadID, parentID)
        XCTAssertEqual(decoded.runtimeContext, .standard)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("runtimeContext"))
    }
}
