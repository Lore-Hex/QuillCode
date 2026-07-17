import XCTest
@testable import QuillCodeCore

final class ThreadRuntimeContextTests: XCTestCase {
    func testConfidentialContextIsEphemeralAndSessionOnlyAcrossCoding() throws {
        // Confidential's whole promise is "never saved": the context must count as ephemeral (which
        // gates every persistence path) and must not survive an encode/decode round trip — a decoded
        // confidential thread degrades to .standard exactly like a side conversation does.
        let thread = ChatThread(title: "Confidential", runtimeContext: .confidential)

        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(ChatThread.self, from: data)

        XCTAssertTrue(thread.runtimeContext.isEphemeral)
        XCTAssertTrue(thread.runtimeContext.isConfidential)
        XCTAssertNil(thread.runtimeContext.sideConversationParentThreadID)
        XCTAssertFalse(ThreadRuntimeContext.standard.isConfidential)
        XCTAssertFalse(ThreadRuntimeContext.sideConversation(parentThreadID: UUID()).isConfidential)
        XCTAssertEqual(decoded.runtimeContext, .standard)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("runtimeContext"))
    }

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
