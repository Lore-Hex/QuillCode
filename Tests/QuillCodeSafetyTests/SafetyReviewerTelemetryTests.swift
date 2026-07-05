import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

final class SafetyReviewerTelemetryTests: SafetyPolicyTestCase {
    func testAutoReviewerRecordsPrimaryModelTelemetry() async {
        let client = RecordingSafetyModelClient(outcomes: [
            "glm-5.2": .success(#"{"verdict":"approve","rationale":"looks safe","userIntentMatched":true}"#)
        ])
        let review = await reviewer(client: client).review(context(command: "whoami", userMessage: "run whoami"))

        XCTAssertEqual(review.verdict, .approve)
        XCTAssertEqual(review.reviewerModel, "glm-5.2")
        XCTAssertEqual(review.reviewTelemetry?.source, .primaryModel)
        XCTAssertEqual(review.reviewTelemetry?.reviewerModel, "glm-5.2")
        XCTAssertEqual(review.reviewTelemetry?.attemptedModels, ["glm-5.2"])
        XCTAssertNil(review.reviewTelemetry?.fallbackReason)
        let requestedModels = await client.requestedModels()
        XCTAssertEqual(requestedModels, ["glm-5.2"])
    }

    func testAutoReviewerRecordsFallbackModelTelemetry() async {
        let client = RecordingSafetyModelClient(outcomes: [
            "glm-5.2": .failure("primary unavailable"),
            "kimi-k2.6": .success(#"{"verdict":"approve","rationale":"fallback approved","userIntentMatched":true}"#)
        ])
        let review = await reviewer(client: client).review(context(command: "whoami", userMessage: "run whoami"))

        XCTAssertEqual(review.verdict, .approve)
        XCTAssertEqual(review.reviewerModel, "kimi-k2.6")
        XCTAssertEqual(review.reviewTelemetry?.source, .fallbackModel)
        XCTAssertEqual(review.reviewTelemetry?.reviewerModel, "kimi-k2.6")
        XCTAssertEqual(review.reviewTelemetry?.attemptedModels, ["glm-5.2", "kimi-k2.6"])
        XCTAssertEqual(review.reviewTelemetry?.fallbackReason, .primaryModelFailed)
        XCTAssertEqual(review.reviewTelemetry?.errorSummary, "primary unavailable")
        let requestedModels = await client.requestedModels()
        XCTAssertEqual(requestedModels, ["glm-5.2", "kimi-k2.6"])
    }

    func testAutoReviewerRecordsStaticFallbackWhenAllModelsFail() async {
        let client = RecordingSafetyModelClient(outcomes: [
            "glm-5.2": .failure("primary unavailable"),
            "kimi-k2.6": .failure("fallback unavailable")
        ])
        let review = await reviewer(client: client).review(context(command: "whoami", userMessage: "run whoami"))

        XCTAssertEqual(review.verdict, .approve)
        XCTAssertNil(review.reviewerModel)
        XCTAssertEqual(review.reviewTelemetry?.source, .staticPolicy)
        XCTAssertEqual(review.reviewTelemetry?.attemptedModels, ["glm-5.2", "kimi-k2.6"])
        XCTAssertEqual(review.reviewTelemetry?.fallbackReason, .allModelsFailed)
        XCTAssertEqual(
            review.reviewTelemetry?.errorSummary,
            "primary: primary unavailable; fallback: fallback unavailable"
        )
    }

    func testAutoReviewerRecordsMissingClientTelemetry() async {
        let review = await AutoSafetyReviewer().review(context(command: "whoami", userMessage: "run whoami"))

        XCTAssertEqual(review.verdict, .approve)
        XCTAssertEqual(review.reviewTelemetry?.source, .staticPolicy)
        XCTAssertEqual(review.reviewTelemetry?.fallbackReason, .missingReviewerClient)
        XCTAssertEqual(review.reviewTelemetry?.attemptedModels, [])
    }

    func testAutoReviewerPromptDefinesStrictVerdictBoundaries() {
        let prompt = AutoSafetyReviewer.prompt(for: context(
            command: "ls -la && cat ~/.ssh/id_rsa",
            userMessage: "List the files here."
        ))

        XCTAssertTrue(prompt.contains("Return only JSON"))
        XCTAssertTrue(prompt.contains("- approve:"))
        XCTAssertTrue(prompt.contains("- clarify: required arguments are missing or empty"))
        XCTAssertTrue(prompt.contains("- deny: the call exfiltrates credentials"))
        XCTAssertTrue(prompt.contains("adds unrelated extra actions"))
        XCTAssertTrue(prompt.contains("shell command chains unrelated work"))
    }

    private func reviewer(client: SafetyModelClient) -> AutoSafetyReviewer {
        AutoSafetyReviewer(
            client: client,
            primaryModel: "glm-5.2",
            fallbackModel: "kimi-k2.6"
        )
    }

    private func context(command: String, userMessage: String) -> SafetyContext {
        SafetyContext(
            mode: .auto,
            userMessage: userMessage,
            toolCall: ToolCall(name: shellRun.name, argumentsJSON: shellArgumentsJSON(command)),
            toolDefinition: shellRun,
            recentMessages: [.init(role: .user, content: userMessage)]
        )
    }
}

private actor RecordingSafetyModelClient: SafetyModelClient {
    private var outcomes: [String: SafetyModelOutcome]
    private var models: [String] = []

    init(outcomes: [String: SafetyModelOutcome]) {
        self.outcomes = outcomes
    }

    func review(prompt: String, model: String) async throws -> String {
        _ = prompt
        models.append(model)
        switch outcomes[model] ?? .failure("missing scripted outcome for \(model)") {
        case .success(let json):
            return json
        case .failure(let message):
            throw SafetyModelStubError(message)
        }
    }

    func requestedModels() -> [String] {
        models
    }
}

private enum SafetyModelOutcome: Sendable {
    case success(String)
    case failure(String)
}

private struct SafetyModelStubError: Error, CustomStringConvertible, Sendable {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
