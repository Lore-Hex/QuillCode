import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class TrustedRouterPromptCachingTests: XCTestCase {
    private let anthropicModel = "anthropic/claude-sonnet-4.5"

    // MARK: - Helpers

    private func message(_ role: String, _ content: Any) -> [String: Any] {
        ["role": role, "content": content]
    }

    /// Decodes the exact request body the client would send, so assertions run over the
    /// serialized JSON rather than intermediate Swift values.
    private func serializedBody(
        model: String,
        messages: [[String: Any]],
        policy: TrustedRouterPromptCachingPolicy = .automatic
    ) throws -> [String: Any] {
        let data = try TrustedRouterLLMClient.chatCompletionBody(
            model: model,
            messages: messages,
            promptCachingPolicy: policy
        )
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func bodyMessages(_ body: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(body["messages"] as? [[String: Any]])
    }

    /// The indexes of messages carrying a cache breakpoint, and the shape check for each:
    /// content must be exactly one text part with `cache_control: {type: ephemeral}`.
    private func breakpointIndexes(in messages: [[String: Any]]) -> [Int] {
        messages.indices.filter { index in
            guard let parts = messages[index]["content"] as? [[String: Any]] else { return false }
            return parts.contains { ($0["cache_control"] as? [String: String]) != nil }
        }
    }

    private func assertEphemeralTextBreakpoint(
        _ message: [String: Any],
        originalText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let parts = try XCTUnwrap(message["content"] as? [[String: Any]], file: file, line: line)
        XCTAssertEqual(parts.count, 1, "breakpoint content must stay a single text part", file: file, line: line)
        XCTAssertEqual(parts[0]["type"] as? String, "text", file: file, line: line)
        XCTAssertEqual(parts[0]["text"] as? String, originalText, "text must be preserved verbatim", file: file, line: line)
        XCTAssertEqual(parts[0]["cache_control"] as? [String: String], ["type": "ephemeral"], file: file, line: line)
    }

    // MARK: - Provider-family gating

    func testOnlyAnthropicFamilyModelsSupportCacheBreakpoints() {
        XCTAssertTrue(TrustedRouterPromptCaching.supportsCacheBreakpoints(modelID: "anthropic/claude-sonnet-4.5"))
        XCTAssertTrue(TrustedRouterPromptCaching.supportsCacheBreakpoints(modelID: "anthropic/claude-opus-4.8"))
        XCTAssertTrue(
            TrustedRouterPromptCaching.supportsCacheBreakpoints(modelID: "Anthropic/claude-haiku-4.5"),
            "provider-family match must be case-insensitive"
        )

        for modelID in [
            TrustedRouterDefaults.fastModel,
            TrustedRouterDefaults.synthModel,
            TrustedRouterDefaults.socratesModel,
            TrustedRouterDefaults.safetyPrimaryCatalogModel,
            TrustedRouterDefaults.safetyFallbackCatalogModel,
            "gemini/gemini-2.5-pro",
            "openai/gpt-5.2",
            "claude-sonnet-4.5"  // no provider prefix -> router-native, not provably Anthropic
        ] {
            XCTAssertFalse(
                TrustedRouterPromptCaching.supportsCacheBreakpoints(modelID: modelID),
                "\(modelID) must not receive cache_control"
            )
        }
    }

    // MARK: - Placement

    func testBreakpointLandsOnLatestUserMessageAndCoversNothingElse() throws {
        let messages = [
            message("system", "base system prompt with tool definitions"),
            message("system", "project instructions"),
            message("user", "first request"),
            message("assistant", "first answer"),
            message("user", "second request")
        ]

        let sent = try bodyMessages(serializedBody(model: anthropicModel, messages: messages))

        XCTAssertEqual(breakpointIndexes(in: sent), [4], "exactly one breakpoint, on the LAST user message")
        try assertEphemeralTextBreakpoint(sent[4], originalText: "second request")
        for index in [0, 1, 2, 3] {
            XCTAssertEqual(
                sent[index]["content"] as? String,
                messages[index]["content"] as? String,
                "message \(index) must be sent as the original plain string"
            )
        }
    }

    func testToolLoopAddsSecondBreakpointOnFinalAssistantMessage() throws {
        let messages = [
            message("system", "base system prompt"),
            message("user", "run the tests"),
            message("assistant", "{\"type\":\"tool\",\"name\":\"host.shell.run\"}"),
            message("assistant", "Tool output: 12 tests passed")
        ]

        let sent = try bodyMessages(serializedBody(model: anthropicModel, messages: messages))

        XCTAssertEqual(
            breakpointIndexes(in: sent),
            [1, 3],
            "latest user message plus the final tool-feedback message, nothing else"
        )
        try assertEphemeralTextBreakpoint(sent[1], originalText: "run the tests")
        try assertEphemeralTextBreakpoint(sent[3], originalText: "Tool output: 12 tests passed")
        XCTAssertEqual(sent[2]["content"] as? String, "{\"type\":\"tool\",\"name\":\"host.shell.run\"}")
    }

    /// The TrustedRouter gateway `str()`-concatenates system message content into Anthropic's
    /// top-level `system` string, so array-shaped system content would be corrupted into a
    /// Python repr. System messages must therefore never be annotated — under any layout.
    func testSystemMessagesAreNeverAnnotated() throws {
        let onlySystem = [
            message("system", "base system prompt"),
            message("system", "project instructions")
        ]
        let sent = try bodyMessages(serializedBody(model: anthropicModel, messages: onlySystem))
        XCTAssertEqual(breakpointIndexes(in: sent), [])
        for (index, original) in onlySystem.enumerated() {
            XCTAssertEqual(sent[index]["content"] as? String, original["content"] as? String)
        }
    }

    // MARK: - Turn-over-turn stability

    /// Breakpoints must move only FORWARD as the conversation grows: every message that was in
    /// the previous request's cached prefix is re-sent byte-identically (as a plain string), so
    /// the prior turn's cache entry still matches and the new breakpoint extends it.
    func testGrowingHistoryKeepsPreviousPrefixIdenticalAndAdvancesTheBreakpoint() throws {
        let turnOne = [
            message("system", "base system prompt"),
            message("user", "first request")
        ]
        let turnTwo = turnOne + [
            message("assistant", "first answer"),
            message("user", "second request")
        ]

        let sentOne = try bodyMessages(serializedBody(model: anthropicModel, messages: turnOne))
        let sentTwo = try bodyMessages(serializedBody(model: anthropicModel, messages: turnTwo))

        XCTAssertEqual(breakpointIndexes(in: sentOne), [1])
        XCTAssertEqual(breakpointIndexes(in: sentTwo), [3], "breakpoint advances to the new latest user message")

        // Turn two re-sends turn one's messages exactly as turn one's UNANNOTATED form.
        // (Anthropic normalizes a plain string to a single text block, so the prefix hash
        // matches the entry the turn-one breakpoint created.)
        for index in turnOne.indices {
            XCTAssertEqual(sentTwo[index]["role"] as? String, turnOne[index]["role"] as? String)
            XCTAssertEqual(
                sentTwo[index]["content"] as? String,
                turnOne[index]["content"] as? String,
                "previously cached message \(index) must be re-sent as the original plain string"
            )
        }
    }

    /// Within one turn's tool loop the latest user message does not change, so its breakpoint
    /// must stay on the same element while the trailing breakpoint follows the newest feedback.
    func testIntraTurnToolLoopKeepsUserBreakpointStable() throws {
        var messages = [
            message("system", "base system prompt"),
            message("user", "run the tests")
        ]
        let userIndex = 1

        for step in 0..<3 {
            messages.append(message("assistant", "Tool output: step \(step)"))
            let sent = try bodyMessages(serializedBody(model: anthropicModel, messages: messages))
            XCTAssertEqual(
                breakpointIndexes(in: sent),
                [userIndex, messages.count - 1],
                "step \(step): stable user breakpoint plus trailing feedback breakpoint"
            )
        }
    }

    // MARK: - Non-Anthropic routes stay byte-identical

    func testNonAnthropicRequestsAreExactlyTheUncachedRequest() throws {
        let messages = [
            message("system", "base system prompt"),
            message("user", "run the tests"),
            message("assistant", "Tool output: ok")
        ]

        for modelID in [
            TrustedRouterDefaults.fastModel,
            TrustedRouterDefaults.synthModel,
            "z-ai/glm-5.2",
            "gemini/gemini-2.5-pro"
        ] {
            let automatic = try TrustedRouterLLMClient.chatCompletionBody(
                model: modelID,
                messages: messages,
                promptCachingPolicy: .automatic
            )
            let disabled = try TrustedRouterLLMClient.chatCompletionBody(
                model: modelID,
                messages: messages,
                promptCachingPolicy: .disabled
            )
            let automaticObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: automatic) as? NSDictionary)
            let disabledObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: disabled) as? NSDictionary)
            XCTAssertEqual(automaticObject, disabledObject, "\(modelID): automatic policy must not alter the request")
            XCTAssertFalse(
                String(decoding: automatic, as: UTF8.self).contains("cache_control"),
                "\(modelID) must never see cache_control"
            )
        }
    }

    func testDisabledPolicySendsAnthropicRequestUnannotated() throws {
        let messages = [
            message("system", "base system prompt"),
            message("user", "run the tests")
        ]
        let body = try serializedBody(model: anthropicModel, messages: messages, policy: .disabled)
        XCTAssertEqual(breakpointIndexes(in: try bodyMessages(body)), [])
        let sent = try bodyMessages(body)
        XCTAssertEqual(sent[1]["content"] as? String, "run the tests")
    }

    // MARK: - Request envelope regression

    func testAnnotationLeavesTheRestOfTheRequestEnvelopeUntouched() throws {
        let body = try serializedBody(
            model: anthropicModel,
            messages: [message("system", "s"), message("user", "u")]
        )
        XCTAssertEqual(body["model"] as? String, anthropicModel)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["stream_options"] as? [String: Bool], ["include_usage": true])
        XCTAssertEqual(body["response_format"] as? [String: String], ["type": "json_object"])
    }

    // MARK: - Robustness

    func testWhitespaceOnlyAndNonStringContentAreLeftUntouched() throws {
        // Anthropic rejects blank text blocks, and content that is already an array must never
        // be re-wrapped — skip annotation entirely rather than risk a malformed request.
        let alreadyArray: [[String: Any]] = [["type": "text", "text": "pre-shaped"]]
        let messages: [[String: Any]] = [
            message("system", "base system prompt"),
            message("user", "   \n"),
            message("assistant", alreadyArray),
            message("user", 42)
        ]

        let sent = try bodyMessages(serializedBody(model: anthropicModel, messages: messages))

        XCTAssertEqual(breakpointIndexes(in: sent), [])
        XCTAssertEqual(sent[1]["content"] as? String, "   \n")
        let preserved = try XCTUnwrap(sent[2]["content"] as? [[String: Any]])
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(preserved[0]["text"] as? String, "pre-shaped")
        XCTAssertNil(preserved[0]["cache_control"], "pre-shaped array content must not be annotated")
        XCTAssertEqual(sent[3]["content"] as? Int, 42)
    }

    func testEmptyMessageListStaysEmpty() {
        XCTAssertTrue(TrustedRouterPromptCaching.annotated([]).isEmpty)
        XCTAssertEqual(TrustedRouterPromptCaching.breakpointIndexes([]), [])
    }

    func testClientDefaultsToAutomaticPolicyAndModelOverrideKeepsIt() {
        let client = TrustedRouterLLMClient(promptCachingPolicy: .disabled)
        XCTAssertEqual(client.promptCachingPolicy, .disabled)
        XCTAssertEqual(TrustedRouterLLMClient().promptCachingPolicy, .automatic)
        XCTAssertEqual(
            TrustedRouterLLMClient().overridingModel("anthropic/claude-haiku-4.5").promptCachingPolicy,
            .automatic,
            "retargeting the model must keep the caching policy"
        )
    }
}
