import Foundation
import QuillCodeCore

public struct ProjectListSurface: Codable, Sendable, Hashable {
    public var title: String
    public var items: [ProjectItemSurface]
    public var selectedProjectID: UUID?
    public var emptyTitle: String

    public init(
        title: String = "Projects",
        items: [ProjectItemSurface],
        selectedProjectID: UUID?,
        emptyTitle: String = "No projects yet"
    ) {
        self.title = title
        self.items = items
        self.selectedProjectID = selectedProjectID
        self.emptyTitle = emptyTitle
    }

    public var countLabel: String {
        switch items.count {
        case 0:
            return "No projects"
        case 1:
            return "1 project"
        default:
            return "\(items.count) projects"
        }
    }

    public var localCountLabel: String {
        "\(localProjectCount) local"
    }

    public var remoteCountLabel: String {
        "\(remoteProjectCount) remote"
    }

    public var connectionSummaryLabel: String {
        guard !items.isEmpty else {
            return "No project connections"
        }
        guard remoteProjectCount > 0 else {
            return localCountLabel
        }
        if localProjectCount == 0 {
            return remoteCountLabel
        }
        return "\(localCountLabel) · \(remoteCountLabel)"
    }

    public var compactCountLabel: String {
        guard remoteProjectCount > 0 else {
            return countLabel
        }
        return "\(countLabel) · \(remoteCountLabel)"
    }

    public var currentProjectLabel: String? {
        items.first(where: \.isSelected).map { "Current project: \($0.name)" }
    }

    public var accessibilitySummary: String {
        guard !items.isEmpty else {
            return "\(title), no projects"
        }
        let current = currentProjectLabel.map { ". \($0)" } ?? ""
        return "\(title), \(countLabel), \(connectionSummaryLabel)\(current). Drag project rows to reorder them."
    }

    private var remoteProjectCount: Int {
        items.filter(\.isRemote).count
    }

    private var localProjectCount: Int {
        items.count - remoteProjectCount
    }
}

public struct ProjectItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var path: String
    public var connectionKindLabel: String
    public var isRemote: Bool
    public var actions: [ProjectItemActionSurface]
    public var isSelected: Bool

    public var selectionLabel: String? {
        isSelected ? "Current" : nil
    }

    public var accessibilityLabel: String {
        [
            isSelected ? "Current project" : "Project",
            name,
            connectionKindLabel,
            path
        ].joined(separator: ", ")
    }

    public init(
        project: ProjectRef,
        selectedProjectID: UUID?,
        canMoveToTop: Bool = true,
        canMoveUp: Bool = true,
        canMoveDown: Bool = true,
        canMoveToBottom: Bool = true
    ) {
        self.id = project.id
        self.name = project.name
        self.path = project.displayPath
        self.connectionKindLabel = project.connection.kindLabel
        self.isRemote = project.isRemote
        self.actions = [
            ProjectItemActionSurface(kind: .newChat, projectID: project.id),
            ProjectItemActionSurface(kind: .refreshContext, projectID: project.id),
            ProjectItemActionSurface(
                kind: .moveToTop,
                projectID: project.id,
                isEnabled: canMoveToTop,
                disabledReason: canMoveToTop ? nil : "Already at the top"
            ),
            ProjectItemActionSurface(
                kind: .moveUp,
                projectID: project.id,
                isEnabled: canMoveUp,
                disabledReason: canMoveUp ? nil : "Already at the top"
            ),
            ProjectItemActionSurface(
                kind: .moveDown,
                projectID: project.id,
                isEnabled: canMoveDown,
                disabledReason: canMoveDown ? nil : "Already at the bottom"
            ),
            ProjectItemActionSurface(
                kind: .moveToBottom,
                projectID: project.id,
                isEnabled: canMoveToBottom,
                disabledReason: canMoveToBottom ? nil : "Already at the bottom"
            ),
            ProjectItemActionSurface(kind: .rename, projectID: project.id),
            ProjectItemActionSurface(kind: .remove, projectID: project.id)
        ]
        self.isSelected = project.id == selectedProjectID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case connectionKindLabel
        case isRemote
        case actions
        case isSelected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.connectionKindLabel = try container.decodeIfPresent(String.self, forKey: .connectionKindLabel) ?? "Local"
        self.isRemote = try container.decodeIfPresent(Bool.self, forKey: .isRemote) ?? false
        self.actions = try container.decodeIfPresent([ProjectItemActionSurface].self, forKey: .actions) ?? [
            ProjectItemActionSurface(kind: .newChat, projectID: id),
            ProjectItemActionSurface(kind: .refreshContext, projectID: id),
            ProjectItemActionSurface(kind: .moveToTop, projectID: id),
            ProjectItemActionSurface(kind: .moveUp, projectID: id),
            ProjectItemActionSurface(kind: .moveDown, projectID: id),
            ProjectItemActionSurface(kind: .moveToBottom, projectID: id),
            ProjectItemActionSurface(kind: .rename, projectID: id),
            ProjectItemActionSurface(kind: .remove, projectID: id)
        ]
        self.isSelected = try container.decode(Bool.self, forKey: .isSelected)
    }
}

public enum ProjectItemActionKind: String, Codable, Sendable, Hashable {
    case newChat
    case refreshContext
    case moveToTop
    case moveUp
    case moveDown
    case moveToBottom
    case rename
    case remove

    public var title: String {
        switch self {
        case .newChat:
            return "New chat"
        case .refreshContext:
            return "Refresh context"
        case .moveToTop:
            return "Move to top"
        case .moveUp:
            return "Move up"
        case .moveDown:
            return "Move down"
        case .moveToBottom:
            return "Move to bottom"
        case .rename:
            return "Rename"
        case .remove:
            return "Remove from list"
        }
    }
}

public struct ProjectItemActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: ProjectItemActionKind
    public var projectID: UUID
    public var isEnabled: Bool
    public var disabledReason: String?

    public var id: String {
        "\(projectID.uuidString)-\(kind.rawValue)"
    }

    public init(
        kind: ProjectItemActionKind,
        projectID: UUID,
        isEnabled: Bool = true,
        disabledReason: String? = nil
    ) {
        self.kind = kind
        self.projectID = projectID
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case projectID
        case isEnabled
        case disabledReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(ProjectItemActionKind.self, forKey: .kind)
        self.projectID = try container.decode(UUID.self, forKey: .projectID)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.disabledReason = try container.decodeIfPresent(String.self, forKey: .disabledReason)
    }
}
