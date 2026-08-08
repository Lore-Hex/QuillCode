import SwiftUI

struct QuillCodeArtifactChip: View {
    var artifact: ToolArtifactState

    @ViewBuilder
    var body: some View {
        if let url = artifactURL {
            Link(destination: url) {
                label
                    .quillCodeLinkTarget(
                        minWidth: 96,
                        alignment: .leading,
                        radius: QuillCodeMetrics.compactControlRadius
                    )
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .accessibilityLabel("Artifact \(artifact.label)")
            .help(artifact.detail)
        } else {
            label
                .quillCodeTextButtonTarget(
                    minWidth: 96,
                    alignment: .leading,
                    radius: QuillCodeMetrics.compactControlRadius
                )
                .accessibilityLabel("Artifact \(artifact.label)")
                .help(artifact.detail)
        }
    }

    private var label: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Image(systemName: iconName)
            Text(artifact.label)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(QuillCodePalette.blue)
        .frame(maxWidth: 260, alignment: .leading)
        .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(QuillCodePalette.blue.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                .stroke(QuillCodePalette.blue.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous))
    }

    private var artifactURL: URL? {
        artifact.href.flatMap(URL.init(string:))
    }

    private var iconName: String {
        if let documentPreview = artifact.documentPreview {
            return documentPreview.systemImage
        }
        switch artifact.kind {
        case .url:
            return "link"
        case .file:
            return "doc.text"
        case .path:
            return "folder"
        }
    }
}
