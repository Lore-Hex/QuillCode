import SwiftUI

extension QuillCodeExtensionsPaneView {
    var extensionCards: some View {
        ScrollView(.horizontal) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                ForEach(extensions.items) { item in
                    extensionCard(item)
                }
            }
        }
    }

    private func extensionCard(_ item: ProjectExtensionManifestSurface) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            extensionStatusHeader(for: item)
            extensionIdentity(for: item)
            extensionLaunchMetadata(for: item)
            extensionProbeMetadata(for: item)
            extensionCardFooter(for: item)
        }
        .padding(12)
        .frame(width: 280, alignment: .topLeading)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func extensionStatusHeader(for item: ProjectExtensionManifestSurface) -> some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
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
    }

    @ViewBuilder
    private func extensionIdentity(for item: ProjectExtensionManifestSurface) -> some View {
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
            extensionMetadataLine(sourceURL)
        }
        extensionMetadataLine(item.relativePath)
    }

    @ViewBuilder
    private func extensionLaunchMetadata(for item: ProjectExtensionManifestSurface) -> some View {
        if let launchCommand = item.launchCommand {
            extensionMetadataLine(launchCommand)
        }
        if let installCommand = item.installCommand {
            extensionMetadataLine(installCommand)
        }
        if let serverLabel = item.serverLabel {
            Text(serverLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
        }
    }

    private func extensionMetadataLine(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(QuillCodePalette.muted)
            .lineLimit(1)
    }

    @ViewBuilder
    private func extensionProbeMetadata(for item: ProjectExtensionManifestSurface) -> some View {
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
    }

    private func extensionCardFooter(for item: ProjectExtensionManifestSurface) -> some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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

    @ViewBuilder
    private func extensionActionButtons(for item: ProjectExtensionManifestSurface) -> some View {
        if let installCommandID = item.installCommandID {
            extensionActionButton(
                title: "Install",
                commandID: installCommandID,
                itemName: item.name,
                role: .secondary
            )
        }
        if let updateCommandID = item.updateCommandID {
            extensionActionButton(
                title: "Update",
                commandID: updateCommandID,
                itemName: item.name,
                role: .secondary
            )
        }
        if let stopCommandID = item.stopCommandID {
            extensionActionButton(
                title: "Stop",
                commandID: stopCommandID,
                itemName: item.name,
                role: .destructive
            )
        } else if let startCommandID = item.startCommandID {
            extensionActionButton(
                title: "Start",
                commandID: startCommandID,
                itemName: item.name,
                role: .primary
            )
        }
    }

    private func extensionActionButton(
        title: String,
        commandID: String,
        itemName: String,
        role: QuillCodeActionButtonStyle.Tone
    ) -> some View {
        Button(title) {
            onCommand(extensionCommand(id: commandID, title: "\(title) \(itemName)"))
        }
        .buttonStyle(QuillCodeActionButtonStyle(role, minWidth: 74))
        .quillCodeFormActionTarget(minWidth: 74)
    }

    func statusColor(for status: String) -> Color {
        switch status {
        case "Discovered", "Running", "Ready":
            return QuillCodePalette.green
        case "Available", "Probing":
            return QuillCodePalette.blue
        case "Failed", "Missing command":
            return QuillCodePalette.red
        default:
            return QuillCodePalette.muted
        }
    }

    func extensionCommand(id: String, title: String) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: title,
            category: WorkspaceCommandPalette.extensionsCategory,
            keywords: ["mcp", "server", title]
        )
    }
}
