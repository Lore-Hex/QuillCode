import Foundation
import QuillCodeCore

public enum ActivitySectionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case plan
    case changes
    case context
    case runReceipts
    case recent
    case subagents
    case handoff
    case tools
    case instructionReview
    case sources
    case artifacts
    case latestAnswer

    public var title: String {
        switch self {
        case .plan:
            return "Task Plan"
        case .changes:
            return "Changes"
        case .context:
            return "Context"
        case .runReceipts:
            return "Run Receipts"
        case .recent:
            return "Recent"
        case .subagents:
            return "Subagents"
        case .handoff:
            return "Handoff Summary"
        case .tools:
            return "Tools"
        case .instructionReview:
            return "Instruction Review"
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
        case .plan:
            return "No plan yet"
        case .changes:
            return "No file changes yet"
        case .context:
            return "No context compaction yet"
        case .runReceipts:
            return "No run receipts yet"
        case .recent:
            return "No task events yet"
        case .subagents:
            return "No subagents running"
        case .handoff:
            return ""
        case .tools:
            return "No tools used yet"
        case .instructionReview:
            return "No instruction conflicts"
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
        case .plan:
            return "activity-plan"
        case .changes:
            return "activity-change"
        case .context:
            return "activity-context"
        case .runReceipts:
            return "activity-run-receipt"
        case .recent:
            return "activity-step"
        case .subagents:
            return "activity-subagent"
        case .handoff:
            return "activity-handoff"
        case .tools:
            return "activity-tool"
        case .instructionReview:
            return "activity-instruction-conflict"
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
        case .plan:
            return true
        case .changes, .context, .runReceipts, .handoff, .instructionReview, .latestAnswer:
            return false
        case .recent, .subagents, .tools, .sources, .artifacts:
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
        if kind == .instructionReview {
            return "\(items.count) issue\(items.count == 1 ? "" : "s")"
        }
        if kind == .changes {
            return "\(items.count) file\(items.count == 1 ? "" : "s")"
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
    public var actions: [ActivityItemActionSurface]
    public var transcript: [SubagentTranscriptEntry]

    public init(
        id: String,
        title: String,
        detail: String,
        kind: String,
        statusLabel: String = "",
        actions: [ActivityItemActionSurface] = [],
        transcript: [SubagentTranscriptEntry] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.statusLabel = statusLabel
        self.actions = actions
        self.transcript = transcript
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case kind
        case statusLabel
        case actions
        case transcript
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        self.statusLabel = try container.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        self.actions = try container.decodeIfPresent([ActivityItemActionSurface].self, forKey: .actions) ?? []
        self.transcript = try container.decodeIfPresent([SubagentTranscriptEntry].self, forKey: .transcript) ?? []
    }
}

public struct ActivityItemActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { commandID }
    public var title: String
    public var commandID: String
    public var kind: String

    public init(title: String, commandID: String, kind: String) {
        self.title = title
        self.commandID = commandID
        self.kind = kind
    }
}
