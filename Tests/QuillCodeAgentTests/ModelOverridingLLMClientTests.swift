import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class ModelOverridingLLMClientTests: XCTestCase {
    func testTrustedRouterClientOverrideRetargetsOnlyTheModel() {
        let base = TrustedRouterLLMClient(
            apiKeyOverride: "sk-test",
            model: "acme/flagship",
            baseURL: "https://api.trustedrouter.test/v1"
        )

        let overridden = base.overridingModel("acme/tiny-mini")

        XCTAssertEqual(overridden.model, "acme/tiny-mini")
        XCTAssertEqual(overridden.apiKeyOverride, "sk-test")
        XCTAssertEqual(overridden.baseURL, "https://api.trustedrouter.test/v1")
        XCTAssertEqual(base.model, "acme/flagship")
    }

    func testRetryingClientOverrideRetargetsTheWrappedClientAndKeepsRetryPolicy() {
        let policy = RetryBackoffPolicy(maxAttempts: 7)
        let client = RetryingLLMClient(
            base: TrustedRouterLLMClient(model: "acme/flagship"),
            policy: policy
        )

        let overridden = client.overridingModel("acme/tiny-mini")

        XCTAssertEqual(overridden.base.model, "acme/tiny-mini")
        XCTAssertEqual(overridden.policy.maxAttempts, policy.maxAttempts)
        XCTAssertEqual(client.base.model, "acme/flagship")
    }
}
