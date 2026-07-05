import XCTest

final class ParityWorkspaceProjectGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesProjectMetadataLoading() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let projectExtensionText = try Self.appSourceText(named: "WorkspaceModelProjects.swift")
        let loaderText = try Self.appSourceText(named: "WorkspaceProjectMetadataLoader.swift")

        Self.assertSource(loaderText, contains: "enum WorkspaceProjectMetadataLoader")
        Self.assertSource(loaderText, contains: "WorkspaceProjectConfigurationLoader.load")
        Self.assertSource(loaderText, contains: "ProjectInstructionLoader.load")
        Self.assertSource(loaderText, contains: "LocalEnvironmentActionLoader.load")
        Self.assertSource(loaderText, contains: "ProjectExtensionManifestLoader.load")
        Self.assertSource(loaderText, contains: "MemoryNoteLoader.loadProject")
        Self.assertSource(loaderText, contains: "SSHRemoteProjectContextLoader.load")
        Self.assertSource(projectExtensionText, contains: "WorkspaceProjectMetadataLoader.loadLocal")
        Self.assertSource(modelText, contains: "WorkspaceProjectContextRefresher.refreshRemoteProjectContext")
        Self.assertSource(modelText, excludes: "ProjectInstructionLoader.load")
        Self.assertSource(modelText, excludes: "LocalEnvironmentActionLoader.load")
        Self.assertSource(modelText, excludes: "ProjectExtensionManifestLoader.load")
        Self.assertSource(modelText, excludes: "MemoryNoteLoader.loadProject")
        Self.assertSource(modelText, excludes: "SSHRemoteProjectContextLoader.load")
    }

    func testWorkspaceModelProjectAPIsLiveInFocusedExtension() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let projectExtensionText = try Self.appSourceText(named: "WorkspaceModelProjects.swift")

        Self.assertSource(projectExtensionText, contains: "extension QuillCodeWorkspaceModel")
        Self.assertSource(projectExtensionText, contains: "public func addProject")
        Self.assertSource(projectExtensionText, contains: "public func addSSHProject")
        Self.assertSource(projectExtensionText, contains: "public func selectProject")
        Self.assertSource(projectExtensionText, contains: "public func refreshSelectedProjectInstructions")
        Self.assertSource(projectExtensionText, contains: "public func refreshSelectedProjectContext")
        Self.assertSource(projectExtensionText, contains: "public func renameProject")
        Self.assertSource(projectExtensionText, contains: "public func refreshProjectContext")
        Self.assertSource(projectExtensionText, contains: "public func runProjectExtensionInstall")
        Self.assertSource(projectExtensionText, contains: "public func runProjectExtensionUpdate")
        Self.assertSource(projectExtensionText, contains: "public func removeProject")
        Self.assertSource(projectExtensionText, contains: "WorkspaceProjectEngine.upsertLocalProject")
        Self.assertSource(projectExtensionText, contains: "WorkspaceProjectEngine.upsertSSHProject")
        Self.assertSource(projectExtensionText, contains: "WorkspaceProjectEngine.selectionAfterSelectingProject")
        Self.assertSource(projectExtensionText, contains: "WorkspaceProjectEngine.renameProject")
        Self.assertSource(projectExtensionText, contains: "WorkspaceProjectEngine.removeProject")

        assertWorkspaceModelDoesNotOwnProjectAPIs(modelText)
    }

    func testWorkspaceModelTestsDoNotOwnPureProjectLoaderCoverage() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let instructionTests = try Self.appTestSourceText(named: "ProjectInstructionLoaderTests.swift")
        let actionTests = try Self.appTestSourceText(named: "LocalEnvironmentActionLoaderTests.swift")
        let extensionTests = try Self.appTestSourceText(named: "ProjectExtensionManifestLoaderTests.swift")
        let memoryTests = try Self.appTestSourceText(named: "MemoryNoteLoaderTests.swift")

        Self.assertSource(instructionTests, contains: "ProjectInstructionLoader.load")
        Self.assertSource(actionTests, contains: "LocalEnvironmentActionLoader.load")
        Self.assertSource(extensionTests, contains: "ProjectExtensionManifestLoader.load")
        Self.assertSource(memoryTests, contains: "MemoryNoteLoader.loadProject")
        Self.assertSource(modelTests, excludes: "ProjectInstructionLoader.load")
        Self.assertSource(modelTests, excludes: "LocalEnvironmentActionLoader.load")
        Self.assertSource(modelTests, excludes: "ProjectExtensionManifestLoader.load")
        Self.assertSource(modelTests, excludes: "MemoryNoteLoader.loadProject")
    }

    func testProjectInstructionScopesStayInCorePromptAndActivityContracts() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let projectInstructionText = try Self.coreSourceText(named: "ProjectInstruction.swift")
        let loaderText = try Self.appSourceText(named: "ProjectInstructionLoader.swift")
        let promptText = try Self.agentSourceText(named: "TrustedRouterPromptBuilder.swift")
        let activityText = try Self.appSourceText(named: "WorkspaceActivitySourceSurfaceBuilder.swift")
        let diagnosticsText = try Self.appSourceText(named: "ProjectInstructionDiagnosticsBuilder.swift")

        Self.assertSource(projectInstructionText, contains: "public var scopePath")
        Self.assertSource(projectInstructionText, contains: "static func scopePath(for instructionPath")
        Self.assertSource(projectInstructionText, contains: "static func scopeLabel(for scopePath")
        Self.assertSource(loaderText, contains: "ProjectInstruction.scopePath(for: relativePath)")
        Self.assertSource(promptText, contains: "Scope: \\(instruction.scopeLabel)")
        Self.assertSource(promptText, contains: "Apply whole-project instructions everywhere")
        Self.assertSource(activityText, contains: "Scope: \\(instruction.scopeLabel)")
        Self.assertSource(activityText, contains: "ProjectInstructionDiagnosticsBuilder")
        Self.assertSource(diagnosticsText, contains: "ProjectInstructionDiagnostic")
        Self.assertSource(diagnosticsText, contains: "Shared instruction scope")
        Self.assertSource(diagnosticsText, contains: "Nested instruction overlap")
        Self.assertSource(diagnosticsText, contains: "Nested instruction override")
        Self.assertSource(diagnosticsText, contains: "Conflicting instruction intent")
        Self.assertSource(modelText, excludes: "scopePath(for:")
    }

    private func assertWorkspaceModelDoesNotOwnProjectAPIs(_ modelText: String) {
        Self.assertSource(modelText, excludes: "public func addProject")
        Self.assertSource(modelText, excludes: "public func addSSHProject")
        Self.assertSource(modelText, excludes: "public func selectProject")
        Self.assertSource(modelText, excludes: "public func refreshSelectedProjectInstructions")
        Self.assertSource(modelText, excludes: "public func refreshSelectedProjectContext")
        Self.assertSource(modelText, excludes: "public func renameProject")
        Self.assertSource(modelText, excludes: "public func refreshProjectContext")
        Self.assertSource(modelText, excludes: "public func runProjectExtensionInstall")
        Self.assertSource(modelText, excludes: "public func runProjectExtensionUpdate")
        Self.assertSource(modelText, excludes: "Installed extension \\(")
        Self.assertSource(modelText, excludes: "Updated extension \\(")
        Self.assertSource(modelText, excludes: "public func removeProject")
    }
}
