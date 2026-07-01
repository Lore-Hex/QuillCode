import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

final class RuntimeFactoryRetryWiringTests: XCTestCase {
    /// The real TrustedRouter runtime must wrap its model client in the retry decorator, so an
    /// unattended run survives a transient blip. Constructed with an injected API key (no network).
    func testTrustedRouterRuntimeWrapsClientInRetryDecorator() {
        let factory = QuillCodeRuntimeFactory(environment: ["QUILLCODE_API_KEY": "test-key"])
        let runtime = factory.makeRuntime(config: AppConfig())
        XCTAssertEqual(runtime.mode, .trustedRouter)
        XCTAssertTrue(
            runtime.runner.llm is RetryingLLMClient<TrustedRouterLLMClient>,
            "expected the runner's LLM client to be retry-wrapped, got \(type(of: runtime.runner.llm))"
        )
    }

    /// The mock runtime (no key / forced mock) is unaffected — it must NOT be retry-wrapped.
    func testMockRuntimeIsNotRetryWrapped() {
        let factory = QuillCodeRuntimeFactory(environment: ["QUILLCODE_USE_MOCK_LLM": "1"])
        let runtime = factory.makeRuntime(config: AppConfig())
        XCTAssertEqual(runtime.mode, .mock)
        XCTAssertFalse(runtime.runner.llm is RetryingLLMClient<TrustedRouterLLMClient>)
    }
}
