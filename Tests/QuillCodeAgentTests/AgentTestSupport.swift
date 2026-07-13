import XCTest
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeAgent

func makeTempDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("QuillCodeAgentTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func initializeGitRepo(at root: URL) throws {
    let result = ShellToolExecutor().run(.init(
        command: "git init && git config user.email test@example.com && git config user.name QuillCodeTests",
        cwd: root
    ))
    XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
}

actor ProgressRecorder {
    private var kinds: [ThreadEventKind] = []
    private var contents: [[String]] = []
    private var snapshots: [[ThreadEvent]] = []

    func record(_ thread: ChatThread) {
        guard let kind = thread.events.last?.kind else { return }
        kinds.append(kind)
        contents.append(thread.messages.map(\.content))
        snapshots.append(thread.events)
    }

    func eventKinds() -> [ThreadEventKind] {
        kinds
    }

    func messageContents() -> [[String]] {
        contents
    }

    func eventSnapshots() -> [[ThreadEvent]] {
        snapshots
    }
}

struct FixedToolLLMClient: LLMClient {
    var call: ToolCall

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(call)
    }
}

struct AlwaysApprovingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        SafetyReview(verdict: .approve, rationale: "Approved for transcript redaction test.")
    }
}

struct AlwaysAskingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        SafetyReview(
            verdict: .clarify,
            rationale: "Explicit approval required in the focused test.",
            userIntentMatched: true
        )
    }
}

actor SequenceLLMState {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func next() -> AgentAction {
        guard !actions.isEmpty else {
            return .say("Done.")
        }
        return actions.removeFirst()
    }
}

struct SequenceLLMClient: LLMClient {
    private let state: SequenceLLMState

    init(actions: [AgentAction]) {
        self.state = SequenceLLMState(actions: actions)
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        await state.next()
    }
}

enum StreamingActionLLMError: Error {
    case nonStreamingPathUsed
}

struct StreamingActionLLMClient: StreamingLLMClient {
    var chunks: [String]

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        throw StreamingActionLLMError.nonStreamingPathUsed
    }

    func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

struct UsageStreamingActionLLMClient: UsageStreamingLLMClient {
    var events: [AgentTextStreamEvent]

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        throw StreamingActionLLMError.nonStreamingPathUsed
    }

    func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let events = try await actionEventStream(
            thread: thread,
            userMessage: userMessage,
            tools: tools
        )
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in events {
                        if case .text(let chunk) = event {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func actionEventStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
