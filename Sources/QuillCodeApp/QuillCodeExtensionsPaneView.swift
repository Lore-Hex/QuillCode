import SwiftUI
import QuillCodeTools

struct QuillCodeExtensionsPaneView: View {
    var extensions: WorkspaceExtensionsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if extensions.items.isEmpty && extensions.hookItems.isEmpty {
                QuillCodePaneEmptyStateView(
                    title: extensions.emptyTitle,
                    subtitle: extensions.emptySubtitle
                )
            } else {
                extensionCards
            }
        }
        .padding(14)
        .frame(height: extensions.items.isEmpty && extensions.hookItems.isEmpty ? 170 : 292)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                QuillCodePaneCountPill(label: "Plugins", count: extensions.pluginCount)
                QuillCodePaneCountPill(label: "Skills", count: extensions.skillCount)
                QuillCodePaneCountPill(label: "MCP", count: extensions.mcpServerCount)
                QuillCodePaneCountPill(label: "Hooks", count: extensions.hookCount)
                if extensions.availableCount > 0 {
                    QuillCodePaneCountPill(label: "Available", count: extensions.availableCount)
                }
            }
        }
    }
}
