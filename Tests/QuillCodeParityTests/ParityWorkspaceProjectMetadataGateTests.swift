import XCTest

final class ParityWorkspaceProjectMetadataGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesProjectMetadataLoading() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let projectExtensionText = try Self.appSourceText(named: "WorkspaceModelProjects.swift")
        let loaderText = try Self.appSourceText(named: "WorkspaceProjectMetadataLoader.swift")

        Self.assertSource(loaderText, contains: "enum WorkspaceProjectMetadataLoader")
        [
            "ProjectInstructionLoader.load",
            "LocalEnvironmentActionLoader.load",
            "ProjectExtensionManifestLoader.load",
            "MemoryNoteLoader.loadProject",
            "SSHRemoteProjectContextLoader.load"
        ].forEach { Self.assertSource(loaderText, contains: $0) }

        Self.assertSource(projectExtensionText, contains: "WorkspaceProjectMetadataLoader.loadLocal")
        Self.assertSource(modelText, contains: "WorkspaceProjectContextRefresher.refreshRemoteProjectContext")
        [
            "ProjectInstructionLoader.load",
            "LocalEnvironmentActionLoader.load",
            "ProjectExtensionManifestLoader.load",
            "MemoryNoteLoader.loadProject",
            "SSHRemoteProjectContextLoader.load"
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }

    func testWorkspaceModelTestsDoNotOwnPureProjectLoaderCoverage() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let focusedLoaderTests = [
            try Self.appTestSourceText(named: "ProjectInstructionLoaderTests.swift"),
            try Self.appTestSourceText(named: "LocalEnvironmentActionLoaderTests.swift"),
            try Self.appTestSourceText(named: "ProjectExtensionManifestLoaderTests.swift"),
            try Self.appTestSourceText(named: "MemoryNoteLoaderTests.swift")
        ].joined(separator: "\n")

        [
            "ProjectInstructionLoader.load",
            "LocalEnvironmentActionLoader.load",
            "ProjectExtensionManifestLoader.load",
            "MemoryNoteLoader.loadProject"
        ].forEach {
            Self.assertSource(focusedLoaderTests, contains: $0)
            Self.assertSource(modelTests, excludes: $0)
        }
    }

    func testProjectInstructionScopesStayInCorePromptAndActivityContracts() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let projectInstructionText = try Self.coreSourceText(named: "ProjectInstruction.swift")
        let loaderText = try Self.appSourceText(named: "ProjectInstructionLoader.swift")
        let promptText = try Self.agentSourceText(named: "TrustedRouterPromptBuilder.swift")
        let activityText = try Self.appSourceText(named: "WorkspaceActivitySourceSurfaceBuilder.swift")
        let diagnosticsText = try Self.appSourceText(named: "ProjectInstructionDiagnosticsBuilder.swift")

        [
            "public var scopePath",
            "static func scopePath(for instructionPath",
            "static func scopeLabel(for scopePath"
        ].forEach { Self.assertSource(projectInstructionText, contains: $0) }
        Self.assertSource(loaderText, contains: "ProjectInstruction.scopePath(for: relativePath)")
        [
            "Scope: \\(instruction.scopeLabel)",
            "Apply whole-project instructions everywhere"
        ].forEach { Self.assertSource(promptText, contains: $0) }
        Self.assertSource(activityText, contains: "Scope: \\(instruction.scopeLabel)")
        Self.assertSource(activityText, contains: "ProjectInstructionDiagnosticsBuilder")
        [
            "ProjectInstructionDiagnostic",
            "Shared instruction scope",
            "Nested instruction override",
            "Conflicting instruction intent"
        ].forEach { Self.assertSource(diagnosticsText, contains: $0) }
        Self.assertSource(modelText, excludes: "scopePath(for:")
    }
}
