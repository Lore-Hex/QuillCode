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

    /// The run-loop client keeps prompt caching ON (its prefix repeats across turns), but the
    /// one-shot context-summary/compaction client must be OFF: each summary prompt is unique and
    /// never re-sent, so a breakpoint there could only ever be a cache write with no read — and
    /// the auxiliary-model selector can steer it onto an Anthropic model. Asserts the two clients
    /// carry opposite caching policies. FAILS on revert of the aux-disable wiring.
    func testSummaryClientDisablesPromptCachingWhileRunLoopKeepsItOn() throws {
        let factory = QuillCodeRuntimeFactory(environment: ["QUILLCODE_API_KEY": "test-key"])
        let runtime = factory.makeRuntime(config: AppConfig())

        let runLoop = try XCTUnwrap(runtime.runner.llm as? RetryingLLMClient<TrustedRouterLLMClient>)
        XCTAssertEqual(
            runLoop.base.promptCachingPolicy, .automatic,
            "the run-loop client must keep prompt caching enabled"
        )

        let summaryGenerator = try XCTUnwrap(
            runtime.contextSummaryGenerator as? LLMWorkspaceContextSummaryGenerator
        )
        let summaryClient = try XCTUnwrap(
            summaryGenerator.llm as? RetryingLLMClient<TrustedRouterLLMClient>
        )
        XCTAssertEqual(
            summaryClient.base.promptCachingPolicy, .disabled,
            "one-shot summary/compaction calls must never carry a prompt-cache breakpoint"
        )

        // And retargeting the summary client at an Anthropic aux model must not re-enable it.
        XCTAssertEqual(
            summaryClient.base.overridingModel("anthropic/claude-haiku-4.5").promptCachingPolicy,
            .disabled
        )
    }
}
