import Foundation

enum WorkspaceHTMLTopBarRenderer {
    static func render(_ topBar: TopBarSurface, commands: [WorkspaceCommandSurface]) -> String {
        """
        <header class="topbar" data-testid="top-bar" aria-label="\(escape(topBarAccessibilityLabel(topBar)))">
          \(renderStatusMetadata(topBar))
          <div class="topbar-sidebar-slot" aria-hidden="true"></div>
          <div class="topbar-title-group" data-testid="top-bar-title-group">
            <strong data-testid="top-bar-title">\(escape(topBar.primaryTitle))</strong>
            <p class="topbar-context-label" data-testid="top-bar-subtitle">\(escape(topBar.subtitle))</p>
            \(renderBranchStatus(topBar))
          </div>
          <div class="topbar-clusters" data-testid="top-bar-clusters">
            \(renderActionCluster(topBar, commands: commands))
          </div>
          \(renderActivityHairline(topBar))
        </header>
        """
    }

    private static func renderStatusMetadata(_ topBar: TopBarSurface) -> String {
        let status = topBar.agentStatusPresentation
        return """
        <div class="topbar-status-metadata" data-testid="top-bar-status-metadata" aria-hidden="true">
          <span data-testid="agent-status" data-tone="\(escape(status.tone.rawValue))" data-indicator="\(status.showsIndicator)">\(escape(status.label))</span>
          \(renderRuntimeIssuePill(topBar))
          <span data-testid="project-instructions-status" title="\(escape(topBar.instructionSources.joined(separator: ", ")))">\(escape(topBar.instructionLabel))</span>
          <span data-testid="project-memories-status" title="\(escape(topBar.memorySources.joined(separator: ", ")))">\(escape(topBar.memoryLabel))</span>
          <span data-testid="computer-use-status">\(escape(topBar.computerUseLabel))</span>
        </div>
        """
    }

    private static func renderBranchStatus(_ topBar: TopBarSurface) -> String {
        guard let branchStatusLabel = topBar.branchStatusLabel else { return "" }
        return #"<span class="topbar-branch-chip" data-testid="top-bar-branch" title="\#(escape(branchStatusLabel))">\#(escape(branchStatusLabel))</span>"#
    }

    private static func renderRuntimeIssuePill(_ topBar: TopBarSurface) -> String {
        guard let issue = topBar.runtimeIssuePresentation else { return "" }
        return #"<span data-testid="runtime-issue-pill" data-severity="\#(escape(issue.tone.rawValue))">\#(escape(issue.label))</span>"#
    }

    private static func renderActivityHairline(_ topBar: TopBarSurface) -> String {
        guard showsActivityHairline(topBar) else { return "" }
        return #"<div class="topbar-activity-hairline" data-testid="top-bar-activity-hairline" data-tone="\#(escape(activityHairlineTone(topBar)))" aria-hidden="true"></div>"#
    }

    private static func showsActivityHairline(_ topBar: TopBarSurface) -> Bool {
        topBar.agentStatusPresentation.showsIndicator || topBar.runtimeIssuePresentation != nil
    }

    private static func activityHairlineTone(_ topBar: TopBarSurface) -> String {
        if let issue = topBar.runtimeIssuePresentation {
            return issue.tone.rawValue
        }
        return topBar.agentStatusPresentation.tone.rawValue
    }

    private static func topBarAccessibilityLabel(_ topBar: TopBarSurface) -> String {
        var parts = [
            topBar.primaryTitle,
            topBar.subtitle,
            topBar.agentStatusPresentation.accessibilityLabel
        ]
        if let issue = topBar.runtimeIssuePresentation {
            parts.append("Issue: \(issue.label)")
        }
        return parts.joined(separator: ", ")
    }

    private static func renderActionCluster(
        _ topBar: TopBarSurface,
        commands: [WorkspaceCommandSurface]
    ) -> String {
        """
        <div class="topbar-cluster topbar-action-cluster" data-testid="top-bar-action-cluster">
          \(renderActiveStopButton(commands: commands))
          <details class="topbar-overflow-menu" data-testid="top-bar-overflow-menu">
            \(WorkspaceHTMLPrimitives.summary(
                "...",
                testID: "top-bar-overflow-button",
                hitTargetKind: .icon,
                ariaLabel: "More",
                title: "More"
            ))
            <div class="topbar-overflow-popover">
              \(renderOverflow(commands: commands, showsComputerUseSetup: topBar.showsComputerUseSetup))
            </div>
          </details>
        </div>
        """
    }

    private static func renderActiveStopButton(commands: [WorkspaceCommandSurface]) -> String {
        guard let command = commands.first(where: { $0.id == "stop-all" && $0.isEnabled }) else {
            return ""
        }
        let title = command.shortcut.map { "\(command.title) (\($0))" } ?? command.title
        return WorkspaceHTMLPrimitives.commandButton(
            "Stop",
            testID: "top-bar-stop-button",
            commandID: "stop-all",
            hitTargetKind: .text,
            classes: ["topbar-stop-button"],
            ariaLabel: "Stop active work",
            title: title
        )
    }

    private static func renderOverflow(
        commands: [WorkspaceCommandSurface],
        showsComputerUseSetup: Bool
    ) -> String {
        TopBarOverflowCommandCatalog.commands(
            from: commands,
            showsComputerUseSetup: showsComputerUseSetup
        )
        .map(renderOverflowButton)
        .joined(separator: "\n")
    }

    private static func renderOverflowButton(_ command: WorkspaceCommandSurface) -> String {
        let testID = TopBarOverflowCommandCatalog.testID(for: command.id)
        let title = command.shortcut.map { "\(command.title) (\($0))" } ?? command.title
        return WorkspaceHTMLPrimitives.commandButton(
            command.title,
            testID: testID,
            commandID: command.id,
            hitTargetKind: .row,
            title: title,
            role: "menuitem",
            disabled: !command.isEnabled
        )
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
