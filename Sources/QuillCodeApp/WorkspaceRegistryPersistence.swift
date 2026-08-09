import QuillCodeCore
import QuillCodePersistence

struct WorkspaceRegistryPersistence {
    let projectStore: JSONProjectStore?
    let automationStore: JSONAutomationStore?
    let sidebarSavedSearchStore: JSONSidebarSavedSearchStore?
    let issueTracker: WorkspaceRegistryPersistenceIssueTracker

    init(
        projectStore: JSONProjectStore?,
        automationStore: JSONAutomationStore?,
        sidebarSavedSearchStore: JSONSidebarSavedSearchStore?,
        issueTracker: WorkspaceRegistryPersistenceIssueTracker = WorkspaceRegistryPersistenceIssueTracker()
    ) {
        self.projectStore = projectStore
        self.automationStore = automationStore
        self.sidebarSavedSearchStore = sidebarSavedSearchStore
        self.issueTracker = issueTracker
    }

    func saveProjects(_ projects: [ProjectRef]) {
        guard let projectStore else { return }
        save(.projects) {
            try projectStore.save(projects)
        }
    }

    func saveProjectsOrThrow(_ projects: [ProjectRef]) throws {
        guard let projectStore else { return }
        try saveOrThrow(.projects) {
            try projectStore.save(projects)
        }
    }

    func saveAutomations(_ automations: [QuillAutomation]) {
        guard let automationStore else { return }
        save(.automations) {
            try automationStore.save(automations)
        }
    }

    func saveSidebarSavedSearches(_ savedSearches: [SidebarSavedSearch]) {
        guard let sidebarSavedSearchStore else { return }
        save(.savedSearches) {
            try sidebarSavedSearchStore.save(savedSearches)
        }
    }

    private func save(
        _ kind: WorkspaceRegistryPersistenceKind,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            issueTracker.recordSuccess(for: kind)
        } catch {
            issueTracker.recordFailure(for: kind)
        }
    }

    private func saveOrThrow(
        _ kind: WorkspaceRegistryPersistenceKind,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            issueTracker.recordSuccess(for: kind)
        } catch {
            issueTracker.recordFailure(for: kind)
            throw error
        }
    }
}
