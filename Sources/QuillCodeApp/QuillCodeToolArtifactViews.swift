import SwiftUI
import QuillCodeCore

struct QuillCodeArtifactChip: View {
    var artifact: ToolArtifactState

    var body: some View {
        Group {
            if let url = artifactURL {
                Link(destination: url) {
                    label
                }
            } else {
                label
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Artifact \(artifact.label)")
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
            VStack(alignment: .leading, spacing: 1) {
                Text(artifact.label)
                    .lineLimit(1)
                Text(artifact.detail)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(QuillCodePalette.blue)
        .frame(maxWidth: 260, alignment: .leading)
        .frame(minHeight: 40)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(QuillCodePalette.blue.opacity(0.12))
        .overlay(
            Capsule()
                .stroke(QuillCodePalette.blue.opacity(0.28), lineWidth: 1)
        )
        .clipShape(Capsule())
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

struct QuillCodeArtifactDocumentPreview: View {
    var artifact: ToolArtifactState

    var body: some View {
        Group {
            if let url = artifactURL {
                Link(destination: url) {
                    content
                }
            } else {
                content
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(QuillCodePalette.blue.opacity(0.14))
                Image(systemName: preview?.systemImage ?? "doc")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.blue)
                    .accessibilityHidden(true)
            }
            .frame(width: 44, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(typeLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.blue)
                    .lineLimit(1)
                Text(artifact.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
                Text(preview?.detail ?? artifact.detail)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if artifactURL != nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .quillCodeSurface(
            fill: Color.white.opacity(0.05),
            radius: 18,
            stroke: Color.white.opacity(0.08),
            shadow: false
        )
    }

    private var preview: ToolArtifactDocumentPreview? {
        artifact.documentPreview
    }

    private var typeLine: String {
        guard let preview else { return "Document" }
        return "\(preview.typeLabel) · \(preview.extensionLabel)"
    }

    private var artifactURL: URL? {
        artifact.href.flatMap(URL.init(string:))
    }

    private var accessibilityLabel: String {
        "\(typeLine) preview \(artifact.label)"
    }
}

struct QuillCodeArtifactImagePreview: View {
    var artifact: ToolArtifactState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = previewURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    @unknown default:
                        fallback
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Color.black.opacity(0.22))
                .quillCodeImageOutline(radius: 10)
            } else {
                fallback
            }
            VStack(alignment: .leading, spacing: 3) {
                if let preview = artifact.imagePreview {
                    Text("\(preview.typeLabel) · \(preview.extensionLabel)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(QuillCodePalette.blue)
                        .lineLimit(1)
                    Text(artifact.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.text)
                        .lineLimit(1)
                    Text(preview.detail)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                } else {
                    Text(artifact.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.text)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .quillCodeSurface(
            fill: Color.white.opacity(0.05),
            radius: 18,
            stroke: Color.white.opacity(0.08),
            shadow: false
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var previewURL: URL? {
        artifact.previewURL.flatMap(URL.init(string:))
    }

    private var accessibilityLabel: String {
        guard let preview = artifact.imagePreview else {
            return "Image preview \(artifact.label)"
        }
        return "\(preview.typeLabel) \(preview.extensionLabel) preview \(artifact.label)"
    }

    private var fallback: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title3)
            Text("Preview unavailable")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(QuillCodePalette.muted)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color.black.opacity(0.22))
        .quillCodeImageOutline(radius: 10)
    }
}

struct QuillCodeArtifactTextPreview: View {
    var artifact: ToolArtifactState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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
}
