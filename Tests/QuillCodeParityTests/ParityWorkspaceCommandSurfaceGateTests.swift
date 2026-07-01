import XCTest

final class ParityWorkspaceCommandSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesCommandSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceCommandSurfaceBuilder.swift")
        let staticCatalogText = try Self.appSourceText(named: "WorkspaceCommandStaticCatalog.swift")
        let threadCatalogText = try Self.appSourceText(named: "WorkspaceThreadCommandCatalog.swift")
        let gitCatalogText = try Self.appSourceText(named: "WorkspaceGitCommandCatalog.swift")
        let projectCatalogText = try Self.appSourceText(named: "WorkspaceProjectCommandCatalog.swift")

        Self.assertSource(builderText, containsAll: [
            "struct WorkspaceCommandSurfaceBuilder",
            "var commands: [WorkspaceCommandSurface]",
            "WorkspaceThreadCommandCatalog.commands",
            "WorkspaceGitCommandCatalog.commands",
            "WorkspaceProjectCommandCatalog.localActionCommands",
            "WorkspaceCommandStaticCatalog.workspaceCommands"
        ])
        Self.assertSource(staticCatalogText, contains: "enum WorkspaceCommandStaticCatalog")
        Self.assertSource(threadCatalogText, containsAll: [
            "enum WorkspaceThreadCommandCatalog",
            "struct WorkspaceThreadCommandAvailability"
        ])
        Self.assertSource(gitCatalogText, contains: "enum WorkspaceGitCommandCatalog")
        Self.assertSource(projectCatalogText, containsAll: [
            "enum WorkspaceProjectCommandCatalog",
            "static func localActionCommands",
            "static func mcpLifecycleCommands",
            "static func extensionInstallCommands",
            "static func extensionUpdateCommands"
        ])
        Self.assertSource(builderText, excludesAll: [
            "private var localActionCommands",
            "private var mcpLifecycleCommands",
            "private var gitCommands"
        ])
        Self.assertSource(surfaceText, contains: "WorkspaceCommandSurfaceBuilder(")
        Self.assertSource(surfaceText, excludesAll: [
            "private func commands() -> [WorkspaceCommandSurface]",
            "let localActionCommands =",
            "let mcpLifecycleCommands =",
            "let extensionInstallCommands =",
            "let extensionUpdateCommands ="
        ])
    }
}
