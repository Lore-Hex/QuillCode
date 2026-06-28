import XCTest

final class ParityWorkspaceSidebarGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesSidebarSelectionTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let threadExtensionText = try Self.appSourceText(named: "WorkspaceModelThreads.swift")
        let threadMutationText = try Self.appSourceText(named: "WorkspaceModelThreadMutation.swift")
        let selectionText = try Self.appSourceText(named: "WorkspaceSidebarSelectionEngine.swift")
        let bulkPlannerText = try Self.appSourceText(named: "WorkspaceSidebarBulkActionPlanner.swift")
        let bulkExecutorText = try Self.appSourceText(named: "WorkspaceSidebarBulkActionExecutor.swift")

        XCTAssertTrue(selectionText.contains("public struct SidebarSelectionState"), "Sidebar selection state should live beside the focused reducer.")
        XCTAssertTrue(selectionText.contains("struct WorkspaceSidebarSelectionEngine"), "Sidebar selection transitions should live in a focused reducer.")
        XCTAssertTrue(selectionText.contains("static func start"), "Selection start should be directly testable.")
        XCTAssertTrue(selectionText.contains("static func selectAll"), "Select-all behavior should be directly testable.")
        XCTAssertTrue(selectionText.contains("static func toggle"), "Selection toggles should be directly testable.")
        XCTAssertTrue(selectionText.contains("static func resolve"), "Stale-ID pruning and sidebar ordering should be directly testable.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceSidebarSelectionEngine.start"), "WorkspaceModel thread/sidebar extension should delegate selection start.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceSidebarSelectionEngine.selectAll"), "WorkspaceModel thread/sidebar extension should delegate select-all.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceSidebarSelectionEngine.toggle"), "WorkspaceModel thread/sidebar extension should delegate selection toggles.")
        XCTAssertTrue(threadExtensionText.contains("setSidebarFilter"), "WorkspaceModel thread/sidebar extension should own the saved-filter transition API.")
        XCTAssertTrue(threadExtensionText.contains("clearSidebarSelection()"), "Changing saved filters should clear hidden bulk selections.")
        XCTAssertTrue(threadMutationText.contains("WorkspaceSidebarSelectionEngine.resolve"), "WorkspaceModel thread mutation extension should delegate stale-ID pruning and ordering.")
        XCTAssertTrue(threadMutationText.contains("func filteredSidebarItems"), "Sidebar filtering should be shared by command availability and selection resolution.")
        XCTAssertTrue(threadMutationText.contains("sidebarFilter.includes"), "Sidebar selection resolution should use the active saved filter.")
        XCTAssertTrue(bulkPlannerText.contains("struct WorkspaceSidebarBulkActionPlanner"), "Sidebar bulk action planning should live in a focused planner.")
        XCTAssertTrue(bulkPlannerText.contains("static func plan"), "Sidebar bulk action plans should be directly testable.")
        XCTAssertTrue(bulkPlannerText.contains("enum FollowUpSelection"), "Bulk action selection follow-up policy should be explicit.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceSidebarBulkActionPlanner.plan"), "WorkspaceModel thread/sidebar extension should delegate bulk action target planning.")
        XCTAssertTrue(bulkExecutorText.contains("struct WorkspaceSidebarBulkActionExecutor"), "Sidebar bulk action execution should live in a focused executor.")
        XCTAssertTrue(bulkExecutorText.contains("static func execute"), "Sidebar bulk mutations should be directly testable.")
        XCTAssertTrue(threadExtensionText.contains("WorkspaceSidebarBulkActionExecutor.execute"), "WorkspaceModel thread/sidebar extension should delegate bulk action execution.")
        XCTAssertFalse(modelText.contains("public func startSidebarSelection"), "WorkspaceModel.swift should not own sidebar-selection API bodies.")
        XCTAssertFalse(modelText.contains("public func performSidebarBulkAction"), "WorkspaceModel.swift should not own sidebar bulk-action API bodies.")
        XCTAssertFalse(modelText.contains("public struct SidebarSelectionState"), "WorkspaceModel should not own sidebar selection state.")
        XCTAssertFalse(modelText.contains("selectedThreadIDs.insert"), "WorkspaceModel should not mutate sidebar selection sets directly.")
        XCTAssertFalse(modelText.contains("selectedThreadIDs.remove"), "WorkspaceModel should not mutate sidebar selection sets directly.")
        XCTAssertFalse(modelText.contains("selectedThreadIDs.intersection"), "WorkspaceModel should not prune sidebar selection sets directly.")
        XCTAssertFalse(modelText.contains("WorkspaceSidebarSelectionEngine.resolve"), "WorkspaceModel.swift should not own stale-ID pruning and ordering.")
        XCTAssertFalse(modelText.contains("let ids = selectedSidebarThreadIDs()"), "WorkspaceModel should not inline bulk selected-ID planning.")
        XCTAssertFalse(modelText.contains("case .pin(let ids):"), "WorkspaceModel should not execute sidebar bulk pin mutations inline.")
        XCTAssertFalse(modelText.contains("WorkspaceThreadLifecycleEngine.archiveThreads"), "WorkspaceModel should not execute sidebar bulk archive mutations inline.")
        XCTAssertFalse(modelText.contains("WorkspaceThreadLifecycleEngine.unarchiveThreads"), "WorkspaceModel should not execute sidebar bulk unarchive mutations inline.")
        XCTAssertFalse(modelText.contains("WorkspaceThreadLifecycleEngine.deleteThreads"), "WorkspaceModel should not execute sidebar bulk delete mutations inline.")
    }

    func testSidebarRowActionsUseSharedPlannerAndExecutor() throws {
        let workspaceViewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSidebarRowActionPlanner.swift")
        let desktopControllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let desktopNavigationText = try Self.desktopSourceText(named: "QuillCodeDesktopNavigationCoordinator.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceThreadRowMutation"), "Thread row mutations should have typed values.")
        XCTAssertTrue(plannerText.contains("enum WorkspaceProjectRowMutation"), "Project row mutations should have typed values.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSidebarRowActionPlanner"), "Sidebar row action planning should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSidebarRowMutationExecutor"), "Sidebar row mutations should execute through a focused desktop/model boundary.")
        XCTAssertTrue(workspaceViewText.contains("WorkspaceSidebarRowActionPlanner("), "WorkspaceSwiftUIView should delegate row action planning.")
        XCTAssertTrue(workspaceViewText.contains("handleSidebarRowAction"), "WorkspaceSwiftUIView should execute typed row actions.")
        XCTAssertTrue(desktopNavigationText.contains("WorkspaceSidebarRowMutationExecutor.execute"), "Desktop navigation coordinator should delegate row mutations.")
        XCTAssertFalse(workspaceViewText.contains("action.kind == .rename"), "WorkspaceSwiftUIView should not inline rename row lookup.")
        XCTAssertFalse(workspaceViewText.contains("surface.sidebar.items.first(where:"), "WorkspaceSwiftUIView should not lookup thread row titles directly.")
        XCTAssertFalse(workspaceViewText.contains("surface.projects.items.first(where:"), "WorkspaceSwiftUIView should not lookup project row names directly.")
        XCTAssertFalse(desktopControllerText.contains("WorkspaceSidebarRowMutationExecutor.execute"), "Desktop controller should not execute row mutations directly.")
        XCTAssertFalse(desktopControllerText.contains("switch action.kind"), "Desktop controller should not switch over row action kinds.")
    }

    func testSidebarCommandPresentationIsSharedByNativeAndHTMLSurfaces() throws {
        let presentationText = try Self.appSourceText(named: "QuillCodeSidebarCommandPresentation.swift")
        let adapterText = try Self.appSourceText(named: "QuillCodeSidebarCommandAdapter.swift")
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let threadListText = try Self.appSourceText(named: "QuillCodeSidebarThreadListView.swift")
        let threadRowText = try Self.appSourceText(named: "QuillCodeSidebarThreadRowView.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListView.swift")
        let htmlSidebarText = try Self.appSourceText(named: "WorkspaceHTMLSidebarRenderer.swift")
        let iconCatalogText = try Self.appSourceText(named: "QuillCodeCommandIconCatalog.swift")

        XCTAssertTrue(presentationText.contains("struct QuillCodeSidebarCommandPresentation"), "Sidebar command labels and icons should live in one focused presentation helper.")
        XCTAssertTrue(presentationText.contains("QuillCodeSidebarCommandMetadata"), "Sidebar command label/icon/test metadata should share one command table.")
        XCTAssertTrue(presentationText.contains("metadataByCommandID"), "Sidebar command presentation should centralize command metadata.")
        XCTAssertTrue(presentationText.contains("static let primaryCommandIDs"), "Primary sidebar command order should be explicit.")
        XCTAssertTrue(presentationText.contains("struct QuillCodeSidebarCommandGroup"), "Sidebar utility grouping should be a focused contract.")
        XCTAssertTrue(presentationText.contains("static let utilityCommandGroups"), "Utility sidebar command grouping should be explicit.")
        XCTAssertTrue(presentationText.contains("static var utilityCommandIDs"), "Utility sidebar command order should be derived from explicit groups.")
        XCTAssertTrue(presentationText.contains("visibleUtilityCommandGroups"), "Utility sidebar filtering should be shared by native and HTML renderers.")
        XCTAssertTrue(presentationText.contains("static func displayTitle"), "Sidebar command display titles should be shared.")
        XCTAssertTrue(presentationText.contains("QuillCodeCommandIconCatalog.systemImage"), "Native sidebar command icons should delegate to the shared icon catalog.")
        XCTAssertTrue(iconCatalogText.contains("enum QuillCodeCommandIconCatalog"), "Command icon mapping should live in one focused catalog.")
        XCTAssertTrue(presentationText.contains("static func htmlIconToken"), "HTML sidebar icon tokens should be shared.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarThreadListView"), "Native sidebar shell should delegate thread list and row rendering.")
        XCTAssertTrue(sidebarText.contains("QuillCodeProjectListView"), "Native sidebar shell should delegate project list and row rendering.")
        XCTAssertTrue(threadListText.contains("struct QuillCodeSidebarThreadListView"), "Thread list rendering should live in a focused native sidebar file.")
        XCTAssertTrue(threadListText.contains("QuillCodeSidebarThreadRowView"), "Thread list rendering should compose the focused thread row view.")
        XCTAssertTrue(threadRowText.contains("struct QuillCodeSidebarThreadRowView"), "Thread row rendering should live in a focused native sidebar file.")
        XCTAssertTrue(projectListText.contains("struct QuillCodeProjectListView"), "Project list rendering should live in a focused native sidebar file.")
        XCTAssertTrue(projectListText.contains("QuillCodeProjectRowView"), "Project row rendering should live beside project list rendering.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.primaryCommandIDs"), "Native sidebar should consume shared primary command ordering.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups"), "Native sidebar should consume shared utility command groups.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.displayTitle"), "Native sidebar should consume shared labels.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandPresentation.systemImage"), "Native sidebar should consume shared SF Symbols.")
        XCTAssertTrue(adapterText.contains("enum QuillCodeSidebarCommandAdapter"), "Sidebar command payload construction should live in a focused adapter.")
        XCTAssertTrue(sidebarText.contains("QuillCodeSidebarCommandAdapter.workspaceCommand") || threadListText.contains("QuillCodeSidebarCommandAdapter.workspaceCommand"), "Native sidebar should use the shared command adapter for bulk actions.")
        XCTAssertTrue(threadRowText.contains("QuillCodeSidebarCommandAdapter.toggleSelectionCommand"), "Native sidebar thread rows should use the shared command adapter for selection toggles.")
        XCTAssertTrue(htmlSidebarText.contains("renderPrimaryActions"), "HTML sidebar renderer should build primary sidebar actions through a helper.")
        XCTAssertTrue(htmlSidebarText.contains("renderUtilityActions"), "HTML sidebar renderer should build utility menu actions through a helper.")
        XCTAssertTrue(htmlSidebarText.contains("QuillCodeSidebarCommandPresentation.primaryCommandIDs"), "HTML sidebar renderer should consume shared primary command ordering.")
        XCTAssertTrue(htmlSidebarText.contains("QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups"), "HTML sidebar renderer should consume shared utility command groups.")
        XCTAssertTrue(htmlSidebarText.contains("QuillCodeSidebarCommandPresentation.htmlIconToken"), "HTML sidebar renderer should consume shared icon tokens.")
        XCTAssertFalse(sidebarText.contains("struct QuillCodeSidebarThreadRowView"), "Native sidebar shell should not own thread row rendering.")
        XCTAssertFalse(threadListText.contains("private struct QuillCodeSidebarThreadRowView"), "Native sidebar thread list should not own thread row rendering.")
        XCTAssertFalse(sidebarText.contains("struct QuillCodeProjectRowView"), "Native sidebar shell should not own project row rendering.")
        XCTAssertFalse(sidebarText.contains("private func displayTitle"), "Native sidebar should not maintain a second label map.")
        XCTAssertFalse(sidebarText.contains("private func systemImage"), "Native sidebar should not maintain a second icon map.")
        XCTAssertFalse(presentationText.contains("switch commandID"), "Sidebar command presentation should not repeat command-ID switches for label/icon/test metadata.")
        XCTAssertFalse(sidebarText.contains("WorkspaceCommandSurface("), "Native sidebar should not duplicate command payload construction.")
        XCTAssertFalse(htmlSidebarText.contains(#"data-icon="plugins">Plugins"#), "HTML sidebar renderer should not hard-code sidebar plugin markup.")
    }

    func testSidebarSavedFiltersWrapInsteadOfClippingHorizontally() throws {
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let harnessText = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        XCTAssertTrue(sidebarText.contains("LazyVGrid("), "Native saved-filter chips should wrap instead of relying on hidden horizontal scrolling.")
        XCTAssertTrue(sidebarText.contains(".adaptive(minimum: 100)"), "Native saved-filter chips should keep enough width for labels like Archived.")
        XCTAssertFalse(sidebarText.contains("ScrollView(.horizontal, showsIndicators: false) {\n            HStack(spacing: 6)"), "Native saved-filter chips should not hide clipped horizontal overflow.")
        XCTAssertTrue(harnessText.contains("flex-wrap: wrap;"), "HTML saved-filter chips should wrap instead of clipping at the sidebar edge.")
        XCTAssertFalse(harnessText.contains(".sidebar-filter-bar::-webkit-scrollbar"), "HTML saved-filter chips should not hide scrollbars around clipped controls.")
    }

    func testNativeSidebarDelegatesProjectListRendering() throws {
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListView.swift")

        XCTAssertTrue(sidebarText.contains("QuillCodeProjectListView("), "Native sidebar should compose a focused project-list view.")
        XCTAssertTrue(projectListText.contains("struct QuillCodeProjectListView"), "Native project-list rendering should live in a focused file.")
        XCTAssertTrue(projectListText.contains("struct QuillCodeProjectRowView"), "Native project-row rendering should live beside the project-list view.")
        XCTAssertTrue(projectListText.contains("maxProjectListHeight"), "Project rows should have an explicit scroll boundary so utility controls stay reachable.")
        XCTAssertFalse(sidebarText.contains("struct QuillCodeProjectRowView"), "Native sidebar should not own project-row rendering.")
        XCTAssertFalse(sidebarText.contains("maxProjectListHeight"), "Native sidebar should not own project-list sizing policy.")
    }

    func testWorkspaceSurfaceDelegatesSidebarSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListSurface.swift")
        let sidebarText = try Self.appSourceText(named: "QuillCodeThreadSidebarSurface.swift")
        let threadListBuilderText = try Self.appSourceText(named: "QuillCodeSidebarThreadListBuilder.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let sidebarSurfaceTests = try Self.appTestSourceText(named: "QuillCodeThreadSidebarSurfaceTests.swift")
        let sidebarIntegrationTests = try Self.appTestSourceText(named: "WorkspaceSidebarIntegrationTests.swift")

        XCTAssertTrue(projectListText.contains("public struct ProjectListSurface"), "Project list aggregate records should live in project-list contracts.")
        XCTAssertTrue(projectListText.contains("public struct ProjectItemSurface"), "Project rows should live in project-list contracts.")
        XCTAssertTrue(projectListText.contains("public enum ProjectItemActionKind"), "Project action labels should live in project-list contracts.")
        XCTAssertTrue(projectListText.contains("public struct ProjectItemActionSurface"), "Project action records should live in project-list contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarSurface"), "Thread sidebar aggregate records should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarItemSurface"), "Thread sidebar item rows should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public enum SidebarBulkActionKind"), "Thread bulk action labels should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarBulkActionSurface"), "Thread bulk action command IDs should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public enum SidebarItemActionKind"), "Thread action labels should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("public struct SidebarItemActionSurface"), "Thread action records should live in thread-sidebar contracts.")
        XCTAssertTrue(sidebarText.contains("filteredItems"), "Sidebar search filtering should be directly testable outside the aggregate workspace surface.")
        XCTAssertTrue(sidebarText.contains("selectionLabel"), "Sidebar selection copy should be directly testable outside the aggregate workspace surface.")
        XCTAssertTrue(sidebarText.contains("SidebarThreadListBuilder(items: items)"), "Sidebar aggregate should delegate thread list derivation.")
        XCTAssertTrue(threadListBuilderText.contains("struct SidebarThreadListBuilder"), "Sidebar list filtering and sectioning should live in a focused helper.")
        XCTAssertTrue(threadListBuilderText.contains("private enum SidebarThreadDateBucket"), "Sidebar date buckets should live with list sectioning.")
        XCTAssertFalse(projectListText.contains("public struct SidebarSurface"), "Project-list contracts should not own thread sidebar records.")
        XCTAssertFalse(projectListText.contains("public struct SidebarItemSurface"), "Project-list contracts should not own thread rows.")
        XCTAssertFalse(projectListText.contains("SidebarThreadListBuilder"), "Project-list contracts should not own thread filtering or sectioning.")
        XCTAssertFalse(sidebarText.contains("public struct ProjectListSurface"), "Thread-sidebar contracts should not own project list records.")
        XCTAssertFalse(sidebarText.contains("public struct ProjectItemSurface"), "Thread-sidebar contracts should not own project rows.")
        XCTAssertFalse(sidebarText.contains("ProjectItemActionSurface"), "Thread-sidebar contracts should not own project actions.")
        XCTAssertFalse(surfaceText.contains("public struct ProjectListSurface"), "WorkspaceSurface should not own project list surface records.")
        XCTAssertFalse(surfaceText.contains("public struct ProjectItemSurface"), "WorkspaceSurface should not own project row records.")
        XCTAssertFalse(surfaceText.contains("public enum ProjectItemActionKind"), "WorkspaceSurface should not own project action labels.")
        XCTAssertFalse(surfaceText.contains("public struct ProjectItemActionSurface"), "WorkspaceSurface should not own project action records.")
        XCTAssertFalse(surfaceText.contains("public struct SidebarSurface"), "WorkspaceSurface should not own sidebar aggregate records.")
        XCTAssertFalse(surfaceText.contains("public struct SidebarItemSurface"), "WorkspaceSurface should not own sidebar item rows.")
        XCTAssertFalse(surfaceText.contains("public enum SidebarBulkActionKind"), "WorkspaceSurface should not own bulk action labels.")
        XCTAssertFalse(surfaceText.contains("public struct SidebarBulkActionSurface"), "WorkspaceSurface should not own bulk action records.")
        XCTAssertFalse(surfaceText.contains("public enum SidebarItemActionKind"), "WorkspaceSurface should not own thread action labels.")
        XCTAssertFalse(surfaceText.contains("public struct SidebarItemActionSurface"), "WorkspaceSurface should not own thread action records.")
        XCTAssertFalse(surfaceText.contains("filteredItems"), "WorkspaceSurface should not own sidebar search filtering.")
        XCTAssertFalse(surfaceText.contains("selectionLabel(count:"), "WorkspaceSurface should not own sidebar selection copy.")
        XCTAssertFalse(sidebarText.contains("private enum SidebarThreadDateBucket"), "Sidebar aggregate should not own date bucketing.")
        XCTAssertTrue(sidebarSurfaceTests.contains("testSidebarSearchExcludesHiddenToolFeedback"), "Sidebar search filtering should live in focused sidebar surface tests.")
        XCTAssertTrue(sidebarSurfaceTests.contains("workspace manager"), "Sidebar negative search coverage should live in focused sidebar surface tests.")
        XCTAssertTrue(sidebarIntegrationTests.contains("testBulkSelectionArchivesAndDeletesChats"), "Sidebar bulk selection integration should live in focused sidebar integration tests.")
        XCTAssertFalse(broadSurfaceTests.contains("testSidebarSearchExcludesHiddenToolFeedback"), "WorkspaceSurfaceTests should not own sidebar search filtering behavior.")
        XCTAssertFalse(broadSurfaceTests.contains("testSidebarSearchFiltersByThreadTitleSubtitleAndTranscriptContent"), "WorkspaceSurfaceTests should not own sidebar search projection behavior.")
        XCTAssertFalse(broadSurfaceTests.contains("testSidebarBulkSelectionArchivesAndDeletesChats"), "WorkspaceSurfaceTests should not own sidebar bulk-action integration.")
    }

    func testWorkspaceSurfaceDelegatesNavigationSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceNavigationSurfaceBuilder.swift")

        XCTAssertTrue(surfaceText.contains("WorkspaceNavigationSurfaceBuilder("), "WorkspaceSurface should delegate navigation surface assembly.")
        XCTAssertTrue(builderText.contains("struct WorkspaceNavigationSurfaceBuilder"), "Navigation surface assembly should live in a focused builder.")
        XCTAssertTrue(builderText.contains("ProjectListSurface("), "Project list construction should live in the navigation builder.")
        XCTAssertTrue(builderText.contains("SidebarSurface("), "Sidebar construction should live in the navigation builder.")
        XCTAssertTrue(builderText.contains("SidebarBulkActionSurface"), "Sidebar bulk-action projection should live in the navigation builder.")
        XCTAssertTrue(builderText.contains("activeSidebarFilter"), "Navigation surface builder should receive the active sidebar saved filter.")
        XCTAssertTrue(builderText.contains("visibleSidebarItems"), "Navigation surface builder should derive visible sidebar rows once.")
        XCTAssertTrue(builderText.contains("selectedThreadIDs.intersection"), "Navigation surface builder should defend against hidden stale selections.")
        XCTAssertFalse(surfaceText.contains("private func sidebarBulkActions"), "WorkspaceSurface should not own sidebar bulk-action projection.")
        XCTAssertFalse(surfaceText.contains("private func projectItems"), "WorkspaceSurface should not own project row projection.")
        XCTAssertFalse(surfaceText.contains("ProjectListSurface("), "WorkspaceSurface should not construct project lists directly.")
        XCTAssertFalse(surfaceText.contains("SidebarSurface("), "WorkspaceSurface should not construct sidebars directly.")
    }

    func testPlaywrightSidebarAndProjectFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let sidebarSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("sidebar.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )
        let sidebarFlowNames = [
            "searches and reopens an existing chat",
            "starts a new chat from the sidebar action",
            "manages chat lifecycle from the sidebar",
            "groups sidebar chats by recency bucket",
            "bulk-selects chats from the sidebar",
            "filters sidebar chats with saved filters",
            "manages projects from the sidebar",
            "adds an SSH remote project from command palette and slash command"
        ]

        XCTAssertTrue(sidebarSpecText.contains("harnessURL()"), "Focused sidebar flows should reuse the shared harness URL helper.")
        XCTAssertTrue(sidebarSpecText.contains("clickSidebarTool"), "Focused sidebar flows should reuse shared sidebar utility navigation.")
        XCTAssertTrue(sidebarSpecText.contains("clickProjectAction"), "Project row action coverage should live with focused sidebar/project flows.")
        XCTAssertTrue(sidebarSpecText.contains("ssh://quill@feather.local/srv/quill"), "Focused sidebar/project flows should cover SSH remote project creation.")
        XCTAssertFalse(coreSpecText.contains("clickProjectAction"), "Broad core spec should not own project row action helpers.")
        XCTAssertFalse(coreSpecText.contains("replaceFocusedText"), "Broad core spec should not own sidebar search editing helpers.")
        for flowName in sidebarFlowNames {
            XCTAssertTrue(sidebarSpecText.contains(flowName), "\(flowName) should live in sidebar.spec.ts.")
            XCTAssertFalse(coreSpecText.contains(flowName), "\(flowName) should not drift back into core.spec.ts.")
        }
    }
}
