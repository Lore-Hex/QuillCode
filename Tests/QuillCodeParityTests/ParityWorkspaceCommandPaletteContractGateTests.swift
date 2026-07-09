import XCTest

final class ParityWorkspaceCommandPaletteContractGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesCommandPaletteContract() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let paletteText = try Self.appSourceText(named: "WorkspaceCommandPaletteSurface.swift")
        let rankerText = try Self.appSourceText(named: "WorkspaceCommandPaletteRanker.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let rankerTests = try Self.appTestSourceText(named: "WorkspaceCommandPaletteRankerTests.swift")
        let builderTests = try Self.appTestSourceText(named: "WorkspaceCommandSurfaceBuilderTests.swift")
        let shortcutTests = try Self.appTestSourceText(named: "WorkspaceShortcutRegistryTests.swift")

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
        Self.assertSource(builderTests, contains: "testCommandSurfaceDecodesOlderPayloadWithoutCategoryMetadata")
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

    func testCommandPaletteRowsUseNamedDenseChromeMetrics() throws {
        let dialogText = try Self.appSourceText(named: "QuillCodeCommandPaletteDialog.swift")
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")
        let densityTests = try Self.appTestSourceText(named: "QuillCodeCommandPaletteDensityTests.swift")

        Self.assertSource(designText, containsAll: [
            "static let commandPaletteRowHorizontalPadding: CGFloat = 10",
            "static let commandPaletteRowVerticalPadding: CGFloat = 7",
            "static let commandPaletteRowRadius: CGFloat = 9"
        ])
        Self.assertSource(dialogText, containsAll: [
            ".padding(.horizontal, QuillCodeMetrics.commandPaletteRowHorizontalPadding)",
            ".padding(.vertical, QuillCodeMetrics.commandPaletteRowVerticalPadding)",
            ".quillCodeFullRowButtonTarget(radius: QuillCodeMetrics.commandPaletteRowRadius)"
        ])
        Self.assertSource(dialogText, excludes: ".padding(12)")
        Self.assertSource(densityTests, contains: "testCommandPaletteRowChromeIsCompactButKeepsHitTargetProtection")
    }
}
