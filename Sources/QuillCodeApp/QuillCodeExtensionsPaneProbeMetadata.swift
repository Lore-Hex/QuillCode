import SwiftUI
import QuillCodeTools

extension QuillCodeExtensionsPaneView {
    @ViewBuilder
    func probeMetadataCounts(for item: ProjectExtensionManifestSurface) -> some View {
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
    func probeMetadataChips(for item: ProjectExtensionManifestSurface) -> some View {
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
                probeMetadataGroupTitle("Tools")
                LazyVGrid(columns: probeToolGridColumns, alignment: .leading, spacing: denseSpacing) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                        probeToolChip(tool)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func probeMetadataGroup(title: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                probeMetadataGroupTitle(title)
                LazyVGrid(columns: probeValueGridColumns, alignment: .leading, spacing: denseSpacing) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        probeValueChip(value)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func probeReferenceActions(for item: ProjectExtensionManifestSurface) -> some View {
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
                probeMetadataGroupTitle(title)
                LazyVGrid(columns: probeActionGridColumns, alignment: .leading, spacing: denseSpacing) {
                    ForEach(actions) { action in
                        Button("\(titlePrefix) \(action.title)") {
                            onCommand(extensionCommand(id: action.commandID, title: "\(titlePrefix) \(action.title)"))
                        }
                        .buttonStyle(QuillCodeActionButtonStyle(.secondary, minWidth: 96))
                        .quillCodeCapsuleButtonTarget(minWidth: 96)
                    }
                }
            }
        }
    }

}

extension ProjectExtensionManifestSurface {
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
