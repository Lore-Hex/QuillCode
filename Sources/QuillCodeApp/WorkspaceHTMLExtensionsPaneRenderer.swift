import QuillCodeTools

enum WorkspaceHTMLExtensionsPaneRenderer {
    private typealias Primitives = WorkspaceHTMLSecondaryPanePrimitives

    static func render(_ extensions: WorkspaceExtensionsSurface) -> String {
        guard extensions.isVisible else { return "" }
        let content = renderContent(extensions)
        return """
        <section class="extensions-pane" data-testid="extensions-pane" aria-label="Project extensions">
          <header>
            <div>
              <strong>\(escape(extensions.title))</strong>
              <p data-testid="extensions-subtitle">\(escape(extensions.subtitle))</p>
            </div>
            <div class="extensions-header-actions">
              \(renderRecordingStartAction(extensions))
              <span class="extensions-counts">
                \(renderCounts(extensions))
              </span>
            </div>
          </header>
          \(content)
        </section>
        """
    }

    private static func renderContent(_ extensions: WorkspaceExtensionsSurface) -> String {
        let recording = renderRecordingStatus(extensions)
        let catalog: String
        if extensions.items.isEmpty && extensions.hookItems.isEmpty {
            catalog = """
            <div class="extensions-empty" data-testid="extensions-empty">
              <strong>\(escape(extensions.emptyTitle))</strong>
              <p>\(escape(extensions.emptySubtitle))</p>
            </div>
            """
        } else {
            catalog = """
            <div class="extensions-grid" data-testid="extensions-grid">
              \((extensions.items.map(renderExtensionItem) + extensions.hookItems.map(renderHookItem)).joined(separator: "\n"))
            </div>
            """
        }
        return [recording, catalog].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func renderRecordingStartAction(_ extensions: WorkspaceExtensionsSurface) -> String {
        guard let status = extensions.workflowRecording, !status.isRecording else { return "" }
        return commandButton(
            "Record a skill",
            testID: "workflow-recording-start",
            commandID: "workflow-recording-create",
            hitTargetKind: .formAction,
            classes: ["extension-action-button"]
        )
    }

    private static func renderRecordingStatus(_ extensions: WorkspaceExtensionsSurface) -> String {
        guard let status = extensions.workflowRecording, status.isRecording else { return "" }
        let goal = status.goal ?? "Demonstrated workflow"
        let title = status.hasReachedDurationLimit ? "Recording limit reached" : "Recording workflow"
        let detail = status.hasReachedDurationLimit
            ? "The 30-minute capture is complete. Stop to create the skill."
            : goal
        return """
        <article class="workflow-recording-card" data-testid="workflow-recording-status" aria-live="polite">
          <span class="workflow-recording-indicator" aria-hidden="true"></span>
          <div>
            <strong>\(escape(title))</strong>
            <p data-testid="workflow-recording-goal">\(escape(detail))</p>
          </div>
          \(commandButton(
              "Stop recording",
              testID: "workflow-recording-stop",
              commandID: WorkspaceCommandAction.workflowRecordingStop.rawValue,
              hitTargetKind: .formAction,
              classes: ["extension-action-button"]
          ))
        </article>
        """
    }

    private static func renderCounts(_ extensions: WorkspaceExtensionsSurface) -> String {
        var counts = [
            countChip(extensions.pluginCount, singular: "plugin"),
            countChip(extensions.skillCount, singular: "skill"),
            countChip(extensions.mcpServerCount, singular: "MCP server"),
            countChip(extensions.hookCount, singular: "hook")
        ]
        if extensions.availableCount > 0 {
            counts.append(countChip(extensions.availableCount, singular: "available extension"))
        }
        return counts.joined(separator: "\n")
    }

    private static func countChip(_ count: Int, singular: String) -> String {
        #"<span data-testid="extensions-count">\#(Primitives.countLabel(count, singular: singular))</span>"#
    }

    private static func renderExtensionItem(_ item: ProjectExtensionManifestSurface) -> String {
        let mcpDetails = renderMCPDetails(item)
        return """
        <article
          class="extension-card"
          data-testid="extension-item"
          data-kind="\(escape(item.kind.rawValue))"
          data-status="\(escape(item.statusLabel))"
        >
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
          \(mcpDetails)
          \(item.probeError.map { #"<p data-testid="extension-mcp-error">\#(escape($0))</p>"# } ?? "")
          \(renderExtensionActions(item))
        </article>
        """
    }

    private static func renderHookItem(_ hook: ProjectPluginHookSurface) -> String {
        let action = if let title = hook.actionTitle, let commandID = hook.actionCommandID {
            extensionActionButton(
                title,
                testID: title == "Disable" ? "hook-disable" : "hook-trust",
                commandID: commandID
            )
        } else {
            ""
        }
        return """
        <article
          class="extension-card hook-card"
          data-testid="hook-item"
          data-kind="hook"
          data-status="\(escape(hook.statusLabel))"
        >
          <header>
            <span data-testid="extension-kind">Hook</span>
            <span data-testid="hook-status">\(escape(hook.statusLabel))</span>
          </header>
          <strong data-testid="hook-name">\(escape(hook.name))</strong>
          <p data-testid="hook-source">\(escape(hook.pluginName)) · \(escape(hook.event))</p>
          \(hook.matcher.map { #"<code data-testid="hook-matcher">Matcher: \#(escape($0))</code>"# } ?? "")
          \(hook.command.map { #"<code data-testid="hook-command">\#(escape($0))</code>"# } ?? "")
          <code data-testid="hook-path">\(escape(hook.relativePath))</code>
          \(hook.supportDetail.map { #"<p data-testid="hook-support">\#(escape($0))</p>"# } ?? "")
          \(action)
        </article>
        """
    }

    private static func renderMCPDetails(_ item: ProjectExtensionManifestSurface) -> String {
        [
            renderMCPMeta(item),
            renderMCPTools(item.toolDescriptors),
            renderMCPNames(
                "Resources",
                item.resourceNames,
                testID: "extension-mcp-resources",
                itemTestID: "extension-mcp-resource"
            ),
            renderMCPNames(
                "Prompts",
                item.promptNames,
                testID: "extension-mcp-prompts",
                itemTestID: "extension-mcp-prompt"
            ),
            renderMCPReferenceActions(
                "Resource Actions",
                item.resourceActions,
                testID: "extension-mcp-resource-action",
                titlePrefix: "Read"
            ),
            renderMCPReferenceActions(
                "Prompt Actions",
                item.promptActions,
                testID: "extension-mcp-prompt-action",
                titlePrefix: "Use"
            )
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func renderMCPMeta(_ item: ProjectExtensionManifestSurface) -> String {
        let labels = [
            item.protocolLabel.map { #"<span data-testid="extension-mcp-protocol">\#(escape($0))</span>"# },
            item.toolCountLabel.map { #"<span data-testid="extension-mcp-tools-count">\#(escape($0))</span>"# },
            item.resourceCountLabel.map { #"<span data-testid="extension-mcp-resources-count">\#(escape($0))</span>"# },
            item.promptCountLabel.map { #"<span data-testid="extension-mcp-prompts-count">\#(escape($0))</span>"# }
        ].compactMap { $0 }
        guard !labels.isEmpty else { return "" }
        return """
        <div class="extension-mcp-meta" data-testid="extension-mcp-meta">
          \(labels.joined(separator: " · "))
        </div>
        """
    }

    private static func renderMCPTools(_ tools: [MCPToolDescriptor]) -> String {
        guard !tools.isEmpty else { return "" }
        let chips = tools.map(renderMCPTool).joined(separator: "\n")
        return renderMCPGroup(title: "Tools", testID: "extension-mcp-tools", content: chips)
    }

    private static func renderMCPTool(_ tool: MCPToolDescriptor) -> String {
        let details = [tool.schemaSummary, tool.description]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return """
        <span class="extension-mcp-tool-chip" data-testid="extension-mcp-tool">
          <strong data-testid="extension-mcp-tool-name">\(escape(tool.name))</strong>
          \(details.isEmpty ? "" : #"<small data-testid="extension-mcp-tool-schema">\#(escape(details))</small>"#)
        </span>
        """
    }

    private static func renderMCPNames(
        _ title: String,
        _ names: [String],
        testID: String,
        itemTestID: String
    ) -> String {
        guard !names.isEmpty else { return "" }
        let chips = names
            .map { #"<span data-testid="\#(escape(itemTestID))">\#(escape($0))</span>"# }
            .joined(separator: "\n")
        return renderMCPGroup(title: title, testID: testID, content: chips)
    }

    private static func renderMCPReferenceActions(
        _ title: String,
        _ actions: [MCPReferenceActionSurface],
        testID: String,
        titlePrefix: String
    ) -> String {
        guard !actions.isEmpty else { return "" }
        let buttons = actions.map { action in
            commandButton(
                "\(titlePrefix) \(action.title)",
                testID: testID,
                commandID: action.commandID,
                hitTargetKind: .capsule,
                classes: ["extension-reference-action"]
            )
        }.joined(separator: "\n")
        return renderMCPGroup(title: title, testID: "\(testID)-group", content: buttons)
    }

    private static func renderMCPGroup(title: String, testID: String, content: String) -> String {
        """
        <div class="extension-mcp-group" data-testid="\(escape(testID))">
          <span class="extension-mcp-group-label" data-testid="extension-mcp-group-label">\(escape(title))</span>
          <div class="extension-mcp-chip-row">\(content)</div>
        </div>
        """
    }

    private static func renderExtensionActions(_ item: ProjectExtensionManifestSurface) -> String {
        var buttons: [String] = []
        if let commandID = item.installCommandID {
            buttons.append(extensionActionButton("Install", testID: "extension-install", commandID: commandID))
        }
        if let commandID = item.updateCommandID {
            buttons.append(extensionActionButton("Update", testID: "extension-update", commandID: commandID))
        }
        if let commandID = item.stopCommandID {
            buttons.append(extensionActionButton("Stop", testID: "extension-stop", commandID: commandID))
        }
        if let commandID = item.startCommandID {
            buttons.append(extensionActionButton("Start", testID: "extension-start", commandID: commandID))
        }
        return buttons.joined(separator: "\n")
    }

    private static func extensionActionButton(_ label: String, testID: String, commandID: String) -> String {
        commandButton(
            label,
            testID: testID,
            commandID: commandID,
            hitTargetKind: .formAction,
            classes: ["extension-action-button"]
        )
    }

    private static func commandButton(
        _ label: String,
        testID: String,
        commandID: String,
        hitTargetKind: WorkspaceHTMLHitTargetKind,
        classes: [String] = []
    ) -> String {
        Primitives.commandButton(
            label,
            testID: testID,
            commandID: commandID,
            hitTargetKind: hitTargetKind,
            classes: classes
        )
    }

    private static func escape(_ text: String) -> String {
        Primitives.escape(text)
    }
}
