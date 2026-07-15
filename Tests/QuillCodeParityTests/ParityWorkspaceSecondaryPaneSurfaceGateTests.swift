import XCTest

final class ParityWorkspaceSecondaryPaneSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesSecondaryPaneSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let extensionsText = try Self.appSourceText(named: "WorkspaceExtensionsSurface.swift")
        let memoriesText = try Self.appSourceText(named: "WorkspaceMemoriesSurface.swift")
        let automationsText = try Self.appSourceText(named: "WorkspaceAutomationsSurface.swift")
        let extensionRowText = try Self.appSourceText(named: "ProjectExtensionManifestSurface.swift")
        let memoryRowText = try Self.appSourceText(named: "MemoryNoteSurface.swift")
        let automationRowText = try Self.appSourceText(named: "AutomationWorkflowSurface.swift")

        [
            "public struct WorkspaceExtensionsSurface",
            "ProjectExtensionManifestSurface(",
            "WorkspacePaneSummaryFormatter.joinedCounts"
        ].forEach { Self.assertSource(extensionsText, contains: $0) }

        [
            "public struct WorkspaceMemoriesSurface",
            "MemoryNoteSurface(note:",
            "WorkspacePaneSummaryFormatter.joinedCounts"
        ].forEach { Self.assertSource(memoriesText, contains: $0) }

        [
            "public struct WorkspaceAutomationsSurface",
            "AutomationWorkflowSurface.init",
            "WorkspacePaneSummaryFormatter.count"
        ].forEach { Self.assertSource(automationsText, contains: $0) }

        [
            "public struct ProjectExtensionManifestSurface",
            "MCPToolDescriptor",
            "public init(from decoder: Decoder)"
        ].forEach { Self.assertSource(extensionRowText, contains: $0) }

        [
            "public struct MemoryNoteSurface",
            "memory-edit:",
            "memory-delete:"
        ].forEach { Self.assertSource(memoryRowText, contains: $0) }

        Self.assertSource(automationRowText, contains: "public struct AutomationWorkflowSurface")
        Self.assertSource(automationRowText, contains: "automation-run:")

        Self.assertSource(extensionsText, excludes: "public struct WorkspaceMemoriesSurface")
        Self.assertSource(extensionsText, excludes: "public struct WorkspaceAutomationsSurface")
        Self.assertSource(memoriesText, excludes: "public struct WorkspaceExtensionsSurface")
        Self.assertSource(memoriesText, excludes: "public struct WorkspaceAutomationsSurface")
        Self.assertSource(automationsText, excludes: "public struct WorkspaceExtensionsSurface")
        Self.assertSource(automationsText, excludes: "public struct WorkspaceMemoriesSurface")

        [
            "public struct WorkspaceExtensionsSurface",
            "public struct WorkspaceMemoriesSurface",
            "public struct WorkspaceAutomationsSurface",
            "public struct ProjectExtensionManifestSurface",
            "public struct MemoryNoteSurface",
            "public struct AutomationWorkflowSurface"
        ].forEach { Self.assertSource(surfaceText, excludes: $0) }
    }

    func testNativeSecondaryPanesUseFocusedViewFiles() throws {
        let workspaceText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let mainPaneText = try Self.appSourceText(named: "QuillCodeWorkspaceMainPaneView.swift")
        let chromeText = try Self.appSourceText(named: "QuillCodeSecondaryPanesView.swift")
        let extensionsText = try Self.appSourceText(named: "QuillCodeExtensionsPaneView.swift")
        let extensionCardsText = try Self.appSourceText(named: "QuillCodeExtensionsPaneCards.swift")
        let metadataText = try Self.appSourceText(named: "QuillCodeExtensionsPaneProbeMetadata.swift")
        let memoriesText = try Self.appSourceText(named: "QuillCodeMemoriesPaneView.swift")
        let automationsText = try Self.appSourceText(named: "QuillCodeAutomationsPaneView.swift")
        let automationMenuText = try Self.appSourceText(named: "QuillCodeAutomationCreateMenu.swift")
        let automationCardText = try Self.appSourceText(named: "QuillCodeAutomationWorkflowCard.swift")

        Self.assertSource(workspaceText, contains: "QuillCodeWorkspaceMainPaneView")

        [
            "struct QuillCodePaneCountPill",
            "struct QuillCodePaneEmptyStateView"
        ].forEach { Self.assertSource(chromeText, contains: $0) }

        [
            "struct QuillCodeExtensionsPaneView",
            "accessibilityIdentifier(\"quillcode-extensions-title\")",
            "accessibilityIdentifier(\"quillcode-extensions-add\")",
            "accessibilityIdentifier: \"quillcode-extensions-close\""
        ].forEach { Self.assertSource(extensionsText, contains: $0) }
        Self.assertSource(extensionsText, excludes: "private func extensionCard")
        Self.assertSource(extensionsText, excludes: "probeMetadataChips")
        Self.assertSource(mainPaneText, contains: "onClose: { runCommand(id: \"toggle-extensions\") }")
        Self.assertSource(extensionCardsText, contains: "ProjectExtensionManifestSurface")
        Self.assertSource(extensionCardsText, contains: "extensionCommand(id:")
        Self.assertSource(metadataText, contains: "MCPToolDescriptor")
        Self.assertSource(metadataText, contains: "probeReferenceActionGroup")
        [
            "struct QuillCodeMemoriesPaneView",
            "accessibilityIdentifier(\"quillcode-memories-title\")",
            "accessibilityIdentifier(\"quillcode-memory-add\")",
            "accessibilityIdentifier: \"quillcode-memories-close\""
        ].forEach { Self.assertSource(memoriesText, contains: $0) }
        Self.assertSource(mainPaneText, contains: "onClose: { runCommand(id: \"toggle-memories\") }")

        [
            "struct QuillCodeAutomationsPaneView",
            "QuillCodeAutomationCreateMenu",
            "QuillCodeAutomationWorkflowCard",
            "accessibilityIdentifier(\"quillcode-automations-title\")",
            "accessibilityIdentifier: \"quillcode-automations-close\""
        ].forEach { Self.assertSource(automationsText, contains: $0) }
        Self.assertSource(mainPaneText, contains: "onClose: { runCommand(id: \"toggle-automations\") }")

        Self.assertSource(automationMenuText, contains: "struct QuillCodeAutomationCreateMenu")
        Self.assertSource(automationMenuText, contains: "quillCodePlatformMenuItemTarget")
        Self.assertSource(automationCardText, contains: "struct QuillCodeAutomationWorkflowCard")
        Self.assertSource(automationCardText, contains: "automationCommand(id:")

        [
            "struct QuillCodePaneCloseButton",
            "accessibilityIdentifier(accessibilityIdentifier)",
            "quillCodeIconButtonTarget()"
        ].forEach { Self.assertSource(chromeText, contains: $0) }
        [extensionsText, memoriesText, automationsText].forEach {
            Self.assertSource($0, contains: "QuillCodePaneCloseButton")
        }

        [
            "QuillCodeExtensionsPaneView",
            "QuillCodeMemoriesPaneView",
            "QuillCodeAutomationsPaneView"
        ].forEach { Self.assertSource(mainPaneText, contains: $0) }

        [
            "QuillCodeExtensionsPaneView",
            "QuillCodeMemoriesPaneView",
            "QuillCodeAutomationsPaneView"
        ].forEach { Self.assertSource(workspaceText, excludes: $0) }

        [
            "struct QuillCodeExtensionsPaneView",
            "struct QuillCodeMemoriesPaneView",
            "struct QuillCodeAutomationsPaneView"
        ].forEach { Self.assertSource(chromeText, excludes: $0) }

        [
            "private var createMenu",
            "private func automationCard",
            "automationCommand(id:"
        ].forEach { Self.assertSource(automationsText, excludes: $0) }
    }
}
