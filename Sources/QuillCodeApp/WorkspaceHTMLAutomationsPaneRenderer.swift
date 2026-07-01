enum WorkspaceHTMLAutomationsPaneRenderer {
    private typealias Primitives = WorkspaceHTMLSecondaryPanePrimitives

    static func render(_ automations: WorkspaceAutomationsSurface) -> String {
        guard automations.isVisible else { return "" }
        return """
        <section class="automations-pane" data-testid="automations-pane" aria-label="Automations">
          <header>
            <div>
              <strong data-testid="automations-title">\(escape(automations.title))</strong>
              <p data-testid="automations-subtitle">\(escape(automations.subtitle))</p>
            </div>
            <div class="automation-create-actions">
              \(renderCreateActions(automations))
            </div>
            <span data-testid="automations-status">\(escape(automations.statusLabel))</span>
          </header>
          <div class="automation-grid">
            \(renderContent(automations))
          </div>
        </section>
        """
    }

    private static func renderContent(_ automations: WorkspaceAutomationsSurface) -> String {
        guard !automations.workflows.isEmpty else {
            return """
            <article class="automation-empty" data-testid="automations-empty">
              <strong>\(escape(automations.emptyTitle))</strong>
              <p>\(escape(automations.emptySubtitle))</p>
            </article>
            """
        }
        return automations.workflows.map(renderWorkflow).joined(separator: "\n")
    }

    private static func renderWorkflow(_ workflow: AutomationWorkflowSurface) -> String {
        """
        <article class="automation-card" data-testid="automation-card">
          <div>
            <span data-testid="automation-schedule">\(escape(workflow.scheduleLabel))</span>
            <span data-testid="automation-status">\(escape(workflow.statusLabel))</span>
          </div>
          <strong>\(escape(workflow.title))</strong>
          <p>\(escape(workflow.detail))</p>
          \(renderAutomationActions(workflow))
        </article>
        """
    }

    private static func renderCreateActions(_ automations: WorkspaceAutomationsSurface) -> String {
        [
            renderCommand(automations.createThreadFollowUpCommand, testID: "automation-create-follow-up"),
            renderCommand(automations.createWorkspaceScheduleCommand, testID: "automation-create-workspace-schedule"),
            renderCommands(automations.scheduleThreadFollowUpCommands, testID: "automation-schedule-follow-up"),
            renderCommands(automations.scheduleWorkspaceScheduleCommands, testID: "automation-schedule-workspace")
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func renderAutomationActions(_ workflow: AutomationWorkflowSurface) -> String {
        let actions = [
            renderAction(workflow.runActionTitle, commandID: workflow.runCommandID, testID: "automation-run"),
            renderAction(
                workflow.primaryActionTitle,
                commandID: workflow.primaryCommandID,
                testID: "automation-primary-action"
            ),
            workflow.deleteCommandID.map { commandID in
                commandButton("Delete", testID: "automation-delete", commandID: commandID)
            } ?? ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        return wrappedAutomationActions(actions)
    }

    private static func renderAction(_ title: String?, commandID: String?, testID: String) -> String {
        guard let title, let commandID else { return "" }
        return commandButton(title, testID: testID, commandID: commandID)
    }

    private static func renderCommands(_ commands: [WorkspaceCommandSurface], testID: String) -> String {
        commands.map { renderCommand($0, testID: testID) }.joined(separator: "\n")
    }

    private static func renderCommand(_ command: WorkspaceCommandSurface?, testID: String) -> String {
        guard let command else { return "" }
        return commandButton(command.title, testID: testID, commandID: command.id, disabled: !command.isEnabled)
    }

    private static func commandButton(
        _ label: String,
        testID: String,
        commandID: String,
        disabled: Bool = false
    ) -> String {
        Primitives.commandButton(
            label,
            testID: testID,
            commandID: commandID,
            hitTargetKind: .formAction,
            disabled: disabled
        )
    }

    private static func escape(_ text: String) -> String {
        Primitives.escape(text)
    }

    private static func wrappedAutomationActions(_ actions: String) -> String {
        actions.isEmpty ? "" : #"<div class="automation-actions">\#(actions)</div>"#
    }
}
