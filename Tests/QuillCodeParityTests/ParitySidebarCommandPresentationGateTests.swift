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

    func testSidebarSavedFiltersWrapInsteadOfClippingHorizontally() throws {
        let savedFilterText = try Self.appSourceText(named: "QuillCodeSidebarSavedFilterBar.swift")
        let harnessText = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        Self.assertSource(savedFilterText, contains: "LazyVGrid(")
        Self.assertSource(savedFilterText, contains: ".adaptive(minimum: 100)")
        Self.assertSource(savedFilterText, excludes: horizontalFilterScrollNeedle)
        Self.assertSource(harnessText, contains: "flex-wrap: wrap;")
        Self.assertSource(harnessText, excludes: ".sidebar-filter-bar::-webkit-scrollbar")
    }

    func testNativeSidebarDelegatesProjectListRendering() throws {
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let projectListText = try Self.appSourceText(named: "QuillCodeProjectListView.swift")
        let projectRowText = try Self.appSourceText(named: "QuillCodeProjectRowView.swift")

        Self.assertSource(sidebarText, contains: "QuillCodeProjectListView(")
        Self.assertSource(projectListText, contains: "struct QuillCodeProjectListView")
        Self.assertSource(projectRowText, contains: "struct QuillCodeProjectRowView")
        Self.assertSource(projectListText, contains: "maxProjectListHeight")
        Self.assertSource(sidebarText, excludes: "struct QuillCodeProjectRowView")
        Self.assertSource(sidebarText, excludes: "maxProjectListHeight")
    }

    func testNativeSidebarUsesCompactVisibleRowsInsideAuditedTargets() throws {
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")
        let primaryActionsText = try Self.appSourceText(named: "QuillCodeSidebarActionsView.swift")
        let utilityActionsText = try Self.appSourceText(named: "QuillCodeSidebarUtilityActionsView.swift")
        let threadRowText = try Self.appSourceText(named: "QuillCodeSidebarThreadRowView.swift")
        let projectRowText = try Self.appSourceText(named: "QuillCodeProjectRowView.swift")
        let buttonTargetText = try Self.appSourceText(named: "QuillCodeButtonHitTargetViewModifiers.swift")

        [
            "static let sidebarVisibleRowHeight: CGFloat = 29",
            "static let sidebarVisibleRowHorizontalPadding: CGFloat = 12",
            "static let sidebarVisibleRowRadius: CGFloat = 7"
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
        Self.assertSource(buttonTargetText, contains: "QuillCodeMetrics.minimumHitTarget")
        Self.assertSource(threadRowText, contains: ".quillCodeIconButtonTarget")
        Self.assertSource(projectRowText, contains: ".quillCodeIconButtonTarget")
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
