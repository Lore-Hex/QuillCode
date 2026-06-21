import Foundation
import QuillCodeCore

public struct WorkspaceActivitySurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var statusLabel: String
    public var taskTitle: String
    public var taskSubtitle: String
    public var recentSteps: [ActivityItemSurface]
    public var tools: [ActivityItemSurface]
    public var sources: [ActivityItemSurface]
    public var artifacts: [ToolArtifactState]
    public var finalAnswer: String?

    public init(
        isVisible: Bool = false,
        title: String = "Activity",
        subtitle: String = "No active thread",
        statusLabel: String = "Idle",
        taskTitle: String = "No task selected",
        taskSubtitle: String = "Start a chat to see task progress, tools, sources, and artifacts.",
        recentSteps: [ActivityItemSurface] = [],
        tools: [ActivityItemSurface] = [],
        sources: [ActivityItemSurface] = [],
        artifacts: [ToolArtifactState] = [],
        finalAnswer: String? = nil
    ) {
        self.isVisible = isVisible
        self.title = title
        self.subtitle = subtitle
        self.statusLabel = statusLabel
        self.taskTitle = taskTitle
        self.taskSubtitle = taskSubtitle
        self.recentSteps = recentSteps
        self.tools = tools
        self.sources = sources
        self.artifacts = artifacts
        self.finalAnswer = finalAnswer
    }

    public init(
        isVisible: Bool,
        thread: ChatThread?,
        toolCards: [ToolCardState],
        instructions: [ProjectInstruction],
        memories: [MemoryNote],
        agentStatus: String
    ) {
        guard let thread else {
            self.init(isVisible: isVisible, statusLabel: agentStatus)
            return
        }

        let sources = Self.sourceItems(instructions: instructions, memories: memories)
        let artifacts = Self.uniqueArtifacts(from: toolCards)
        self.init(
            isVisible: isVisible,
            title: "Activity",
            subtitle: Self.subtitle(toolCount: toolCards.count, sourceCount: sources.count, artifactCount: artifacts.count),
            statusLabel: agentStatus,
            taskTitle: Self.taskTitle(for: thread),
            taskSubtitle: "\(thread.messages.count) message\(thread.messages.count == 1 ? "" : "s") - \(thread.events.count) event\(thread.events.count == 1 ? "" : "s")",
            recentSteps: Self.recentSteps(for: thread),
            tools: Self.toolItems(from: toolCards),
            sources: sources,
            artifacts: artifacts,
            finalAnswer: Self.finalAnswer(for: thread)
        )
    }

    private static func subtitle(toolCount: Int, sourceCount: Int, artifactCount: Int) -> String {
        [
            countLabel(toolCount, singular: "tool"),
            countLabel(sourceCount, singular: "source"),
            countLabel(artifactCount, singular: "artifact")
        ].joined(separator: " - ")
    }

    private static func taskTitle(for thread: ChatThread) -> String {
        guard let latestUserMessage = thread.messages.reversed().first(where: { $0.role == .user }) else {
            return thread.title
        }
        return boundedLine(latestUserMessage.content, limit: 96)
    }

    private static func recentSteps(for thread: ChatThread) -> [ActivityItemSurface] {
        thread.events
            .filter { $0.kind != .messageFeedback }
            .suffix(8)
            .map { event in
                ActivityItemSurface(
                    id: event.id.uuidString,
                    title: eventKindLabel(event.kind),
                    detail: boundedLine(event.summary, limit: 140),
                    kind: event.kind.rawValue,
                    statusLabel: eventStatusLabel(event.kind)
                )
            }
    }

    private static func toolItems(from toolCards: [ToolCardState]) -> [ActivityItemSurface] {
        toolCards
            .suffix(8)
            .map { card in
                ActivityItemSurface(
                    id: card.id,
                    title: card.title,
                    detail: boundedLine(card.subtitle, limit: 120),
                    kind: "tool",
                    statusLabel: card.status.rawValue
                )
            }
    }

    private static func sourceItems(instructions: [ProjectInstruction], memories: [MemoryNote]) -> [ActivityItemSurface] {
        let instructionItems = instructions.prefix(4).map { instruction in
            ActivityItemSurface(
                id: "instruction-\(instruction.path)",
                title: sourceTitle(instruction.path),
                detail: instruction.path,
                kind: "instruction",
                statusLabel: "rules"
            )
        }
        let memoryItems = memories.prefix(4).map { memory in
            ActivityItemSurface(
                id: "memory-\(memory.id)",
                title: memory.title,
                detail: memory.relativePath,
                kind: "memory",
                statusLabel: memory.scope.title
            )
        }
        return Array(instructionItems + memoryItems)
    }

    private static func uniqueArtifacts(from toolCards: [ToolCardState]) -> [ToolArtifactState] {
        var seen = Set<String>()
        var artifacts: [ToolArtifactState] = []
        for artifact in toolCards.flatMap(\.artifacts).reversed() {
            guard seen.insert(artifact.value).inserted else { continue }
            artifacts.append(artifact)
            if artifacts.count == 8 { break }
        }
        return Array(artifacts.reversed())
    }

    private static func finalAnswer(for thread: ChatThread) -> String? {
        guard let answer = thread.messages.reversed().first(where: { $0.role == .assistant })?.content else {
            return nil
        }
        return boundedLine(answer, limit: 280)
    }

    private static func sourceTitle(_ path: String) -> String {
        let title = URL(fileURLWithPath: path).lastPathComponent
        return title.isEmpty ? path : title
    }

    private static func boundedLine(_ value: String, limit: Int) -> String {
        let normalized = value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: limit)
        return "\(normalized[..<end])..."
    }

    private static func eventKindLabel(_ kind: ThreadEventKind) -> String {
        switch kind {
        case .message:
            return "Message"
        case .toolQueued:
            return "Tool queued"
        case .toolRunning:
            return "Tool running"
        case .toolCompleted:
            return "Tool completed"
        case .toolFailed:
            return "Tool failed"
        case .approvalRequested:
            return "Safety check"
        case .approvalDecided:
            return "Safety decision"
        case .reviewComment:
            return "Review comment"
        case .notice:
            return "Notice"
        case .messageFeedback:
            return "Feedback"
        }
    }

    private static func eventStatusLabel(_ kind: ThreadEventKind) -> String {
        switch kind {
        case .toolQueued:
            return "Queued"
        case .toolRunning:
            return "Running"
        case .toolCompleted:
            return "Done"
        case .toolFailed:
            return "Failed"
        case .approvalRequested:
            return "Review"
        case .approvalDecided:
            return "Checked"
        case .message, .reviewComment, .notice, .messageFeedback:
            return "Logged"
        }
    }

    private static func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

public struct ActivityItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var kind: String
    public var statusLabel: String

    public init(
        id: String,
        title: String,
        detail: String,
        kind: String,
        statusLabel: String = ""
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.statusLabel = statusLabel
    }
}
