import SwiftUI

struct QuillCodeImageAttachmentStrip: View {
    var attachments: [ImageAttachmentSurface]
    var onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: 4) {
                            QuillCodeAttachmentImage(attachment: attachment)
                                .frame(width: 96, height: 68)
                            Text(attachment.displayName)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 96, alignment: .leading)
                        }
                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body.weight(.semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.black.opacity(0.72))
                                .quillCodeIconButtonTarget(
                                    size: QuillCodeMetrics.minimumHitTarget,
                                    radius: QuillCodeMetrics.minimumHitTarget / 2
                                )
                        }
                        .buttonStyle(QuillCodePressableButtonStyle())
                        .offset(x: 10, y: -10)
                        .help("Remove \(attachment.displayName)")
                        .accessibilityLabel("Remove attached image \(attachment.displayName)")
                        .accessibilityIdentifier("quillcode-attachment-remove")
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(attachment.accessibilityLabel)
                    .accessibilityIdentifier("quillcode-composer-attachment")
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Attached images")
    }
}

struct QuillCodeMessageAttachmentGrid: View {
    var attachments: [ImageAttachmentSurface]

    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 220), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(attachments) { attachment in
                VStack(alignment: .leading, spacing: 4) {
                    QuillCodeAttachmentImage(attachment: attachment)
                        .frame(minHeight: 112, maxHeight: 220)
                    Text(attachment.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(attachment.accessibilityLabel)
            }
        }
        .frame(minWidth: 132, maxWidth: 448, alignment: .leading)
    }
}

private struct QuillCodeAttachmentImage: View {
    var attachment: ImageAttachmentSurface

    var body: some View {
        AsyncImage(url: URL(string: attachment.previewURL)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                fallback
            @unknown default:
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
        .quillCodeImageOutline(radius: 8)
    }

    private var fallback: some View {
        Image(systemName: "photo")
            .font(.title3)
            .foregroundStyle(QuillCodePalette.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
