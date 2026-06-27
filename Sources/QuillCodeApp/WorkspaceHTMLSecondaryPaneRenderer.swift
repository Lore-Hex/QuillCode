import Foundation
import QuillCodeTools

enum WorkspaceHTMLSecondaryPaneRenderer {
    static func renderExtensions(_ extensions: WorkspaceExtensionsSurface) -> String {
        guard extensions.isVisible else { return "" }
        let counts = """
        <span data-testid="extensions-count">\(countLabel(extensions.pluginCount, singular: "plugin"))</span>
        <span data-testid="extensions-count">\(countLabel(extensions.skillCount, singular: "skill"))</span>
        <span data-testid="extensions-count">\(countLabel(extensions.mcpServerCount, singular: "MCP server"))</span>
        """
        let content: String
        if extensions.items.isEmpty {
            content = """
            <div class="extensions-empty" data-testid="extensions-empty">
              <strong>\(escape(extensions.emptyTitle))</strong>
              <p>\(escape(extensions.emptySubtitle))</p>
            </div>
            """
        } else {
            content = """
            <div class="extensions-grid" data-testid="extensions-grid">
              \(extensions.items.map(renderExtensionItem).joined(separator: "\n"))
            </div>
            """
        }
        return """
        <section class="extensions-pane" data-testid="extensions-pane" aria-label="Project extensions">
          <header>
            <div>
              <strong>\(escape(extensions.title))</strong>
              <p data-testid="extensions-subtitle">\(escape(extensions.subtitle))</p>
            </div>
            <span class="extensions-counts">
              \(counts)
            </span>
          </header>
          \(content)
        </section>
        """
    }

    static func renderMemories(_ memories: WorkspaceMemoriesSurface) -> String {
        guard memories.isVisible else { return "" }
        let counts = """
        <span data-testid="memories-count">\(countLabel(memories.globalCount, singular: "global memory"))</span>
        <span data-testid="memories-count">\(countLabel(memories.projectCount, singular: "project memory"))</span>
        """
        let content: String
        if memories.items.isEmpty {
            content = """
            <div class="memories-empty" data-testid="memories-empty">
              <strong>\(escape(memories.emptyTitle))</strong>
              <p>\(escape(memories.emptySubtitle))</p>
            </div>
            """
        } else {
            content = """
            <div class="memories-grid" data-testid="memories-grid">
              \(memories.items.map(renderMemoryItem).joined(separator: "\n"))
            </div>
            """
        }
        return """
        <section class="memories-pane" data-testid="memories-pane" aria-label="QuillCode memories">
          <header>
            <div>
              <strong>\(escape(memories.title))</strong>
              <p data-testid="memories-subtitle">\(escape(memories.subtitle))</p>
            </div>
            <span class="memories-counts">
              \(counts)
            </span>
          </header>
          \(content)
        </section>
        """
    }

    static func renderActivity(_ activity: WorkspaceActivitySurface) -> String {
        guard activity.isVisible else { return "" }
        return """
        <section class="activity-pane" data-testid="activity-pane" aria-label="Task activity">
          <header>
            <div>
              <strong data-testid="activity-title">\(escape(activity.title))</strong>
              <p data-testid="activity-subtitle">\(escape(activity.subtitle))</p>
            </div>
            <span data-testid="activity-status">\(escape(activity.statusLabel))</span>
          </header>
          <article class="activity-task" data-testid="activity-task">
            <strong data-testid="activity-task-title">\(escape(activity.taskTitle))</strong>
            <p data-testid="activity-task-subtitle">\(escape(activity.taskSubtitle))</p>
          </article>
          \(activity.sections.map(renderActivitySection).joined(separator: "\n"))
        </section>
        """
    }

    static func renderAutomations(_ automations: WorkspaceAutomationsSurface) -> String {
        guard automations.isVisible else { return "" }
        let content: String
        if automations.workflows.isEmpty {
            content = """
            <article class="automation-empty" data-testid="automations-empty">
              <strong>\(escape(automations.emptyTitle))</strong>
              <p>\(escape(automations.emptySubtitle))</p>
            </article>
            """
        } else {
            content = automations.workflows.map { workflow in
                let actions = renderAutomationActions(workflow)
                return """
                <article class="automation-card" data-testid="automation-card">
                  <div>
                    <span data-testid="automation-schedule">\(escape(workflow.scheduleLabel))</span>
                    <span data-testid="automation-status">\(escape(workflow.statusLabel))</span>
                  </div>
                  <strong>\(escape(workflow.title))</strong>
                  <p>\(escape(workflow.detail))</p>
                  \(actions)
                </article>
                """
            }.joined(separator: "\n")
        }
        let createButton = automations.createThreadFollowUpCommand.map { command in
            #"<button type="button" data-testid="automation-create-follow-up" data-command-id="\#(escape(command.id))" \#(command.isEnabled ? "" : "disabled")>\#(escape(command.title))</button>"#
        } ?? ""
        let createWorkspaceButton = automations.createWorkspaceScheduleCommand.map { command in
            #"<button type="button" data-testid="automation-create-workspace-schedule" data-command-id="\#(escape(command.id))" \#(command.isEnabled ? "" : "disabled")>\#(escape(command.title))</button>"#
        } ?? ""
        let scheduleButtons = automations.scheduleThreadFollowUpCommands.map { command in
            #"<button type="button" data-testid="automation-schedule-follow-up" data-command-id="\#(escape(command.id))" \#(command.isEnabled ? "" : "disabled")>\#(escape(command.title))</button>"#
        }.joined(separator: "\n")
        let workspaceScheduleButtons = automations.scheduleWorkspaceScheduleCommands.map { command in
            #"<button type="button" data-testid="automation-schedule-workspace" data-command-id="\#(escape(command.id))" \#(command.isEnabled ? "" : "disabled")>\#(escape(command.title))</button>"#
        }.joined(separator: "\n")
        let createActions = [createButton, createWorkspaceButton, scheduleButtons, workspaceScheduleButtons]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return """
        <section class="automations-pane" data-testid="automations-pane" aria-label="Automations">
          <header>
            <div>
              <strong data-testid="automations-title">\(escape(automations.title))</strong>
              <p data-testid="automations-subtitle">\(escape(automations.subtitle))</p>
            </div>
            <div class="automation-create-actions">
              \(createActions)
            </div>
            <span data-testid="automations-status">\(escape(automations.statusLabel))</span>
          </header>
          <div class="automation-grid">
            \(content)
          </div>
        </section>
        """
    }

    private static func renderExtensionItem(_ item: ProjectExtensionManifestSurface) -> String {
        """
        <article class="extension-card" data-testid="extension-item" data-kind="\(escape(item.kind.rawValue))" data-status="\(escape(item.statusLabel))">
          <header>
            <span data-testid="extension-kind">\(escape(item.kindLabel))</span>
            <span data-testid="extension-status">\(escape(item.statusLabel))</span>
          </header>
          <strong data-testid="extension-name">\(escape(item.name))</strong>
          \(item.summary.isEmpty ? "" : #"<p data-testid="extension-summary">\#(escape(item.summary))</p>"#)
          \(item.versionLabel.map { #"<span data-testid="extension-version">\#(escape($0))</span>"# } ?? "")
          \(item.sourceURL.map { #"<code data-testid="extension-source">\#(escape($0))</code>"# } ?? "")
          <code data-testid="extension-path">\(escape(item.relativePath))</code>
          \(item.launchCommand.map { #"<code data-testid="extension-command">\#(escape($0))</code>"# } ?? "")
          \(item.installCommand.map { #"<code data-testid="extension-install-command">\#(escape($0))</code>"# } ?? "")
          \(item.updateCommand.map { #"<code data-testid="extension-update-command">\#(escape($0))</code>"# } ?? "")
          \(item.transportLabel.map { #"<span data-testid="extension-transport">\#(escape($0))</span>"# } ?? "")
          \(item.serverLabel.map { #"<span data-testid="extension-mcp-server">\#(escape($0))</span>"# } ?? "")
          \(renderMCPMeta(item))
          \(renderMCPTools(item.toolDescriptors))
          \(renderMCPNames("Resources", item.resourceNames, groupTestID: "extension-mcp-resources", itemTestID: "extension-mcp-resource"))
          \(renderMCPNames("Prompts", item.promptNames, groupTestID: "extension-mcp-prompts", itemTestID: "extension-mcp-prompt"))
          \(renderMCPReferenceActions("Resource Actions", item.resourceActions, testID: "extension-mcp-resource-action", titlePrefix: "Read"))
          \(renderMCPReferenceActions("Prompt Actions", item.promptActions, testID: "extension-mcp-prompt-action", titlePrefix: "Use"))
          \(item.probeError.map { #"<p data-testid="extension-mcp-error">\#(escape($0))</p>"# } ?? "")
          \(renderExtensionActions(item))
        </article>
        """
    }

    private static func renderMCPMeta(_ item: ProjectExtensionManifestSurface) -> String {
        let labels = [
            item.protocolLabel.map { #"<span data-testid="extension-mcp-protocol">\#(escape($0))</span>"# },
            item.toolCountLabel.map { #"<span data-testid="extension-mcp-tools-count">\#(escape($0))</span>"# },
            item.resourceCountLabel.map { #"<span data-testid="extension-mcp-resources-count">\#(escape($0))</span>"# },
            item.promptCountLabel.map { #"<span data-testid="extension-mcp-prompts-count">\#(escape($0))</span>"# }
        ].compactMap { $0 }
        guard !labels.isEmpty else { return "" }
        return #"<div class="extension-mcp-meta" data-testid="extension-mcp-meta">\#(labels.joined(separator: " · "))</div>"#
    }

    private static func renderMCPTools(_ tools: [MCPToolDescriptor]) -> String {
        guard !tools.isEmpty else { return "" }
        let chips = tools.map { tool in
            let details = [tool.schemaSummary, tool.description]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return """
            <span class="extension-mcp-tool-chip" data-testid="extension-mcp-tool">
              <strong data-testid="extension-mcp-tool-name">\(escape(tool.name))</strong>
              \(details.isEmpty ? "" : #"<small data-testid="extension-mcp-tool-schema">\#(escape(details))</small>"#)
            </span>
            """
        }.joined()
        return #"<div class="extension-mcp-group" data-testid="extension-mcp-tools"><span class="extension-mcp-group-label" data-testid="extension-mcp-group-label">Tools</span><div class="extension-mcp-chip-row">\#(chips)</div></div>"#
    }

    private static func renderMCPNames(_ title: String, _ names: [String], groupTestID: String, itemTestID: String) -> String {
        guard !names.isEmpty else { return "" }
        let chips = names.map { #"<span data-testid="\#(escape(itemTestID))">\#(escape($0))</span>"# }.joined()
        return #"<div class="extension-mcp-group" data-testid="\#(escape(groupTestID))"><span class="extension-mcp-group-label" data-testid="extension-mcp-group-label">\#(escape(title))</span><div class="extension-mcp-chip-row">\#(chips)</div></div>"#
    }

    private static func renderMCPReferenceActions(
        _ title: String,
        _ actions: [MCPReferenceActionSurface],
        testID: String,
        titlePrefix: String
    ) -> String {
        guard !actions.isEmpty else { return "" }
        let buttons = actions.map { action in
            #"<button type="button" class="extension-reference-action" data-testid="\#(escape(testID))" data-command="\#(escape(action.commandID))">\#(escape(titlePrefix)) \#(escape(action.title))</button>"#
        }.joined()
        return #"<div class="extension-mcp-group" data-testid="\#(escape(testID))-group"><span class="extension-mcp-group-label" data-testid="extension-mcp-group-label">\#(escape(title))</span><div class="extension-mcp-chip-row">\#(buttons)</div></div>"#
    }

    private static func renderExtensionActions(_ item: ProjectExtensionManifestSurface) -> String {
        var buttons: [String] = []
        if let installCommandID = item.installCommandID {
            buttons.append(#"<button type="button" class="extension-action-button" data-testid="extension-install" data-command="\#(escape(installCommandID))">Install</button>"#)
        }
        if let updateCommandID = item.updateCommandID {
            buttons.append(#"<button type="button" class="extension-action-button" data-testid="extension-update" data-command="\#(escape(updateCommandID))">Update</button>"#)
        }
        if let stopCommandID = item.stopCommandID {
            buttons.append(#"<button type="button" class="extension-action-button" data-testid="extension-stop" data-command="\#(escape(stopCommandID))">Stop</button>"#)
        }
        if let startCommandID = item.startCommandID {
            buttons.append(#"<button type="button" class="extension-action-button" data-testid="extension-start" data-command="\#(escape(startCommandID))">Start</button>"#)
        }
        return buttons.joined(separator: "\n")
    }

    private static func renderMemoryItem(_ item: MemoryNoteSurface) -> String {
        """
        <article class="memory-card" data-testid="memory-item" data-scope="\(escape(item.scope.rawValue))">
          <header>
            <span data-testid="memory-scope">\(escape(item.scopeLabel))</span>
            <span data-testid="memory-size">\(escape(item.byteCountLabel))</span>
            \(item.editCommandID.map { #"<button type="button" class="memory-edit-button" data-testid="memory-edit" data-command-id="\#(escape($0))">Edit</button>"# } ?? "")
            \(item.deleteCommandID.map { #"<button type="button" class="memory-delete-button" data-testid="memory-delete" data-command-id="\#(escape($0))">Forget</button>"# } ?? "")
          </header>
          <strong data-testid="memory-title">\(escape(item.title))</strong>
          <p data-testid="memory-preview">\(escape(item.preview))</p>
          <code data-testid="memory-path">\(escape(item.relativePath))</code>
        </article>
        """
    }

    private static func renderAutomationActions(_ workflow: AutomationWorkflowSurface) -> String {
        var buttons: [String] = []
        if let commandID = workflow.runCommandID,
           let title = workflow.runActionTitle {
            buttons.append(#"<button type="button" data-testid="automation-run" data-command-id="\#(escape(commandID))">\#(escape(title))</button>"#)
        }
        if let commandID = workflow.primaryCommandID,
           let title = workflow.primaryActionTitle {
            buttons.append(#"<button type="button" data-testid="automation-primary-action" data-command-id="\#(escape(commandID))">\#(escape(title))</button>"#)
        }
        if let commandID = workflow.deleteCommandID {
            buttons.append(#"<button type="button" data-testid="automation-delete" data-command-id="\#(escape(commandID))">Delete</button>"#)
        }
        guard !buttons.isEmpty else { return "" }
        return #"<div class="automation-actions">\#(buttons.joined(separator: "\n"))</div>"#
    }

    private static func renderActivitySection(_ section: ActivitySectionSurface) -> String {
        let content: String
        if section.isCollapsed {
            content = ""
        } else if let bodyText = section.bodyText {
            content = #"<p data-testid="\#(escape(section.itemTestID))" style="white-space: pre-wrap;">\#(escape(bodyText))</p>"#
        } else if !section.artifacts.isEmpty {
            content = section.artifacts.map { artifact in
                """
                <article class="activity-artifact" data-testid="\(escape(section.itemTestID))">
                  <strong>\(escape(artifact.label))</strong>
                  <p>\(escape(artifact.detail))</p>
                </article>
                """
            }.joined(separator: "\n")
        } else if !section.items.isEmpty {
            content = section.items.map { item in
                """
                <article class="activity-item" data-testid="\(escape(section.itemTestID))" data-kind="\(escape(item.kind))">
                  <strong>\(escape(item.title))</strong>
                  \(item.statusLabel.isEmpty ? "" : #"<span>\#(escape(item.statusLabel))</span>"#)
                  \(item.detail.isEmpty ? "" : #"<p>\#(escape(item.detail))</p>"#)
                </article>
                """
            }.joined(separator: "\n")
        } else {
            content = #"<p data-testid="\#(escape(section.itemTestID))-empty">\#(escape(section.emptyTitle))</p>"#
        }
        return """
        <section class="activity-section" data-testid="\(escape(section.itemTestID))-section" data-collapsed="\(section.isCollapsed ? "true" : "false")">
          <button type="button" data-testid="activity-section-toggle" data-command-id="\(escape(section.toggleCommandID))">
            <span>\(section.isCollapsed ? ">" : "v") \(escape(section.title))</span>
            <span>\(escape(section.countLabel))</span>
          </button>
          \(content)
        </section>
        """
    }

    private static func countLabel(_ count: Int, singular: String) -> String {
        if count == 1 { return "1 \(singular)" }
        if singular.hasSuffix("memory") {
            return "\(count) \(singular.dropLast("memory".count))memories"
        }
        return "\(count) \(singular)s"
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
