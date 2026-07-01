import SwiftUI
import QuillCodeTools

extension QuillCodeExtensionsPaneView {
    var denseSpacing: CGFloat {
        QuillCodeMetrics.denseControlClusterSpacing
    }

    var probeToolGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 104), spacing: denseSpacing)]
    }

    var probeValueGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 82), spacing: denseSpacing)]
    }

    var probeActionGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: denseSpacing)]
    }

    func probeMetadataGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(QuillCodePalette.muted)
            .lineLimit(1)
    }

    func probeToolChip(_ tool: MCPToolDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tool.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.blue)
                .lineLimit(1)
                .truncationMode(.middle)
            if !tool.schemaSummary.isEmpty || !tool.description.isEmpty {
                Text(probeToolSummary(tool))
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

    func probeValueChip(_ value: String) -> some View {
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

    func probeToolSummary(_ tool: MCPToolDescriptor) -> String {
        [tool.schemaSummary, tool.description]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
