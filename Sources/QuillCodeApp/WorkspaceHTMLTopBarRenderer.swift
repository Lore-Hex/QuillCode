import Foundation

enum WorkspaceHTMLTopBarRenderer {
    static func render(_ topBar: TopBarSurface, commands: [WorkspaceCommandSurface]) -> String {
        """
        <header class="topbar" data-testid="top-bar" aria-label="\(escape(topBar.topBarAccessibilityLabel))">
          \(renderStatusMetadata(topBar))
          <div class="topbar-sidebar-slot">\(renderNavigationControls(commands: commands))</div>
          <div class="topbar-title-group" data-testid="top-bar-title-group">
            <div class="topbar-title-copy">
              <strong data-testid="top-bar-title">\(escape(topBar.primaryTitle))</strong>
              <p class="topbar-context-label" data-testid="top-bar-subtitle">\(escape(topBar.subtitle))</p>
            </div>
            \(renderBranchStatus(topBar))
            \(renderGoal(topBar))
            \(renderLiveWork(topBar))
            \(renderWorktreeStatus(topBar))
            \(renderTokenBudget(topBar))
            \(renderSpendStatus(topBar))
            \(renderUsageStatus(topBar))
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

    private static func renderLiveWork(_ topBar: TopBarSurface) -> String {
        guard let liveWork = topBar.liveWork else { return "" }
        return #"<span class="topbar-live-work-chip" data-testid="top-bar-live-work" data-tone="\#(escape(liveWork.tone.rawValue))" title="\#(escape(liveWork.detail))">\#(escape(liveWork.label))</span>"#
    }

    private static func renderGoal(_ topBar: TopBarSurface) -> String {
        guard let goal = topBar.goal else { return "" }
        return #"<span class="topbar-goal-chip" data-testid="top-bar-goal" data-tone="\#(escape(goal.tone.rawValue))" title="\#(escape(goal.detail))">\#(escape(goal.label))</span>"#
    }

    private static func renderWorktreeStatus(_ topBar: TopBarSurface) -> String {
        guard let worktreeStatusLabel = topBar.worktreeStatusLabel else { return "" }
        let title = topBar.worktreeStatusDetail ?? worktreeStatusLabel
        let tone = topBar.worktreeStatusIsWarning ? "warning" : "normal"
        return #"<span class="topbar-worktree-chip" data-testid="top-bar-worktree" data-tone="\#(escape(tone))" title="\#(escape(title))">\#(escape(worktreeStatusLabel))</span>"#
    }

    private static func renderUsageStatus(_ topBar: TopBarSurface) -> String {
        guard topBar.tokenBudget == nil,
              topBar.spendStatusLabel == nil,
              let usageStatusLabel = topBar.usageStatusLabel
        else { return "" }
        return #"<span class="topbar-usage-chip" data-testid="top-bar-usage" title="\#(escape(usageStatusLabel))">\#(escape(usageStatusLabel))</span>"#
    }

    private static func renderTokenBudget(_ topBar: TopBarSurface) -> String {
        guard let budget = topBar.tokenBudget else { return "" }
        return """
        <section class="topbar-token-budget" data-testid="top-bar-token-budget" data-tone="\(escape(tokenBudgetTone(budget)))" title="\(escape(budget.accessibilityLabel))" aria-label="\(escape(budget.accessibilityLabel))">
          <div class="topbar-token-budget-row">
            <span class="topbar-token-budget-label">Tokens</span>
            <strong data-testid="top-bar-token-budget-primary">\(escape(budget.primaryLabel))</strong>
          </div>
          <div class="topbar-token-budget-meter" aria-hidden="true">
            <span style="width: \(budget.progressPercent)%"></span>
          </div>
          <p data-testid="top-bar-token-budget-secondary">\(escape(tokenBudgetSecondaryLabel(budget)))</p>
          \(renderQuotaLimits(budget))
        </section>
        """
    }

    private static func renderQuotaLimits(_ budget: TokenBudgetSurface) -> String {
        let quotaLimits = budget.visibleQuotaLimits.prefix(3)
        guard !quotaLimits.isEmpty else { return "" }
        let chips = quotaLimits.map { quota in
            #"<span title="\#(escape(quota.detailLabel))">\#(escape(quota.compactLabel))</span>"#
        }.joined(separator: "")
        return #"<div class="topbar-token-quota-row" data-testid="top-bar-token-quota-limits">\#(chips)</div>"#
    }

    private static func tokenBudgetTone(_ budget: TokenBudgetSurface) -> String {
        if budget.usedPercent >= 100 { return "critical" }
        if budget.usedPercent >= 80 { return "warning" }
        return "normal"
    }

    private static func tokenBudgetSecondaryLabel(_ budget: TokenBudgetSurface) -> String {
        let compactParts = budget.secondaryLabel
            .components(separatedBy: tokenBudgetMetadataSeparator)
            .prefix(2)
            .filter { !$0.isEmpty }
        let compactLabel = compactParts.joined(separator: tokenBudgetMetadataSeparator)
        return compactLabel.isEmpty ? budget.secondaryLabel : compactLabel
    }

    private static let tokenBudgetMetadataSeparator = [" ", "·", " "].joined()

    private static func renderSpendStatus(_ topBar: TopBarSurface) -> String {
        guard let spendStatusLabel = topBar.spendStatusLabel else { return "" }
        let title = topBar.spendStatusDetail ?? spendStatusLabel
        return #"<span class="topbar-spend-chip" data-testid="top-bar-spend" title="\#(escape(title))">\#(escape(spendStatusLabel))</span>"#
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
        topBar.showsActivityHairline
    }

    private static func activityHairlineTone(_ topBar: TopBarSurface) -> String {
        if let issue = topBar.runtimeIssuePresentation {
            return issue.tone.rawValue
        }
        return topBar.agentStatusPresentation.tone.rawValue
    }

    private static func renderActionCluster(
        _ topBar: TopBarSurface,
        commands: [WorkspaceCommandSurface]
    ) -> String {
        """
        <div class="topbar-cluster topbar-action-cluster" data-testid="top-bar-action-cluster">
          \(renderCreateBranchButton(commands: commands))
          \(renderHandoffButton(commands: commands))
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

    private static func renderNavigationControls(commands: [WorkspaceCommandSurface]) -> String {
        let back = commands.first { $0.id == "workspace-back" } ?? WorkspaceCommandSurface(
            id: "workspace-back",
            title: "Back",
            category: WorkspaceCommandPalette.navigationCategory,
            keywords: [],
            isEnabled: false
        )
        let forward = commands.first { $0.id == "workspace-forward" } ?? WorkspaceCommandSurface(
            id: "workspace-forward",
            title: "Forward",
            category: WorkspaceCommandPalette.navigationCategory,
            keywords: [],
            isEnabled: false
        )
        return """
        <div class="topbar-navigation" data-testid="top-bar-navigation" aria-label="Workspace navigation">
          \(renderNavigationButton(back, label: "‹", testID: "top-bar-back", ariaLabel: "Back"))
          \(renderNavigationButton(forward, label: "›", testID: "top-bar-forward", ariaLabel: "Forward"))
        </div>
        """
    }

    private static func renderNavigationButton(
        _ command: WorkspaceCommandSurface,
        label: String,
        testID: String,
        ariaLabel: String
    ) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            label,
            testID: testID,
            commandID: command.id,
            hitTargetKind: .icon,
            classes: ["topbar-navigation-button"],
            ariaLabel: ariaLabel,
            title: command.isEnabled ? command.title : "\(ariaLabel) unavailable",
            disabled: !command.isEnabled
        )
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

    private static func renderHandoffButton(commands: [WorkspaceCommandSurface]) -> String {
        guard let command = commands.first(where: {
            $0.id == WorkspaceCommandAction.threadHandoff.rawValue && $0.isEnabled
        }) else { return "" }
        return WorkspaceHTMLPrimitives.commandButton(
            "↔",
            testID: "top-bar-handoff-button",
            commandID: command.id,
            hitTargetKind: .icon,
            classes: ["topbar-handoff-button"],
            ariaLabel: command.title,
            title: command.title
        )
    }

    private static func renderCreateBranchButton(commands: [WorkspaceCommandSurface]) -> String {
        guard let command = commands.first(where: {
            $0.id == WorkspaceCommandAction.threadCreateBranch.rawValue && $0.isEnabled
        }) else { return "" }
        return WorkspaceHTMLPrimitives.commandButton(
            "Create branch here",
            testID: "top-bar-create-branch-button",
            commandID: command.id,
            hitTargetKind: .text,
            classes: ["topbar-create-branch-button"],
            ariaLabel: command.title,
            title: command.title
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
