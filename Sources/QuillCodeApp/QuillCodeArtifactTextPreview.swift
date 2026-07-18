import SwiftUI

struct QuillCodeArtifactTextPreview: View {
    var artifact: ToolArtifactState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            metadata
            ScrollView(.horizontal, showsIndicators: false) {
                Text(artifact.textPreview ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(14)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.30))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(10)
        .quillCodeSurface(
            fill: Color.white.opacity(0.05),
            radius: 18,
            stroke: Color.white.opacity(0.08),
            shadow: false
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Text preview \(artifact.label)")
    }

    private var header: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "doc.plaintext")
                .foregroundStyle(QuillCodePalette.blue)
            Text(artifact.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("Preview")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if let preview = artifact.sourceTextPreview {
            HStack(spacing: 6) {
                ForEach(preview.metadataLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
        }
    }
}
