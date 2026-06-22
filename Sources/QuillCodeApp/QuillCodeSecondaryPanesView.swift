import SwiftUI
import QuillCodeTools

struct QuillCodeExtensionsPaneView: View {
    var extensions: WorkspaceExtensionsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if extensions.items.isEmpty {
                QuillCodePaneEmptyStateView(
                    title: extensions.emptyTitle,
                    subtitle: extensions.emptySubtitle
                )
            } else {
                extensionCards
            }
        }
        .padding(14)
        .frame(height: extensions.items.isEmpty ? 170 : 280)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(QuillCodePalette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(extensions.title)
                    .font(.headline)
                Text(extensions.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                QuillCodePaneCountPill(label: "Plugins", count: extensions.pluginCount)
                QuillCodePaneCountPill(label: "Skills", count: extensions.skillCount)
                QuillCodePaneCountPill(label: "MCP", count: extensions.mcpServerCount)
            }
        }
    }

    private var extensionCards: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(extensions.items) { item in
                    extensionCard(item)
                }
            }
        }
    }

    private func extensionCard(_ item: ProjectExtensionManifestSurface) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(item.kindLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                Text(item.statusLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusColor(for: item.statusLabel))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor(for: item.statusLabel).opacity(0.14))
                    .clipShape(Capsule())
                Spacer()
            }
            Text(item.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(2)
            }
            if let versionLabel = item.versionLabel {
                Text(versionLabel)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(QuillCodePalette.green)
                    .lineLimit(1)
            }
            if let sourceURL = item.sourceURL {
                Text(sourceURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            Text(item.relativePath)
                .font(.caption2.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            if let launchCommand = item.launchCommand {
                Text(launchCommand)
                    .font(.caption2.monospaced())
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            if let serverLabel = item.serverLabel {
                Text(serverLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            if let probeError = item.probeError {
                Text(probeError)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.red)
                    .lineLimit(2)
            } else if item.hasMCPProbeMetadata {
                VStack(alignment: .leading, spacing: 5) {
                    probeMetadataCounts(for: item)
                    probeMetadataChips(for: item)
                }
            }
            HStack(spacing: 8) {
                if let transportLabel = item.transportLabel {
                    Text(transportLabel)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(QuillCodePalette.panel.opacity(0.9))
                        .clipShape(Capsule())
                }
                Spacer()
                extensionActionButtons(for: item)
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .topLeading)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func extensionActionButtons(for item: ProjectExtensionManifestSurface) -> some View {
        if let updateCommandID = item.updateCommandID {
            Button("Update") {
                onCommand(extensionCommand(id: updateCommandID, title: "Update \(item.name)"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        if let stopCommandID = item.stopCommandID {
            Button("Stop") {
                onCommand(extensionCommand(id: stopCommandID, title: "Stop \(item.name)"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else if let startCommandID = item.startCommandID {
            Button("Start") {
                onCommand(extensionCommand(id: startCommandID, title: "Start \(item.name)"))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func probeMetadataCounts(for item: ProjectExtensionManifestSurface) -> some View {
        let labels = [
            item.protocolLabel,
            item.toolCountLabel,
            item.resourceCountLabel,
            item.promptCountLabel
        ].compactMap { $0 }

        if !labels.isEmpty {
            Text(labels.joined(separator: " · "))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func probeMetadataChips(for item: ProjectExtensionManifestSurface) -> some View {
        if !item.toolNames.isEmpty || !item.resourceNames.isEmpty || !item.promptNames.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                probeMetadataToolGroup(tools: item.toolDescriptors)
                probeMetadataGroup(title: "Resources", values: item.resourceNames)
                probeMetadataGroup(title: "Prompts", values: item.promptNames)
            }
        }
    }

    @ViewBuilder
    private func probeMetadataToolGroup(tools: [MCPToolDescriptor]) -> some View {
        if !tools.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tools")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 5)], alignment: .leading, spacing: 5) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(QuillCodePalette.blue)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !tool.schemaSummary.isEmpty || !tool.description.isEmpty {
                                Text([tool.schemaSummary, tool.description].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(QuillCodePalette.blue.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func probeMetadataGroup(title: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 5)], alignment: .leading, spacing: 5) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(QuillCodePalette.blue)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(QuillCodePalette.blue.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Discovered", "Running", "Ready":
            return QuillCodePalette.green
        case "Probing":
            return QuillCodePalette.blue
        case "Failed", "Missing command":
            return QuillCodePalette.red
        default:
            return QuillCodePalette.muted
        }
    }

    private func extensionCommand(id: String, title: String) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: title,
            category: WorkspaceCommandPalette.extensionsCategory,
            keywords: ["mcp", "server", title]
        )
    }
}

private extension ProjectExtensionManifestSurface {
    var hasMCPProbeMetadata: Bool {
        toolCountLabel != nil
            || resourceCountLabel != nil
            || promptCountLabel != nil
            || protocolLabel != nil
            || !toolDescriptors.isEmpty
            || !resourceNames.isEmpty
            || !promptNames.isEmpty
    }
}

struct QuillCodeMemoriesPaneView: View {
    var memories: WorkspaceMemoriesSurface
    var onCommand: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if memories.items.isEmpty {
                QuillCodePaneEmptyStateView(
                    title: memories.emptyTitle,
                    subtitle: memories.emptySubtitle
                )
            } else {
                memoryCards
            }
        }
        .padding(14)
        .frame(height: memories.items.isEmpty ? 170 : 220)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(QuillCodePalette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(memories.title)
                    .font(.headline)
                Text(memories.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                QuillCodePaneCountPill(label: "Global", count: memories.globalCount)
                QuillCodePaneCountPill(label: "Project", count: memories.projectCount)
            }
            Button {
                onCommand("memory-add")
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var memoryCards: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(memories.items) { item in
                    memoryCard(item)
                }
            }
        }
    }

    private func memoryCard(_ item: MemoryNoteSurface) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(item.scopeLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(QuillCodePalette.blue.opacity(0.14))
                    .clipShape(Capsule())
                Text(item.byteCountLabel)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                Spacer()
                if item.canDelete, let deleteCommandID = item.deleteCommandID {
                    Button {
                        onCommand(deleteCommandID)
                    } label: {
                        Label("Forget", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(QuillCodePalette.muted)
                    .help("Forget this global memory")
                }
            }
            Text(item.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text(item.preview)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(3)
            Text(item.relativePath)
                .font(.caption2.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 300, alignment: .topLeading)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct QuillCodeAutomationsPaneView: View {
    var automations: WorkspaceAutomationsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if automations.workflows.isEmpty {
                QuillCodePaneEmptyStateView(
                    title: automations.emptyTitle,
                    subtitle: automations.emptySubtitle
                )
            } else {
                automationGrid
            }
        }
        .padding(14)
        .frame(minHeight: 190)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(QuillCodePalette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(automations.title)
                    .font(.headline)
                Text(automations.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(2)
            }
            Spacer()
            createMenu
            Text(automations.statusLabel)
                .font(.caption.weight(.semibold))
                .fontDesign(.rounded)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(QuillCodePalette.blue.opacity(0.14))
                .foregroundStyle(QuillCodePalette.blue)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var createMenu: some View {
        if automations.createThreadFollowUpCommand != nil
            || automations.createWorkspaceScheduleCommand != nil
            || !automations.scheduleThreadFollowUpCommands.isEmpty
            || !automations.scheduleWorkspaceScheduleCommands.isEmpty {
            Menu {
                if let createCommand = automations.createThreadFollowUpCommand {
                    Button(createCommand.title) {
                        onCommand(createCommand)
                    }
                    .disabled(!createCommand.isEnabled)
                }
                if let createCommand = automations.createWorkspaceScheduleCommand {
                    Button(createCommand.title) {
                        onCommand(createCommand)
                    }
                    .disabled(!createCommand.isEnabled)
                }
                if !automations.scheduleThreadFollowUpCommands.isEmpty {
                    Divider()
                    ForEach(automations.scheduleThreadFollowUpCommands, id: \.id) { command in
                        Button(command.title) {
                            onCommand(command)
                        }
                        .disabled(!command.isEnabled)
                    }
                }
                if !automations.scheduleWorkspaceScheduleCommands.isEmpty {
                    Divider()
                    ForEach(automations.scheduleWorkspaceScheduleCommands, id: \.id) { command in
                        Button(command.title) {
                            onCommand(command)
                        }
                        .disabled(!command.isEnabled)
                    }
                }
            } label: {
                Label("Create", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var automationGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(automations.workflows) { workflow in
                automationCard(workflow)
            }
        }
    }

    private func automationCard(_ workflow: AutomationWorkflowSurface) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(workflow.scheduleLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.blue)
                Spacer()
                Text(workflow.statusLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Text(workflow.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text(workflow.detail)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(3)
            automationActions(for: workflow)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func automationActions(for workflow: AutomationWorkflowSurface) -> some View {
        if workflow.runCommandID != nil || workflow.primaryCommandID != nil || workflow.deleteCommandID != nil {
            Divider()
            HStack(spacing: 8) {
                if let commandID = workflow.runCommandID,
                   let actionTitle = workflow.runActionTitle {
                    Button(actionTitle) {
                        onCommand(automationCommand(id: commandID, title: actionTitle))
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let commandID = workflow.primaryCommandID,
                   let actionTitle = workflow.primaryActionTitle {
                    Button(actionTitle) {
                        onCommand(automationCommand(id: commandID, title: actionTitle))
                    }
                    .buttonStyle(.bordered)
                }
                if let commandID = workflow.deleteCommandID {
                    Button("Delete", role: .destructive) {
                        onCommand(automationCommand(id: commandID, title: "Delete automation"))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func automationCommand(id: String, title: String) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: title,
            category: WorkspaceCommandPalette.automationsCategory,
            keywords: ["automation", "schedule", "follow-up"]
        )
    }
}

private struct QuillCodePaneCountPill: View {
    var label: String
    var count: Int

    var body: some View {
        Text("\(count) \(label)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(QuillCodePalette.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(QuillCodePalette.blue.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct QuillCodePaneEmptyStateView: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
