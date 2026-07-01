import XCTest

final class ParityWorkspaceCommandPaletteContractGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesCommandPaletteContract() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let paletteText = try Self.appSourceText(named: "WorkspaceCommandPaletteSurface.swift")
        let rankerText = try Self.appSourceText(named: "WorkspaceCommandPaletteRanker.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let rankerTests = try Self.appTestSourceText(
            named: "WorkspaceCommandPaletteRankerTests.swift"
        )
        let builderTests = try Self.appTestSourceText(
            named: "WorkspaceCommandSurfaceBuilderTests.swift"
        )
        let shortcutTests = try Self.appTestSourceText(
            named: "WorkspaceShortcutRegistryTests.swift"
        )

        Self.assertSource(paletteText, containsAll: [
            "public struct WorkspaceCommandSurface",
            "public enum TopBarOverflowCommandCatalog",
            "public enum WorkspaceCommandPalette",
            "WorkspaceCommandPaletteRanker.rankedCommands",
            "WorkspaceCommandPaletteRanker.groupedCommands"
        ])
        Self.assertSource(rankerText, containsAll: [
            "enum WorkspaceCommandPaletteRanker",
            "private static func score",
            "private struct QueryRequest"
        ])
        Self.assertSource(paletteText, excludesAll: [
            "private static func score",
            "private struct QueryRequest"
        ])
        Self.assertSource(surfaceText, excludesAll: [
            "public struct WorkspaceCommandSurface",
            "public enum TopBarOverflowCommandCatalog",
            "public enum WorkspaceCommandPalette",
            "private struct QueryRequest"
        ])
        Self.assertSource(rankerTests, containsAll: [
            "testRanksCommandsByShortcutKeywordsAndTitle",
            "testGroupsUsePaletteCategoryOrder"
        ])
        Self.assertSource(builderTests, contains: "testCommandSurfaceDecodesOlderPayload")
        Self.assertSource(shortcutTests, containsAll: [
            "testShortcutRegistryLabelsSurfaceCommands",
            "testShortcutRegistryHasNoDuplicateBindings"
        ])
        Self.assertSource(broadSurfaceTests, excludesAll: [
            "testCommandPaletteRanksByShortcutKeywordsAndTitle",
            "testShortcutRegistryLabelsSurfaceCommands",
            "testWorkspaceCommandSurfaceDecodesOlderPayloadWithoutCategoryMetadata"
        ])
    }
}
