import Foundation

public enum WorkspaceThreadRowMutation: Sendable, Hashable {
    case duplicate(UUID)
    case togglePin(UUID)
    case archive(UUID)
    case unarchive(UUID)
    case delete(UUID)
}

public enum WorkspaceProjectRowMutation: Sendable, Hashable {
    case newChat(UUID)
    case refreshContext(UUID)
    case remove(UUID)
}

enum WorkspaceSidebarRowAction: Sendable, Hashable {
    case renameThread(threadID: UUID, title: String)
    case mutateThread(WorkspaceThreadRowMutation)
    case renameProject(projectID: UUID, name: String)
    case mutateProject(WorkspaceProjectRowMutation)
}

struct WorkspaceSidebarRowActionPlanner: Sendable, Hashable {
    var sidebar: SidebarSurface
    var projects: ProjectListSurface

    func action(for action: SidebarItemActionSurface) -> WorkspaceSidebarRowAction? {
        switch action.kind {
        case .rename:
            return threadRenameAction(threadID: action.threadID)
        case .duplicate, .pin, .unpin, .archive, .unarchive, .delete:
            return Self.threadMutation(for: action).map(WorkspaceSidebarRowAction.mutateThread)
        }
    }

    func action(for action: ProjectItemActionSurface) -> WorkspaceSidebarRowAction? {
        switch action.kind {
        case .rename:
            return projectRenameAction(projectID: action.projectID)
        case .newChat, .refreshContext, .remove:
            return Self.projectMutation(for: action).map(WorkspaceSidebarRowAction.mutateProject)
        }
    }

    static func threadMutation(for action: SidebarItemActionSurface) -> WorkspaceThreadRowMutation? {
        switch action.kind {
        case .rename:
            return nil
        case .duplicate:
            return .duplicate(action.threadID)
        case .pin, .unpin:
            return .togglePin(action.threadID)
        case .archive:
            return .archive(action.threadID)
        case .unarchive:
            return .unarchive(action.threadID)
        case .delete:
            return .delete(action.threadID)
        }
    }

    static func projectMutation(for action: ProjectItemActionSurface) -> WorkspaceProjectRowMutation? {
        switch action.kind {
        case .newChat:
            return .newChat(action.projectID)
        case .refreshContext:
            return .refreshContext(action.projectID)
        case .rename:
            return nil
        case .remove:
            return .remove(action.projectID)
        }
    }

    private func threadRenameAction(threadID: UUID) -> WorkspaceSidebarRowAction? {
        guard let item = sidebar.items.first(where: { $0.id == threadID }) else {
            return nil
        }
        return .renameThread(threadID: item.id, title: item.title)
    }

    private func projectRenameAction(projectID: UUID) -> WorkspaceSidebarRowAction? {
        guard let item = projects.items.first(where: { $0.id == projectID }) else {
            return nil
        }
        return .renameProject(projectID: item.id, name: item.name)
    }
}

public struct WorkspaceSidebarRowMutationExecutor {
    private init() {}

    @MainActor
    @discardableResult
    public static func execute(
        _ mutation: WorkspaceThreadRowMutation,
        model: QuillCodeWorkspaceModel
    ) -> Bool {
        switch mutation {
        case .duplicate(let threadID):
            return model.duplicateThread(threadID) != nil
        case .togglePin(let threadID):
            model.togglePinThread(threadID)
            return true
        case .archive(let threadID):
            model.archiveThread(threadID)
            return true
        case .unarchive(let threadID):
            return model.unarchiveThread(threadID)
        case .delete(let threadID):
            return model.deleteThread(threadID)
        }
    }

    @MainActor
    @discardableResult
    public static func execute(
        _ mutation: WorkspaceProjectRowMutation,
        model: QuillCodeWorkspaceModel
    ) -> Bool {
        switch mutation {
        case .newChat(let projectID):
            _ = model.newChat(projectID: projectID)
            return true
        case .refreshContext(let projectID):
            return model.refreshProjectContext(projectID)
        case .remove(let projectID):
            return model.removeProject(projectID)
        }
    }
}
