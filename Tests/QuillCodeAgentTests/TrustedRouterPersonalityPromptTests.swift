import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class TrustedRouterPersonalityPromptTests: XCTestCase {
    func testFriendlyPersonalityAddsOnlyFriendlyGuidance() {
        let systemMessages = systemMessages(for: .friendly)

        XCTAssertEqual(systemMessages.filter { $0.contains("Communication style: Friendly") }.count, 1)
        XCTAssertFalse(systemMessages.contains { $0.contains("Communication style: Pragmatic") })
    }

    func testPragmaticPersonalityAddsOnlyPragmaticGuidance() {
        let systemMessages = systemMessages(for: .pragmatic)

        XCTAssertEqual(systemMessages.filter { $0.contains("Communication style: Pragmatic") }.count, 1)
        XCTAssertFalse(systemMessages.contains { $0.contains("Communication style: Friendly") })
    }

    func testNonePersonalityAddsNoStyleGuidance() {
        let systemMessages = systemMessages(for: .none)

        XCTAssertFalse(systemMessages.contains { $0.contains("Communication style:") })
    }

    private func systemMessages(for personality: QuillCodePersonality) -> [String] {
        TrustedRouterPromptBuilder().messages(
            thread: ChatThread(personality: personality),
            userMessage: "Review this change",
            tools: []
        ).compactMap { message in
            guard message["role"] as? String == "system" else { return nil }
            return message["content"] as? String
        }
    }
}
