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
            if let installCommand = item.installCommand {
                Text(installCommand)
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
                    probeReferenceActions(for: item)
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
        if let installCommandID = item.installCommandID {
            Button("Install") {
                onCommand(extensionCommand(id: installCommandID, title: "Install \(item.name)"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .quillCodeHitTarget(minWidth: 74)
        }
        if let updateCommandID = item.updateCommandID {
            Button("Update") {
                onCommand(extensionCommand(id: updateCommandID, title: "Update \(item.name)"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .quillCodeHitTarget(minWidth: 74)
        }
        if let stopCommandID = item.stopCommandID {
            Button("Stop") {
                onCommand(extensionCommand(id: stopCommandID, title: "Stop \(item.name)"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .quillCodeHitTarget(minWidth: 74)
        } else if let startCommandID = item.startCommandID {
            Button("Start") {
                onCommand(extensionCommand(id: startCommandID, title: "Start \(item.name)"))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .quillCodeHitTarget(minWidth: 74)
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

    @ViewBuilder
    private func probeReferenceActions(for item: ProjectExtensionManifestSurface) -> some View {
        if !item.resourceActions.isEmpty || !item.promptActions.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                probeReferenceActionGroup(
                    title: "Use Resources",
                    actions: item.resourceActions,
                    titlePrefix: "Read"
                )
                probeReferenceActionGroup(
                    title: "Use Prompts",
                    actions: item.promptActions,
                    titlePrefix: "Use"
                )
            }
        }
    }

    @ViewBuilder
    private func probeReferenceActionGroup(
        title: String,
        actions: [MCPReferenceActionSurface],
        titlePrefix: String
    ) -> some View {
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 5)], alignment: .leading, spacing: 5) {
                    ForEach(actions) { action in
                        Button("\(titlePrefix) \(action.title)") {
                            onCommand(extensionCommand(id: action.commandID, title: "\(titlePrefix) \(action.title)"))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .quillCodeHitTarget(minWidth: 96)
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
