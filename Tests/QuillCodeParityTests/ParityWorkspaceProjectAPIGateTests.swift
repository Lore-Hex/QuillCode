import XCTest

final class ParityWorkspaceProjectAPIGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelProjectAPIsLiveInFocusedExtension() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let projectExtensionText = try Self.appSourceText(named: "WorkspaceModelProjects.swift")

        [
            "extension QuillCodeWorkspaceModel",
            "public func addProject",
            "public func addSSHProject",
            "public func selectProject",
            "public func refreshSelectedProjectInstructions",
            "public func refreshSelectedProjectContext",
            "public func renameProject",
            "public func refreshProjectContext",
            "public func runProjectExtensionInstall",
            "public func runProjectExtensionUpdate",
            "public func removeProject",
            "WorkspaceProjectEngine.upsertLocalProject",
            "WorkspaceProjectEngine.upsertSSHProject",
            "WorkspaceProjectEngine.selectionAfterSelectingProject",
            "WorkspaceProjectEngine.renameProject",
            "WorkspaceProjectEngine.removeProject"
        ].forEach { Self.assertSource(projectExtensionText, contains: $0) }

        [
            "public func addProject",
            "public func addSSHProject",
            "public func selectProject",
            "public func refreshSelectedProjectInstructions",
            "public func refreshSelectedProjectContext",
            "public func renameProject",
            "public func refreshProjectContext",
            "public func runProjectExtensionInstall",
            "public func runProjectExtensionUpdate",
            "Installed extension \\(",
            "Updated extension \\(",
            "public func removeProject"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }
}
