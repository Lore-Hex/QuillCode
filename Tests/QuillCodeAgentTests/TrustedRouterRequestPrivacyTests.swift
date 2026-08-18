import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class TrustedRouterRequestPrivacyTests: XCTestCase {
    func testStandardRequestDoesNotInjectProviderPolicy() throws {
        let body = try decodedBody(privacy: .standard)

        XCTAssertNil(body["provider"])
    }

    func testConfidentialUSRequestInjectsFailClosedProviderPolicy() throws {
        let provider = try providerPayload(for: .confidential(jurisdiction: .unitedStates))

        XCTAssertEqual(provider["data_collection"] as? String, "deny")
        XCTAssertEqual(provider["min_privacy"] as? String, "confidential")
        XCTAssertEqual(provider["jurisdiction"] as? String, "us")
    }

    func testConfidentialEURequestInjectsFailClosedProviderPolicy() throws {
        let provider = try providerPayload(for: .confidential(jurisdiction: .europeanUnion))

        XCTAssertEqual(provider["data_collection"] as? String, "deny")
        XCTAssertEqual(provider["min_privacy"] as? String, "confidential")
        XCTAssertEqual(provider["jurisdiction"] as? String, "eu")
    }

    private func providerPayload(
        for privacy: TrustedRouterRequestPrivacy
    ) throws -> [String: Any] {
        let body = try decodedBody(privacy: privacy)
        return try XCTUnwrap(body["provider"] as? [String: Any])
    }

    private func decodedBody(
        privacy: TrustedRouterRequestPrivacy
    ) throws -> [String: Any] {
        let data = try TrustedRouterLLMClient.chatCompletionBody(
            model: TrustedRouterDefaults.confidentialModel,
            messages: [["role": "user", "content": "hello"]],
            requestPrivacy: privacy
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
