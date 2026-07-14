import XCTest

final class ParitySidebarCommandPresentationGateTests: QuillCodeParityTestCase {
    func testSidebarCommandPresentationIsSharedByNativeAndHTMLSurfaces() throws {
        let presentationText = try Self.appSourceText(named: "QuillCodeSidebarCommandPresentation.swift")
        let adapterText = try Self.appSourceText(named: "QuillCodeSidebarCommandAdapter.swift")
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let sidebarActionsText = try Self.appSourceText(named: "QuillCodeSidebarActionsView.swift")
        let sidebarUtilityText = try Self.appSourceText(named: "QuillCodeSidebarUtilityActionsView.swift")
        let bulkActionsText = try Self.appSourceText(named: "QuillCodeSidebarBulkActionsView.swift")
        let threadListText = try Self.appSourceText(named: "QuillCodeSidebarThreadListView.swift")
        let threadSectionText = try Self.appSourceText(named: "QuillCodeSidebarThreadSectionView.swift")
        let threadRowText = try Self.appSourceText(named: "QuillCodeSidebarThreadRowView.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListView.swift")
        let projectRowText = try Self.appSourceText(named: "QuillCodeProjectRowView.swift")
        let htmlSidebarText = try Self.appSourceText(named: "WorkspaceHTMLSidebarRenderer.swift")
        let htmlCommandText = try Self.appSourceText(named: "WorkspaceHTMLSidebarCommandRenderer.swift")
        let iconCatalogText = try Self.appSourceText(named: "QuillCodeCommandIconCatalog.swift")

        assertCommandPresentationContract(presentationText, iconCatalogText)
        assertNativeSidebarCommandRendering(
            sidebarText,
            sidebarActionsText + sidebarUtilityText,
            threadListText,
            threadSectionText,
            threadRowText,
            bulkActionsText,
            projectListText + projectRowText
        )
        assertSidebarCommandAdapterUsage(
            adapterText,
            sidebarText + sidebarActionsText + sidebarUtilityText,
            threadListText + bulkActionsText,
            threadRowText
        )
        assertHTMLSidebarCommandRendering(htmlSidebarText, htmlCommandText)
    }

    func testSidebarSavedFiltersUseProgressiveDisclosureWithoutHorizontalChrome() throws {
        let savedFilterText = try Self.appSourceText(named: "QuillCodeSidebarSavedFilterBar.swift")
        let harnessText = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        Self.assertSource(savedFilterText, contains: "Menu {")
        Self.assertSource(savedFilterText, contains: #"Section("Chats")"#)
        Self.assertSource(savedFilterText, contains: #"Section("Actions")"#)
        Self.assertSource(savedFilterText, contains: #"Label("Select chats", systemImage: "checkmark.circle")"#)
        Self.assertSource(savedFilterText, contains: "QuillCodeSidebarSavedSearchMenuContent")
        Self.assertSource(savedFilterText, contains: #"accessibilityIdentifier("quillcode-sidebar-filter-menu")"#)
        Self.assertSource(savedFilterText, excludes: "LazyVGrid(")
        Self.assertSource(savedFilterText, excludes: horizontalFilterScrollNeedle)
        Self.assertSource(harnessText, contains: #".sidebar-filter-menu {"#)
        Self.assertSource(harnessText, contains: #".sidebar-filter-popover {"#)
        Self.assertSource(harnessText, contains: #"data-testid="sidebar-filter-menu-button""#)
        Self.assertSource(harnessText, contains: #"data-sidebar-select-chats="true""#)
        Self.assertSource(harnessText, contains: #"bulkActions.filter(action => action.id !== 'clearSelection')"#)
        Self.assertSource(harnessText, excludes: #"data-testid="sidebar-filter-bar""#)
        Self.assertSource(harnessText, excludes: ".sidebar-filter-bar::-webkit-scrollbar")
    }

    func testNativeSidebarDelegatesProjectListRendering() throws {
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListView.swift")
        let projectRowText = try Self.appSourceText(named: "QuillCodeProjectRowView.swift")
        let projectSurfaceText = try Self.appSourceText(named: "QuillCodeProjectListSurface.swift")
        let htmlProjectText = try Self.appSourceText(named: "WorkspaceHTMLSidebarProjectRenderer.swift")
        let harnessText = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        Self.assertSource(sidebarText, contains: "QuillCodeProjectListView(")
        Self.assertSource(projectListText, contains: "struct QuillCodeProjectListView")
        Self.assertSource(projectRowText, contains: "struct QuillCodeProjectRowView")
        Self.assertSource(projectListText, contains: "maxProjectListHeight")
        Self.assertSource(projectSurfaceText, contains: "public var countLabel")
        Self.assertSource(projectSurfaceText, contains: "public var compactCountLabel")
        Self.assertSource(projectSurfaceText, contains: "public var connectionSummaryLabel")
        Self.assertSource(projectSurfaceText, contains: "public var accessibilitySummary")
        Self.assertSource(projectListText, contains: "projects.compactCountLabel")
        Self.assertSource(projectListText, contains: "projects.accessibilitySummary")
        Self.assertSource(htmlProjectText, contains: #"data-testid="project-count""#)
        Self.assertSource(htmlProjectText, contains: "projects.compactCountLabel")
        Self.assertSource(harnessText, contains: "projectCountLabel")
        Self.assertSource(harnessText, contains: #"data-testid="project-count""#)
        Self.assertSource(sidebarText, excludes: "struct QuillCodeProjectRowView")
        Self.assertSource(sidebarText, excludes: "maxProjectListHeight")
    }

    func testNativeSidebarUsesCompactVisibleRowsInsideAuditedTargets() throws {
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")
        let primaryActionsText = try Self.appSourceText(named: "QuillCodeSidebarActionsView.swift")
        let utilityActionsText = try Self.appSourceText(named: "QuillCodeSidebarUtilityActionsView.swift")
        let threadRowText = try Self.appSourceText(named: "QuillCodeSidebarThreadRowView.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListView.swift")
        let projectRowText = try Self.appSourceText(named: "QuillCodeProjectRowView.swift")
        let buttonTargetText = try Self.appSourceText(named: "QuillCodeButtonHitTargetViewModifiers.swift")

        [
            "static let sidebarInteractionRowHeight: CGFloat = 32",
            "static let sidebarIconTargetSize: CGFloat = 32",
            "static let sidebarVisibleRowHeight: CGFloat = 25",
            "static let sidebarVisibleRowHorizontalPadding: CGFloat = 11",
            "static let sidebarVisibleRowRadius: CGFloat = 6"
        ].forEach { Self.assertSource(designText, contains: $0) }
        [
            primaryActionsText,
            utilityActionsText,
            threadRowText,
            projectRowText
        ].forEach { source in
            Self.assertSource(source, contains: ".quillCodeSidebarRowChrome")
        }
        Self.assertSource(buttonTargetText, contains: "QuillCodeMetrics.sidebarVisibleRowHorizontalPadding")
        Self.assertSource(buttonTargetText, contains: "QuillCodeMetrics.sidebarVisibleRowRadius")
        Self.assertSource(buttonTargetText, contains: "QuillCodeMetrics.sidebarVisibleRowHeight")
        Self.assertSource(buttonTargetText, contains: "QuillCodeMetrics.sidebarInteractionRowHeight")
        Self.assertSource(buttonTargetText, contains: "quillCodeSidebarRowTarget")
        Self.assertSource(buttonTargetText, contains: "quillCodeSidebarIconButtonTarget")
        Self.assertSource(primaryActionsText, contains: ".quillCodeSidebarRowTarget()")
        Self.assertSource(threadRowText, contains: "HStack(spacing: QuillCodeMetrics.sidebarControlSpacing)")
        Self.assertSource(projectRowText, contains: "HStack(spacing: QuillCodeMetrics.sidebarControlSpacing)")
        Self.assertSource(threadRowText, contains: ".quillCodeSidebarIconButtonTarget")
        Self.assertSource(projectRowText, contains: ".quillCodeSidebarIconButtonTarget")
        Self.assertSource(threadRowText, contains: "SidebarActivityLabelFormatter.label")
        Self.assertSource(projectListText, contains: ".projectDragReorderTarget(")
        Self.assertSource(projectListText, contains: ".onDrag {")
        Self.assertSource(projectRowText, excludes: "projectDragHandle")
        Self.assertSource(projectRowText, excludes: "line.3.horizontal")
        Self.assertSource(projectRowText, contains: "Drag to reorder")
        Self.assertSource(projectRowText, contains: "Drag the row to reorder it.")
    }

    private var horizontalFilterScrollNeedle: String {
        "ScrollView(.horizontal, showsIndicators: false) {\n            HStack(spacing: 6)"
    }

    private func assertCommandPresentationContract(
        _ presentationText: String,
        _ iconCatalogText: String
    ) {
        Self.assertSource(presentationText, contains: "struct QuillCodeSidebarCommandPresentation")
        Self.assertSource(presentationText, contains: "QuillCodeSidebarCommandMetadata")
        Self.assertSource(presentationText, contains: "metadataByCommandID")
        Self.assertSource(presentationText, contains: "static let primaryCommandIDs")
        Self.assertSource(presentationText, contains: "struct QuillCodeSidebarCommandGroup")
        Self.assertSource(presentationText, contains: "static let utilityCommandGroups")
        Self.assertSource(presentationText, contains: "static var utilityCommandIDs")
        Self.assertSource(presentationText, contains: "visibleUtilityCommandGroups")
        Self.assertSource(presentationText, contains: "static func displayTitle")
        Self.assertSource(presentationText, contains: "QuillCodeCommandIconCatalog.systemImage")
        Self.assertSource(presentationText, contains: "static func htmlIconToken")
        Self.assertSource(presentationText, excludes: "switch commandID")
        Self.assertSource(iconCatalogText, contains: "enum QuillCodeCommandIconCatalog")
    }

    private func assertNativeSidebarCommandRendering(
        _ sidebarText: String,
        _ sidebarCommandText: String,
        _ threadListText: String,
        _ threadSectionText: String,
        _ threadRowText: String,
        _ bulkActionsText: String,
        _ projectListText: String
    ) {
        Self.assertSource(sidebarText, contains: "QuillCodeSidebarThreadListView")
        Self.assertSource(sidebarText, contains: "QuillCodeProjectListView")
        Self.assertSource(threadListText, contains: "struct QuillCodeSidebarThreadListView")
        Self.assertSource(threadListText, contains: "QuillCodeSidebarThreadSectionView")
        Self.assertSource(threadSectionText, contains: "struct QuillCodeSidebarThreadSectionView")
        Self.assertSource(threadSectionText, contains: "QuillCodeSidebarThreadRowView")
        Self.assertSource(threadRowText, contains: "struct QuillCodeSidebarThreadRowView")
        Self.assertSource(bulkActionsText, contains: "struct QuillCodeSidebarBulkActionsView")
        Self.assertSource(bulkActionsText, contains: "struct QuillCodeSidebarBulkActionButton")
        Self.assertSource(projectListText, contains: "struct QuillCodeProjectListView")
        Self.assertSource(projectListText, contains: "QuillCodeProjectRowView")
        Self.assertSource(sidebarCommandText, contains: "QuillCodeSidebarCommandPresentation.primaryCommandIDs")
        Self.assertSource(sidebarCommandText, contains: "QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups")
        Self.assertSource(sidebarCommandText, contains: "QuillCodeSidebarCommandPresentation.displayTitle")
        Self.assertSource(sidebarCommandText, contains: "QuillCodeSidebarCommandPresentation.systemImage")
        Self.assertSource(sidebarText, excludes: "struct QuillCodeSidebarThreadRowView")
        Self.assertSource(sidebarText, excludes: "struct QuillCodeSidebarThreadSectionView")
        Self.assertSource(threadListText, excludes: "struct QuillCodeSidebarBulkActionButton")
        Self.assertSource(threadListText, excludes: "private struct QuillCodeSidebarThreadRowView")
        Self.assertSource(sidebarText, excludes: "struct QuillCodeProjectRowView")
        Self.assertSource(sidebarCommandText, excludes: "private func displayTitle")
        Self.assertSource(sidebarCommandText, excludes: "private func systemImage")
    }

    private func assertSidebarCommandAdapterUsage(
        _ adapterText: String,
        _ sidebarText: String,
        _ threadListText: String,
        _ threadRowText: String
    ) {
        Self.assertSource(adapterText, contains: "enum QuillCodeSidebarCommandAdapter")
        XCTAssertTrue(
            sidebarText.contains("QuillCodeSidebarCommandAdapter.workspaceCommand")
                || threadListText.contains("QuillCodeSidebarCommandAdapter.workspaceCommand")
        )
        Self.assertSource(threadRowText, contains: "QuillCodeSidebarCommandAdapter.toggleSelectionCommand")
        Self.assertSource(sidebarText, excludes: "WorkspaceCommandSurface(")
    }

    private func assertHTMLSidebarCommandRendering(
        _ htmlSidebarText: String,
        _ htmlCommandText: String
    ) {
        Self.assertSource(htmlSidebarText, contains: "WorkspaceHTMLSidebarCommandRenderer.renderPrimaryActions")
        Self.assertSource(htmlSidebarText, contains: "WorkspaceHTMLSidebarCommandRenderer.renderFooter")
        Self.assertSource(htmlCommandText, contains: "renderPrimaryActions")
        Self.assertSource(htmlCommandText, contains: "renderUtilityActions")
        Self.assertSource(htmlCommandText, contains: "QuillCodeSidebarCommandPresentation.primaryCommandIDs")
        Self.assertSource(htmlCommandText, contains: "QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups")
        Self.assertSource(htmlCommandText, contains: "QuillCodeSidebarCommandPresentation.htmlIconToken")
        Self.assertSource(htmlSidebarText, excludes: #"data-icon="plugins">Plugins"#)
        Self.assertSource(htmlCommandText, excludes: #"data-icon="plugins">Plugins"#)
    }
}
