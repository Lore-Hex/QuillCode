import XCTest

final class ParityNativeWorkspaceProgressiveDisclosureGateTests: QuillCodeParityTestCase {
    func testTranscriptActionsAppearOnIntentWithoutLosingAlternateAccess() throws {
        let messageText = try Self.appSourceText(named: "QuillCodeTranscriptMessageView.swift")

        Self.assertSource(messageText, containsAll: [
            "if showsActions",
            ".onHover",
            ".focusable()",
            "focusedAction",
            "isVoiceOverEnabled",
            ".contextMenu",
            "messageContextMenu"
        ])
    }

    func testToolCardsShowLifecycleAndArtifactMetadataOnlyOnce() throws {
        let toolCardText = try Self.appSourceText(named: "QuillCodeToolCardView.swift")
        let artifactText = try Self.appSourceText(named: "QuillCodeArtifactChip.swift")
        let subtitleBuilderText = try Self.appSourceText(named: "WorkspaceToolCardSubtitleBuilder.swift")

        Self.assertSource(toolCardText, containsAll: [
            "WorkspaceToolCardSubtitleBuilder.visibleDetail",
            "card.statusDisplayLabel",
            "if hasDetails, isDetailsOpen",
            "private var toolHeaderControl",
            "private var displayedArtifacts",
            "$0.label.localizedCaseInsensitiveCompare(visibleSubtitle)"
        ])
        Self.assertSource(toolCardText, excludes: "Text(\"Raw tool data\")")
        Self.assertSource(subtitleBuilderText, containsAll: [
            "lifecycleLabels",
            "static func visibleDetail"
        ])
        Self.assertSource(artifactText, contains: ".help(artifact.detail)")
        Self.assertSource(artifactText, excludesAll: [
            "Text(artifact.detail)",
            "Capsule()"
        ])
    }

    func testCompletedToolCardsCollapseIntoCompactActivityRows() throws {
        let toolCardText = try Self.appSourceText(named: "QuillCodeToolCardView.swift")
        let targetModifierText = try Self.appSourceText(named: "QuillCodeButtonHitTargetViewModifiers.swift")

        Self.assertSource(toolCardText, containsAll: [
            "private var usesCompactActivityLayout",
            "maxWidth: usesCompactActivityLayout ? nil : 760",
            "maxWidth: usesCompactActivityLayout ? nil : .infinity",
            "private var compactDoneStatus",
            "executionContext.kind == .sshRemote"
        ])
        Self.assertSource(targetModifierText, contains: "maxWidth: CGFloat? = .infinity")
    }
}
