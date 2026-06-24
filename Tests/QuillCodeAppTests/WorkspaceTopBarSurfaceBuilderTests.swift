import XCTest
import QuillCodeCore
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceTopBarSurfaceBuilderTests: XCTestCase {
    func testBuildsThreadTopBarWithSourcesRuntimeIssueAndComputerUseState() {
        let thread = ChatThread(title: "Ship QuillCode", model: TrustedRouterDefaults.synthModel)
        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "AGENTS.md",
                content: "Use Swift idioms.",
                byteCount: 17
            )
        ]
        let memories = [
            MemoryNote(
                id: "global",
                scope: .global,
                title: "Preference",
                content: "Prefer small PRs.",
                relativePath: "memories/preference.md",
                byteCount: 17
            )
        ]
        let runtimeIssue = RuntimeIssueSurface(
            severity: .warning,
            title: "Rate limited",
            message: "TrustedRouter is retrying."
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(
                appName: "QuillCode",
                projectName: "QuillCode",
                model: TrustedRouterDefaults.synthModel,
                mode: .review,
                agentStatus: TopBarAgentStatusLabel.streaming,
                computerUseStatus: .permissionStatus(
                    screenRecordingGranted: true,
                    accessibilityGranted: false
                )
            ),
            thread: thread,
            projectName: "QuillCode",
            instructions: instructions,
            memories: memories,
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: runtimeIssue
        ).surface()

        XCTAssertEqual(topBar.appName, "QuillCode")
        XCTAssertEqual(topBar.primaryTitle, "Ship QuillCode")
        XCTAssertEqual(topBar.subtitle, "QuillCode - Auto - \(TrustedRouterDefaults.synthModel)")
        XCTAssertEqual(topBar.instructionLabel, "1 instruction file loaded")
        XCTAssertEqual(topBar.instructionSources, ["AGENTS.md"])
        XCTAssertEqual(topBar.memoryLabel, "1 memory")
        XCTAssertEqual(topBar.memorySources, ["memories/preference.md"])
        XCTAssertEqual(topBar.modelLabel, TrustedRouterDefaults.synthModelDisplayName)
        XCTAssertEqual(topBar.selectedModelID, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(topBar.modeLabel, "Review")
        XCTAssertEqual(topBar.agentStatus, TopBarAgentStatusLabel.streaming)
        XCTAssertEqual(topBar.runtimeIssueLabel, "Rate limited")
        XCTAssertEqual(topBar.runtimeIssueSeverity, .warning)
        XCTAssertEqual(topBar.computerUseLabel, "Needs Accessibility")
        XCTAssertTrue(topBar.showsComputerUseSetup)
    }

    func testBuildsFallbackTitleAndNoProjectSubtitle() {
        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(),
            thread: nil,
            projectName: nil,
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [],
            runtimeIssue: nil
        ).surface()

        XCTAssertEqual(topBar.primaryTitle, "QuillCode")
        XCTAssertEqual(topBar.subtitle, "No project - Not started")
        XCTAssertEqual(topBar.instructionLabel, "No project instructions")
        XCTAssertEqual(topBar.memoryLabel, "No memories")
        XCTAssertEqual(topBar.computerUseLabel, "Needs Screen Recording + Accessibility")
        XCTAssertTrue(topBar.showsComputerUseSetup)
    }

    func testBuildsModelCatalogWithFavoritesAndUnarchivedRecents() throws {
        let favoriteModelID = TrustedRouterDefaults.synthModel
        let recentModelID = "moonshotai/kimi-k2.6"
        let archivedRecent = ChatThread(
            title: "Archived",
            model: "anthropic/claude-sonnet-4",
            isArchived: true,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let recent = ChatThread(
            title: "Recent",
            model: recentModelID,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let older = ChatThread(
            title: "Older",
            model: favoriteModelID,
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(
                model: favoriteModelID,
                computerUseStatus: .permissionStatus(
                    screenRecordingGranted: true,
                    accessibilityGranted: true
                )
            ),
            thread: older,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([
                ModelInfo(
                    id: recentModelID,
                    provider: "moonshotai",
                    displayName: "Kimi K2.6",
                    category: "Safety"
                )
            ]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [favoriteModelID],
            recentThreads: [older, recent, archivedRecent],
            runtimeIssue: nil
        ).surface()

        XCTAssertEqual(topBar.computerUseLabel, "Computer Use ready")
        XCTAssertFalse(topBar.showsComputerUseSetup)
        XCTAssertEqual(topBar.modelCategories.prefix(2).map(\.category), ["Favorites", "Recent"])
        XCTAssertEqual(try XCTUnwrap(topBar.modelCategories.first { $0.category == "Favorites" }).models.map(\.id), [favoriteModelID])
        XCTAssertEqual(try XCTUnwrap(topBar.modelCategories.first { $0.category == "Recent" }).models.map(\.id), [recentModelID])
        XCTAssertFalse(topBar.modelCategories.flatMap(\.models).contains { $0.id == archivedRecent.model && $0.badges.contains("Recent") })
    }
}
