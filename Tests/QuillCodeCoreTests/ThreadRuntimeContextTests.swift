import XCTest
@testable import QuillCodeCore

final class ThreadRuntimeContextTests: XCTestCase {
    func testIncognitoContextIsEphemeralAndSessionOnlyAcrossCoding() throws {
        // Incognito's whole promise is "never saved": the context must count as ephemeral (which
        // gates every persistence path) and must not survive an encode/decode round trip — a decoded
        // incognito thread degrades to .standard exactly like a side conversation does.
        let thread = ChatThread(title: "Incognito", runtimeContext: .incognito)

        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(ChatThread.self, from: data)

        XCTAssertTrue(thread.runtimeContext.isEphemeral)
        XCTAssertTrue(thread.runtimeContext.isIncognito)
        XCTAssertNil(thread.runtimeContext.sideConversationParentThreadID)
        XCTAssertFalse(ThreadRuntimeContext.standard.isIncognito)
        XCTAssertFalse(ThreadRuntimeContext.sideConversation(parentThreadID: UUID()).isIncognito)
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
