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
    public var handoffSummary: String?
    public var sections: [ActivitySectionSurface]

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
        finalAnswer: String? = nil,
        handoffSummary: String? = nil,
        collapsedSectionIDs: Set<ActivitySectionKind> = []
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
        self.handoffSummary = handoffSummary
        self.sections = Self.sections(
            recentSteps: recentSteps,
            tools: tools,
            sources: sources,
            artifacts: artifacts,
            finalAnswer: finalAnswer,
            handoffSummary: handoffSummary,
            collapsedSectionIDs: collapsedSectionIDs
        )
    }

    public init(
        isVisible: Bool,
        thread: ChatThread?,
        toolCards: [ToolCardState],
        instructions: [ProjectInstruction],
        memories: [MemoryNote],
        agentStatus: String,
        collapsedSectionIDs: Set<ActivitySectionKind> = []
    ) {
        guard let thread else {
            self.init(
                isVisible: isVisible,
                statusLabel: agentStatus,
                collapsedSectionIDs: collapsedSectionIDs
            )
            return
        }

        let sources = Self.sourceItems(instructions: instructions, memories: memories)
        let artifacts = Self.uniqueArtifacts(from: toolCards)
        let finalAnswer = Self.finalAnswer(for: thread)
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
            finalAnswer: finalAnswer,
            handoffSummary: Self.handoffSummary(
                for: thread,
                toolCards: toolCards,
                sources: sources,
                artifacts: artifacts,
                finalAnswer: finalAnswer,
                agentStatus: agentStatus
            ),
            collapsedSectionIDs: collapsedSectionIDs
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isVisible
        case title
        case subtitle
        case statusLabel
        case taskTitle
        case taskSubtitle
        case recentSteps
        case tools
        case sources
        case artifacts
        case finalAnswer
        case handoffSummary
        case sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Activity"
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? "No active thread"
        self.statusLabel = try container.decodeIfPresent(String.self, forKey: .statusLabel) ?? "Idle"
        self.taskTitle = try container.decodeIfPresent(String.self, forKey: .taskTitle) ?? "No task selected"
        self.taskSubtitle = try container.decodeIfPresent(String.self, forKey: .taskSubtitle)
            ?? "Start a chat to see task progress, tools, sources, and artifacts."
        self.recentSteps = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .recentSteps) ?? []
        self.tools = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .tools) ?? []
        self.sources = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .sources) ?? []
        self.artifacts = try container.decodeIfPresent([ToolArtifactState].self, forKey: .artifacts) ?? []
        self.finalAnswer = try container.decodeIfPresent(String.self, forKey: .finalAnswer)
        self.handoffSummary = try container.decodeIfPresent(String.self, forKey: .handoffSummary)
        self.sections = try container.decodeIfPresent([ActivitySectionSurface].self, forKey: .sections)
            ?? Self.sections(
                recentSteps: recentSteps,
                tools: tools,
                sources: sources,
                artifacts: artifacts,
                finalAnswer: finalAnswer,
                handoffSummary: handoffSummary,
                collapsedSectionIDs: []
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

    private static func sections(
        recentSteps: [ActivityItemSurface],
        tools: [ActivityItemSurface],
        sources: [ActivityItemSurface],
        artifacts: [ToolArtifactState],
        finalAnswer: String?,
        handoffSummary: String?,
        collapsedSectionIDs: Set<ActivitySectionKind>
    ) -> [ActivitySectionSurface] {
        [
            ActivitySectionSurface(
                kind: .recent,
                items: recentSteps,
                isCollapsed: collapsedSectionIDs.contains(.recent)
            ),
            ActivitySectionSurface(
                kind: .handoff,
                bodyText: handoffSummary,
                isCollapsed: collapsedSectionIDs.contains(.handoff)
            ),
            ActivitySectionSurface(
                kind: .tools,
                items: tools,
                isCollapsed: collapsedSectionIDs.contains(.tools)
            ),
            ActivitySectionSurface(
                kind: .sources,
                items: sources,
                isCollapsed: collapsedSectionIDs.contains(.sources)
            ),
            ActivitySectionSurface(
                kind: .artifacts,
                artifacts: artifacts,
                isCollapsed: collapsedSectionIDs.contains(.artifacts)
            ),
            ActivitySectionSurface(
                kind: .latestAnswer,
                bodyText: finalAnswer,
                isCollapsed: collapsedSectionIDs.contains(.latestAnswer)
            )
        ].filter { !$0.isEmpty || $0.kind.alwaysVisible }
    }

    private static func finalAnswer(for thread: ChatThread) -> String? {
        guard let answer = thread.messages.reversed().first(where: { $0.role == .assistant })?.content else {
            return nil
        }
        return boundedLine(answer, limit: 280)
    }

    private static func handoffSummary(
        for thread: ChatThread,
        toolCards: [ToolCardState],
        sources: [ActivityItemSurface],
        artifacts: [ToolArtifactState],
        finalAnswer: String?,
        agentStatus: String
    ) -> String {
        let toolNames = toolCards.suffix(4).map(\.title)
        let artifactLabels = artifacts.suffix(4).map(\.label)
        var lines = [
            "Thread: \(boundedLine(thread.title, limit: 80))",
            "Latest request: \(taskTitle(for: thread))",
            "Status: \(agentStatus)",
            "Tools: \(summary(count: toolCards.count, singular: "tool", details: toolNames))",
            "Sources: \(countLabel(sources.count, singular: "source"))",
            "Artifacts: \(summary(count: artifacts.count, singular: "artifact", details: artifactLabels))"
        ]
        if let finalAnswer {
            lines.append("Latest answer: \(boundedLine(finalAnswer, limit: 160))")
        }
        return lines.joined(separator: "\n")
    }

    private static func summary(count: Int, singular: String, details: [String]) -> String {
        guard count > 0 else { return "none" }
        let countText = countLabel(count, singular: singular)
        guard !details.isEmpty else { return countText }
        return "\(countText) (\(details.joined(separator: ", ")))"
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

public enum ActivitySectionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case recent
    case handoff
    case tools
    case sources
    case artifacts
    case latestAnswer

    public var title: String {
        switch self {
        case .recent:
            return "Recent"
        case .handoff:
            return "Handoff Summary"
        case .tools:
            return "Tools"
        case .sources:
            return "Sources"
        case .artifacts:
            return "Artifacts"
        case .latestAnswer:
            return "Latest Answer"
        }
    }

    public var emptyTitle: String {
        switch self {
        case .recent:
            return "No task events yet"
        case .handoff:
            return ""
        case .tools:
            return "No tools used yet"
        case .sources:
            return "No context sources attached"
        case .artifacts:
            return "No artifacts produced yet"
        case .latestAnswer:
            return ""
        }
    }

    public var itemTestID: String {
        switch self {
        case .recent:
            return "activity-step"
        case .handoff:
            return "activity-handoff"
        case .tools:
            return "activity-tool"
        case .sources:
            return "activity-source"
        case .artifacts:
            return "activity-artifact"
        case .latestAnswer:
            return "activity-final-answer"
        }
    }

    public var alwaysVisible: Bool {
        switch self {
        case .handoff, .latestAnswer:
            return false
        case .recent, .tools, .sources, .artifacts:
            return true
        }
    }
}

public struct ActivitySectionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: ActivitySectionKind
    public var title: String
    public var emptyTitle: String
    public var itemTestID: String
    public var items: [ActivityItemSurface]
    public var artifacts: [ToolArtifactState]
    public var bodyText: String?
    public var isCollapsed: Bool
    public var toggleCommandID: String

    public var id: String { kind.rawValue }
    public var isEmpty: Bool {
        items.isEmpty
            && artifacts.isEmpty
            && (bodyText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    public var countLabel: String {
        if let bodyText, !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if kind == .handoff { return "1 summary" }
            return "1 answer"
        }
        if !artifacts.isEmpty {
            return "\(artifacts.count) artifact\(artifacts.count == 1 ? "" : "s")"
        }
        return "\(items.count) item\(items.count == 1 ? "" : "s")"
    }

    public init(
        kind: ActivitySectionKind,
        items: [ActivityItemSurface] = [],
        artifacts: [ToolArtifactState] = [],
        bodyText: String? = nil,
        isCollapsed: Bool = false
    ) {
        self.kind = kind
        self.title = kind.title
        self.emptyTitle = kind.emptyTitle
        self.itemTestID = kind.itemTestID
        self.items = items
        self.artifacts = artifacts
        self.bodyText = bodyText
        self.isCollapsed = isCollapsed
        self.toggleCommandID = "activity-toggle-section:\(kind.rawValue)"
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case title
        case emptyTitle
        case itemTestID
        case items
        case artifacts
        case bodyText
        case isCollapsed
        case toggleCommandID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(ActivitySectionKind.self, forKey: .kind)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? kind.title
        self.emptyTitle = try container.decodeIfPresent(String.self, forKey: .emptyTitle) ?? kind.emptyTitle
        self.itemTestID = try container.decodeIfPresent(String.self, forKey: .itemTestID) ?? kind.itemTestID
        self.items = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .items) ?? []
        self.artifacts = try container.decodeIfPresent([ToolArtifactState].self, forKey: .artifacts) ?? []
        self.bodyText = try container.decodeIfPresent(String.self, forKey: .bodyText)
        self.isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        self.toggleCommandID = try container.decodeIfPresent(String.self, forKey: .toggleCommandID)
            ?? "activity-toggle-section:\(kind.rawValue)"
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
