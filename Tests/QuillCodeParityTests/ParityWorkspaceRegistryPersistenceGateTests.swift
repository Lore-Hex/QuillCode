import XCTest

final class ParityWorkspaceRegistryPersistenceGateTests: QuillCodeParityTestCase {
    func testWorkspaceRegistriesShareOneTrackedPersistenceBoundary() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let persistenceText = try Self.appSourceText(named: "WorkspaceRegistryPersistence.swift")
        let issueText = try Self.appSourceText(named: "WorkspaceRegistryPersistenceIssue.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")

        Self.assertSource(persistenceText, containsAll: [
            "struct WorkspaceRegistryPersistence",
            "func saveProjects(",
            "func saveProjectsOrThrow(",
            "func saveAutomations(",
            "func saveSidebarSavedSearches("
        ])
        Self.assertSource(issueText, containsAll: [
            "final class WorkspaceRegistryPersistenceIssueTracker",
            "private var failedKinds: Set<WorkspaceRegistryPersistenceKind>",
            "Private content included"
        ])
        Self.assertSource(modelText, containsAll: [
            "let registryPersistenceIssueTracker = WorkspaceRegistryPersistenceIssueTracker()",
            "self.registryPersistenceIssueTracker = registryPersistenceIssueTracker",
            "self.registryPersistence = WorkspaceRegistryPersistence(",
            "registryPersistence.saveProjects(root.projects)",
            "registryPersistence.saveAutomations(automations.items)",
            "registryPersistence.saveSidebarSavedSearches(sidebarSavedSearches)"
        ])
        Self.assertSource(modelText, excludesAll: [
            "try? projectStore?.save",
            "try? automationStore?.save",
            "try? sidebarSavedSearchStore?.save"
        ])
        Self.assertSource(
            surfaceText,
            contains: "registryPersistenceIssueTracker.runtimeIssue"
        )
    }
}
