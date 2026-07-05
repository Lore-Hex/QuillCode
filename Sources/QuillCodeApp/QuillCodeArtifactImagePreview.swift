import SwiftUI

struct QuillCodeArtifactImagePreview: View {
    var artifact: ToolArtifactState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            imageContent
            imageMetadata
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

    @ViewBuilder
    private var imageContent: some View {
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
    }

    private var imageMetadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let preview = artifact.imagePreview {
                Text(preview.typeLine)
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

    private var previewURL: URL? {
        artifact.previewURL.flatMap(URL.init(string:))
    }

    private var accessibilityLabel: String {
        guard let preview = artifact.imagePreview else {
            return "Image preview \(artifact.label)"
        }
        return "\(preview.typeLine) preview \(artifact.label)"
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
