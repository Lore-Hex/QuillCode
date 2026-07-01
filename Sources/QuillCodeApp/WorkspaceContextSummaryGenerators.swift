import Foundation
import QuillCodeAgent
import QuillCodeCore

public protocol WorkspaceContextSummaryGenerating: Sendable {
    var isModelBacked: Bool { get }
    func summary(for request: WorkspaceContextSummaryRequest) async throws -> String
}

public struct DeterministicWorkspaceContextSummaryGenerator: WorkspaceContextSummaryGenerating {
    public var isModelBacked: Bool { false }

    public init() {}

    public func summary(for request: WorkspaceContextSummaryRequest) async throws -> String {
        WorkspaceThreadSeedBuilder.summaryText(
            sourceTitle: request.sourceTitle,
            olderMessages: request.olderMessages,
            recentMessages: request.recentMessages,
            purpose: request.purpose
        )
    }
}

public struct LLMWorkspaceContextSummaryGenerator: WorkspaceContextSummaryGenerating {
    public var isModelBacked: Bool { true }
    public var llm: any LLMClient

    public init(llm: any LLMClient) {
        self.llm = llm
    }

    public func summary(for request: WorkspaceContextSummaryRequest) async throws -> String {
        let prompt = WorkspaceContextSummaryPromptBuilder.prompt(for: request)
        let action = try await llm.nextAction(
            thread: ChatThread(title: "Context summary"),
            userMessage: prompt,
            tools: []
        )
        guard case .say(let text) = action,
              let summary = WorkspaceContextSummarySanitizer.summary(from: text)
        else {
            throw WorkspaceContextSummaryError.invalidModelSummary
        }
        return summary
    }
}

enum WorkspaceContextSummaryError: Error {
    case invalidModelSummary
}

extension WorkspaceContextSummaryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidModelSummary:
            return "model did not return a valid summary action"
        }
    }
}
