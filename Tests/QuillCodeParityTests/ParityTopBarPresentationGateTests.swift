import XCTest

final class ParityTopBarPresentationGateTests: QuillCodeParityTestCase {
    func testTopBarViewsDelegateStatusPresentationSemantics() throws {
        let topBarViewText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let htmlRendererText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")
        let presentationText = try Self.appSourceText(named: "QuillCodeTopBarStatusPresentation.swift")
        let toneColorText = try Self.appSourceText(named: "QuillCodeTopBarToneColor.swift")

        [
            "public enum TopBarAgentStatusLabel",
            "struct TopBarStatusPresentation",
            "static func agentStatus",
            "struct TopBarRuntimeIssuePresentation",
            "topBarHelpText",
            "topBarAccessibilityLabel"
        ].forEach { Self.assertSource(presentationText, contains: $0) }
        [
            "topBar.topBarHelpText",
            "topBar.topBarAccessibilityLabel"
        ].forEach { Self.assertSource(topBarViewText, contains: $0) }
        [
            "topBar.agentStatusPresentation",
            "topBar.runtimeIssuePresentation"
        ].forEach { Self.assertSource(toneColorText, contains: $0) }
        [
            "topBar.agentStatusPresentation",
            "topBar.runtimeIssuePresentation",
            "topBar.topBarAccessibilityLabel"
        ].forEach { Self.assertSource(htmlRendererText, contains: $0) }
        [
            "lowercasedStatus.contains",
            "runtimeIssueSeverity == .error"
        ].forEach { Self.assertSource(topBarViewText, excludes: $0) }
        Self.assertSource(htmlRendererText, excludes: "runtimeIssueSeverity?.rawValue")
    }

    func testTopBarAgentStatusLabelsAreSharedByRuntimePaths() throws {
        let appStateText = try Self.appSourceText(named: "AppState.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let workspaceRuntimeText = [modelText, reviewExtensionText].joined(separator: "\n")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentStatusBuilder.swift")
        let mcpRuntimeText = try Self.appSourceText(named: "WorkspaceMCPRuntime.swift")
        let terminalLifecycleText = try Self.appSourceText(named: "WorkspaceTerminalLifecyclePlanner.swift")

        Self.assertSource(appStateText, contains: "agentStatus: String = TopBarAgentStatusLabel.idle")
        Self.assertSource(workspaceRuntimeText, contains: "TopBarAgentStatusLabel.running")
        Self.assertSource(terminalLifecycleText, contains: "TopBarAgentStatusLabel.terminal")
        Self.assertSource(builderText, contains: "TopBarAgentStatusLabel.streaming")
        Self.assertSource(mcpRuntimeText, contains: "TopBarAgentStatusLabel.failed")
        Self.assertSource(workspaceRuntimeText, excludes: "refreshTopBar(agentStatus: \"")
        [
            "return \"Running\"",
            "return \"Failed\""
        ].forEach { Self.assertSource(builderText, excludes: $0) }
        [
            "agentStatus: \"Idle\"",
            "agentStatus: \"Failed\""
        ].forEach { Self.assertSource(mcpRuntimeText, excludes: $0) }
    }

    func testRuntimeStatusLabelsAreSharedByAuthAndIssuePaths() throws {
        let labelsText = try Self.appSourceText(named: "QuillCodeRuntimeStatusLabel.swift")
        let runtimeFactoryText = try Self.appSourceText(named: "RuntimeFactory.swift")
        let issueBuilderText = try Self.appSourceText(named: "WorkspaceRuntimeIssueBuilder.swift")
        let desktopSignInText = try Self.desktopSourceText(named: "QuillCodeDesktopSignInCoordinator.swift")

        Self.assertSource(labelsText, contains: "public enum QuillCodeRuntimeStatusLabel")
        [
            "QuillCodeRuntimeStatusLabel.signInWithTrustedRouter",
            "QuillCodeRuntimeStatusLabel.developerKeyNeeded",
            "QuillCodeRuntimeStatusLabel.trustedRouterReady"
        ].forEach { Self.assertSource(runtimeFactoryText, contains: $0) }
        [
            "case QuillCodeRuntimeStatusLabel.signInWithTrustedRouter",
            "case QuillCodeRuntimeStatusLabel.developerKeyNeeded"
        ].forEach { Self.assertSource(issueBuilderText, contains: $0) }
        Self.assertSource(desktopSignInText, contains: "QuillCodeRuntimeStatusLabel.signInFailed")
        [
            "status: \"Mock LLM\"",
            "status: \"Sign in with TrustedRouter\"",
            "status: \"Developer key needed\""
        ].forEach { Self.assertSource(runtimeFactoryText, excludes: $0) }
        [
            "case \"Sign in with TrustedRouter\"",
            "case \"Developer key needed\""
        ].forEach { Self.assertSource(issueBuilderText, excludes: $0) }
        Self.assertSource(desktopSignInText, excludes: "setAgentStatus(\"Sign-in failed\"")
    }
}
