import Foundation
import QuillCodeAgent
import QuillCodeCore

public enum WorkspaceContextSummaryPurpose: String, Codable, Sendable, Hashable {
    case compact
    case forkSummary

    var promptTitle: String {
        switch self {
        case .compact:
            return "compact this QuillCode thread"
        case .forkSummary:
            return "summarize this QuillCode thread for a fork"
        }
    }
}

struct WorkspaceContextSummaryContext: Sendable, Hashable {
    var olderMessages: [ChatMessage]
    var recentMessages: [ChatMessage]
}

public struct WorkspaceContextSummaryRequest: Sendable, Hashable {
    public var sourceTitle: String
    public var olderMessages: [ChatMessage]
    public var recentMessages: [ChatMessage]
    public var purpose: WorkspaceContextSummaryPurpose

    init(sourceTitle: String, context: WorkspaceContextSummaryContext, purpose: WorkspaceContextSummaryPurpose) {
        self.sourceTitle = sourceTitle
        self.olderMessages = context.olderMessages
        self.recentMessages = context.recentMessages
        self.purpose = purpose
    }
}

public enum WorkspaceContextSummaryOutcomeSource: String, Codable, Sendable, Hashable {
    case model
    case deterministicFallback = "deterministic_fallback"
}

public struct WorkspaceContextSummaryOutcome: Sendable, Hashable {
    public var summaryOverride: String?
    public var source: WorkspaceContextSummaryOutcomeSource
    public var errorDescription: String?

    public init(
        summaryOverride: String?,
        source: WorkspaceContextSummaryOutcomeSource,
        errorDescription: String? = nil
    ) {
        self.summaryOverride = summaryOverride
        self.source = source
        self.errorDescription = errorDescription
    }
}

public struct WorkspaceContextSummaryTelemetry: Codable, Sendable, Hashable {
    public var purpose: WorkspaceContextSummaryPurpose
    public var source: WorkspaceContextSummaryOutcomeSource
    public var sourceTitle: String
    public var summaryCharacterCount: Int?
    public var errorDescription: String?

    public init(
        purpose: WorkspaceContextSummaryPurpose,
        source: WorkspaceContextSummaryOutcomeSource,
        sourceTitle: String,
        summaryCharacterCount: Int? = nil,
        errorDescription: String? = nil
    ) {
        self.purpose = purpose
        self.source = source
        self.sourceTitle = sourceTitle
        self.summaryCharacterCount = summaryCharacterCount
        self.errorDescription = errorDescription
    }
}

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

enum WorkspaceContextSummaryPromptBuilder {
    private static let maxConversationCharacters = 18_000

    static func prompt(for request: WorkspaceContextSummaryRequest) -> String {
        let transcript = boundedTranscript(for: request)
        return """
        Please \(request.purpose.promptTitle).

        Return exactly one QuillCode action JSON object and no markdown:
        {"type":"say","text":"..."}

        The text must be a concise durable continuation summary for a coding agent. Include:
        - user goals and explicit preferences
        - current implementation state
        - important files, commands, tests, branches, PRs, and decisions
        - unresolved questions, blockers, and next steps

        Do not include tool-feedback JSON, credentials, API keys, private keys, or secrets. Do not invent completed work.

        Source thread: \(request.sourceTitle)

        Visible conversation:
        \(transcript)
        """
    }

    private static func boundedTranscript(for request: WorkspaceContextSummaryRequest) -> String {
        let lines = (request.olderMessages + request.recentMessages)
            .map { "- \(roleLabel($0.role)): \(singleLine($0.content, limit: 1_200))" }
        let joined = lines.joined(separator: "\n")
        guard joined.count > maxConversationCharacters else { return joined }
        return String(joined.suffix(maxConversationCharacters))
    }

    private static func roleLabel(_ role: ChatRole) -> String {
        switch role {
        case .system:
            return "System"
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .tool:
            return "Tool"
        }
    }

    private static func singleLine(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

enum WorkspaceContextSummarySanitizer {
    private static let maxSummaryCharacters = 6_000
    private static let maxDiagnosticCharacters = 180
    private static let secretPatterns = [
        #"sk-[A-Za-z0-9_-]{12,}"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#
    ]

    static func summary(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let redacted = secretPatterns.reduce(trimmed) { result, pattern in
            result.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression
            )
        }
        guard redacted.count > maxSummaryCharacters else { return redacted }
        return String(redacted.prefix(maxSummaryCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    static func diagnostic(from text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = secretPatterns.reduce(collapsed) { result, pattern in
            result.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression
            )
        }
        guard redacted.count > maxDiagnosticCharacters else { return redacted }
        return String(redacted.prefix(maxDiagnosticCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
