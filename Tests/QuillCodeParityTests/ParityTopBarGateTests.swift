import XCTest

final class ParityTopBarGateTests: QuillCodeParityTestCase {
    func testTopBarViewsDelegateStatusPresentationSemantics() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let htmlRendererText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")
        let presentationText = try Self.appSourceText(named: "QuillCodeTopBarStatusPresentation.swift")

        XCTAssertTrue(presentationText.contains("public enum TopBarAgentStatusLabel"), "Shared status labels should live beside top-bar presentation semantics.")
        XCTAssertTrue(presentationText.contains("struct TopBarStatusPresentation"), "Top-bar status semantics should live in a focused presentation value.")
        XCTAssertTrue(presentationText.contains("static func agentStatus"), "Agent status classification should be directly testable.")
        XCTAssertTrue(presentationText.contains("struct TopBarRuntimeIssuePresentation"), "Runtime issue pill semantics should be directly testable.")
        XCTAssertTrue(topBarViewText.contains("topBar.agentStatusPresentation"), "Native top bar should use shared status presentation.")
        XCTAssertTrue(topBarViewText.contains("topBar.runtimeIssuePresentation"), "Native top bar should use shared runtime issue presentation.")
        XCTAssertTrue(htmlRendererText.contains("topBar.agentStatusPresentation"), "HTML top bar should use shared status presentation.")
        XCTAssertTrue(htmlRendererText.contains("topBar.runtimeIssuePresentation"), "HTML top bar should use shared runtime issue presentation.")
        XCTAssertFalse(topBarViewText.contains("lowercasedStatus.contains"), "Top-bar view should not own status string classification.")
        XCTAssertFalse(topBarViewText.contains("runtimeIssueSeverity == .error"), "Top-bar view should not own runtime issue tone classification.")
        XCTAssertFalse(htmlRendererText.contains("runtimeIssueSeverity?.rawValue"), "HTML renderer should not own runtime issue tone fallback logic.")
    }

    func testNativeTopBarKeepsCodexStyleChromeQuiet() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")

        XCTAssertTrue(topBarViewText.contains("contextLabel"), "Native top bar should preserve a quiet leading context label.")
        XCTAssertTrue(topBarViewText.contains("threadTitle"), "Native top bar should center the active thread title.")
        XCTAssertTrue(topBarViewText.contains("showsActivityHairline"), "Native top bar should show run/error state as a subtle hairline instead of another pill.")
        XCTAssertTrue(designText.contains("static let topBarHeight: CGFloat = 40"), "Native top bar should keep a compact Codex-style height.")
        XCTAssertFalse(topBarViewText.contains("statusIndicator"), "Native top bar should not reintroduce a permanent status pill.")
        XCTAssertFalse(topBarViewText.contains("QuillCodeTopBarPill"), "Native top bar should not reintroduce runtime issue pills into the main chrome.")
    }

    func testTopBarAgentStatusLabelsAreSharedByRuntimePaths() throws {
        let appStateText = try Self.appSourceText(named: "AppState.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let workspaceRuntimeText = [modelText, reviewExtensionText].joined(separator: "\n")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentStatusBuilder.swift")
        let mcpRuntimeText = try Self.appSourceText(named: "WorkspaceMCPRuntime.swift")
        let terminalLifecycleText = try Self.appSourceText(named: "WorkspaceTerminalLifecyclePlanner.swift")

        XCTAssertTrue(appStateText.contains("agentStatus: String = TopBarAgentStatusLabel.idle"), "Root state should use the shared idle label default.")
        XCTAssertTrue(workspaceRuntimeText.contains("TopBarAgentStatusLabel.running"), "Workspace runtime paths should use shared running status copy.")
        XCTAssertTrue(terminalLifecycleText.contains("TopBarAgentStatusLabel.terminal"), "Terminal lifecycle planner should use shared terminal status copy.")
        XCTAssertTrue(builderText.contains("TopBarAgentStatusLabel.streaming"), "Agent progress builder should use shared streaming status copy.")
        XCTAssertTrue(mcpRuntimeText.contains("TopBarAgentStatusLabel.failed"), "MCP runtime should use shared failed status copy.")
        XCTAssertFalse(workspaceRuntimeText.contains("refreshTopBar(agentStatus: \""), "Workspace runtime paths should not pass raw lifecycle status strings to the top bar.")
        XCTAssertFalse(builderText.contains("return \"Running\""), "Agent progress builder should not return raw lifecycle status strings.")
        XCTAssertFalse(builderText.contains("return \"Failed\""), "Agent progress builder should not return raw lifecycle status strings.")
        XCTAssertFalse(mcpRuntimeText.contains("agentStatus: \"Idle\""), "MCP runtime should not return raw idle status strings.")
        XCTAssertFalse(mcpRuntimeText.contains("agentStatus: \"Failed\""), "MCP runtime should not return raw failed status strings.")
    }

    func testRuntimeStatusLabelsAreSharedByAuthAndIssuePaths() throws {
        let labelsText = try Self.appSourceText(named: "QuillCodeRuntimeStatusLabel.swift")
        let runtimeFactoryText = try Self.appSourceText(named: "RuntimeFactory.swift")
        let issueBuilderText = try Self.appSourceText(named: "WorkspaceRuntimeIssueBuilder.swift")
        let desktopControllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(labelsText.contains("public enum QuillCodeRuntimeStatusLabel"), "Runtime/auth status labels should live in one focused label boundary.")
        XCTAssertTrue(runtimeFactoryText.contains("QuillCodeRuntimeStatusLabel.signInWithTrustedRouter"), "RuntimeFactory should use shared sign-in-needed copy.")
        XCTAssertTrue(runtimeFactoryText.contains("QuillCodeRuntimeStatusLabel.developerKeyNeeded"), "RuntimeFactory should use shared developer-key-needed copy.")
        XCTAssertTrue(runtimeFactoryText.contains("QuillCodeRuntimeStatusLabel.trustedRouterReady"), "RuntimeFactory should use shared TrustedRouter-ready copy.")
        XCTAssertTrue(issueBuilderText.contains("case QuillCodeRuntimeStatusLabel.signInWithTrustedRouter"), "Runtime issue builder should branch on shared sign-in-needed copy.")
        XCTAssertTrue(issueBuilderText.contains("case QuillCodeRuntimeStatusLabel.developerKeyNeeded"), "Runtime issue builder should branch on shared developer-key-needed copy.")
        XCTAssertTrue(desktopControllerText.contains("QuillCodeRuntimeStatusLabel.signInFailed"), "Desktop sign-in failure should use shared runtime status copy.")
        XCTAssertFalse(runtimeFactoryText.contains("status: \"Mock LLM\""), "RuntimeFactory should not emit raw mock status copy.")
        XCTAssertFalse(runtimeFactoryText.contains("status: \"Sign in with TrustedRouter\""), "RuntimeFactory should not emit raw sign-in-needed status copy.")
        XCTAssertFalse(runtimeFactoryText.contains("status: \"Developer key needed\""), "RuntimeFactory should not emit raw developer-key-needed status copy.")
        XCTAssertFalse(issueBuilderText.contains("case \"Sign in with TrustedRouter\""), "Runtime issue builder should not branch on raw sign-in-needed copy.")
        XCTAssertFalse(issueBuilderText.contains("case \"Developer key needed\""), "Runtime issue builder should not branch on raw developer-key-needed copy.")
        XCTAssertFalse(desktopControllerText.contains("setAgentStatus(\"Sign-in failed\""), "Desktop controller should not emit raw sign-in-failed status copy.")
    }

    func testWorkspaceSurfaceDelegatesModelCatalogBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceModelCatalogSurfaceBuilder.swift")
        let topBarBuilderText = try Self.appSourceText(named: "WorkspaceTopBarSurfaceBuilder.swift")

        XCTAssertTrue(builderText.contains("struct WorkspaceModelCatalogSurfaceBuilder"), "Model picker category construction should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func modelLabel()"), "Model picker label formatting should be directly testable.")
        XCTAssertTrue(builderText.contains("func categories()"), "Model picker category construction should be directly testable.")
        XCTAssertTrue(builderText.contains("normalizedUniqueModelIDs"), "Model picker builder should normalize favorites and recents defensively.")
        XCTAssertTrue(topBarBuilderText.contains("WorkspaceModelCatalogSurfaceBuilder("), "Top-bar builder should delegate model catalog presentation construction.")
        XCTAssertFalse(surfaceText.contains("WorkspaceModelCatalogSurfaceBuilder("), "WorkspaceSurface should not construct model catalog presentation directly.")
        XCTAssertFalse(surfaceText.contains("func modelCategories(selectedModelID:"), "WorkspaceSurface should not own model category construction.")
        XCTAssertFalse(surfaceText.contains("func modelOption("), "WorkspaceSurface should not own model option badge construction.")
        XCTAssertFalse(surfaceText.contains("func favoriteModelIDs()"), "WorkspaceSurface should not own model favorite normalization.")
        XCTAssertFalse(surfaceText.contains("func recentModelIDs("), "WorkspaceSurface should not own recent model normalization.")
    }

    func testWorkspaceSurfaceDelegatesTopBarSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let topBarText = try Self.appSourceText(named: "QuillCodeTopBarSurface.swift")
        let searchFilterText = try Self.appSourceText(named: "ModelCategorySearchFilter.swift")

        XCTAssertTrue(topBarText.contains("public struct TopBarSurface"), "Top-bar aggregate records should live beside top-bar-specific behavior.")
        XCTAssertTrue(topBarText.contains("public struct ModelCategorySurface"), "Model category rows should live beside model picker filtering.")
        XCTAssertTrue(topBarText.contains("public struct ModelMetadataRowSurface"), "Model metadata rows should live beside model option compatibility behavior.")
        XCTAssertTrue(topBarText.contains("public struct ModelOptionSurface"), "Model option records should live beside model option metadata construction.")
        XCTAssertTrue(topBarText.contains("filteredModelCategories"), "Model picker filtering should be directly testable outside the aggregate workspace surface.")
        XCTAssertTrue(topBarText.contains("ModelCategorySearchFilter.filter"), "Top-bar surface should delegate model picker search policy to the focused filter.")
        XCTAssertTrue(searchFilterText.contains("enum ModelCategorySearchFilter"), "Model picker search policy should live in a focused filter.")
        XCTAssertTrue(searchFilterText.contains("static func filter("), "Model picker search policy should be directly testable.")
        XCTAssertTrue(searchFilterText.contains("normalizedTerms"), "Model picker query normalization should be isolated from the surface DTO.")
        XCTAssertFalse(topBarText.contains("includesFavoriteTerm"), "Top-bar surface should not own Favorites special-case search policy.")
        XCTAssertFalse(topBarText.contains("metadataRows.map"), "Top-bar surface should not own model metadata haystack construction.")
        XCTAssertFalse(surfaceText.contains("public struct TopBarSurface"), "WorkspaceSurface should not own top-bar surface records.")
        XCTAssertFalse(surfaceText.contains("public struct ModelCategorySurface"), "WorkspaceSurface should not own model category records.")
        XCTAssertFalse(surfaceText.contains("public struct ModelMetadataRowSurface"), "WorkspaceSurface should not own model metadata rows.")
        XCTAssertFalse(surfaceText.contains("public struct ModelOptionSurface"), "WorkspaceSurface should not own model option records.")
        XCTAssertFalse(surfaceText.contains("filteredModelCategories"), "WorkspaceSurface should not own model picker filtering.")
    }

    func testNativeModelPickerKeepsRowsAndDetailsFocused() throws {
        let pickerText = try Self.appSourceText(named: "QuillCodeModelPickerView.swift")
        let rowText = try Self.appSourceText(named: "QuillCodeModelPickerRows.swift")

        XCTAssertTrue(pickerText.contains("struct QuillCodeModelPickerView"), "Model picker trigger and popover shell should live in the picker view.")
        XCTAssertTrue(pickerText.contains("@State private var searchText"), "Model picker search state should stay with the popover shell.")
        XCTAssertTrue(pickerText.contains("ensureHighlightedModel"), "Keyboard highlight behavior should stay with the popover shell.")
        XCTAssertTrue(rowText.contains("struct QuillCodeModelCategorySection"), "Model picker category rows should live in a focused row file.")
        XCTAssertTrue(rowText.contains("struct QuillCodeModelRow"), "Model picker option rows should live in a focused row file.")
        XCTAssertTrue(rowText.contains("struct QuillCodeModelDetails"), "Model picker details should live in a focused row file.")
        XCTAssertTrue(rowText.contains("QuillCodePressableButtonStyle"), "Model picker row actions should keep shared 0.96 press feedback.")
        XCTAssertTrue(rowText.contains("QuillCodeMetrics.minimumHitTarget"), "Model picker row actions should keep minimum hit targets.")
        XCTAssertFalse(pickerText.contains("struct QuillCodeModelRow"), "Model picker shell should not own option-row rendering.")
        XCTAssertFalse(pickerText.contains("struct QuillCodeModelDetails"), "Model picker shell should not own model details rendering.")
        XCTAssertFalse(pickerText.contains("badgeForeground"), "Model picker shell should not own model badge tone policy.")
    }

    func testWorkspaceSurfaceDelegatesTopBarSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceTopBarSurfaceBuilder.swift")

        XCTAssertTrue(surfaceText.contains("WorkspaceTopBarSurfaceBuilder("), "WorkspaceSurface should delegate top-bar surface assembly.")
        XCTAssertTrue(builderText.contains("struct WorkspaceTopBarSurfaceBuilder"), "Top-bar surface assembly should live in a focused builder.")
        XCTAssertTrue(builderText.contains("func surface() -> TopBarSurface"), "Top-bar surface assembly should be directly testable.")
        XCTAssertTrue(builderText.contains("recentModelIDs()"), "Recent model projection should live with top-bar model presentation.")
        XCTAssertFalse(surfaceText.contains("TopBarSurface("), "WorkspaceSurface should not construct top-bar records directly.")
        XCTAssertFalse(surfaceText.contains("private func modelCatalogBuilder"), "WorkspaceSurface should not own top-bar model catalog builder plumbing.")
    }

    func testModelPickerWorkspaceIntegrationCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let modelPickerTests = try Self.appTestSourceText(named: "WorkspaceModelPickerSurfaceIntegrationTests.swift")
        let topBarTests = try Self.appTestSourceText(named: "QuillCodeTopBarSurfaceTests.swift")
        let modelPickerCases = [
            "testSurfaceGroupsCustomModelCatalogByCategory",
            "testTopBarFiltersModelCatalogByProviderCategoryAndModel",
            "testSurfaceKeepsUnknownSelectedModelVisible",
            "testModelPickerShowsRecentModelsAndBadges",
            "testModelPickerShowsFavoriteModelsBeforeRecent"
        ]

        for testCase in modelPickerCases {
            XCTAssertTrue(
                modelPickerTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceModelPickerSurfaceIntegrationTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }

        XCTAssertTrue(
            topBarTests.contains("func testModelOptionDecodesOlderPayloadWithoutBadges"),
            "Model option Codable compatibility belongs with the top-bar surface contract."
        )
        XCTAssertFalse(
            broadSurfaceTests.contains("func testModelOptionDecodesOlderPayloadWithoutBadges"),
            "Broad workspace surface tests should not duplicate focused top-bar Codable coverage."
        )
    }
}
