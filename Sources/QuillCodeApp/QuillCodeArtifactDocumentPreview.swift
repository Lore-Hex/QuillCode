import SwiftUI

struct QuillCodeArtifactDocumentPreview: View {
    var artifact: ToolArtifactState

    @ViewBuilder
    var body: some View {
        if let pdfPreview = artifact.pdfPreview,
           let previewURL = artifactURL {
            pdfContent(pdfPreview, previewURL: previewURL)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel)
        } else if let mediaPreview = artifact.mediaPreview,
           let playbackURL = mediaPreview.playbackURL.flatMap(URL.init(string:)) {
            mediaContent(mediaPreview, playbackURL: playbackURL)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel)
        } else if let url = artifactURL {
            Link(destination: url) {
                content
                    .quillCodeLinkTarget(minWidth: 160, alignment: .leading, radius: 18)
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        } else {
            content
                .quillCodeTextButtonTarget(minWidth: 160, alignment: .leading, radius: 18)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let appshotPreview = artifact.appshotPreview,
           preview?.kind == .appshot {
            appshotContent(appshotPreview)
        } else if let pdfPreview = artifact.pdfPreview,
                  preview?.kind == .pdf {
            metadataContent(
                title: pdfPreview.title ?? artifact.label,
                metadataLines: pdfPreview.metadataLines
            )
        } else if let markdownPreview = artifact.markdownPreview {
            metadataContent(
                title: markdownPreview.title ?? artifact.label,
                metadataLines: markdownPreview.metadataLines
            )
        } else if let officePreview = artifact.officePreview {
            metadataContent(title: artifact.label, metadataLines: officePreview.metadataLines)
        } else if let tablePreview = artifact.tablePreview {
            tableContent(tablePreview)
        } else if let archivePreview = artifact.archivePreview {
            metadataContent(title: artifact.label, metadataLines: archivePreview.metadataLines)
        } else if let mediaPreview = artifact.mediaPreview {
            metadataContent(
                title: mediaPreview.title ?? artifact.label,
                metadataLines: mediaPreview.metadataLines
            )
        } else {
            genericContent
        }
    }

    private var genericContent: some View {
        previewSurface(minHeight: 74) {
            header(
                thumbnail: { iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "doc") },
                title: artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
        }
    }

    private func metadataContent(title: String, metadataLines: [String]) -> some View {
        previewSurface(minHeight: 92) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "doc.richtext")
                },
                title: title,
                subtitle: preview?.detail ?? artifact.detail
            )
            metadataPills(metadataLines)
        }
    }

    private func appshotContent(_ appshotPreview: ToolArtifactAppshotPreview) -> some View {
        previewSurface(minHeight: 96) {
            header(
                thumbnail: { appshotThumbnail(appshotPreview) },
                title: appshotPreview.title ?? artifact.label,
                subtitle: appshotPreview.summary ?? preview?.detail ?? artifact.detail,
                subtitleLineLimit: 2
            )
            appshotMetadata(appshotPreview.metadataLines)
            appshotReplayTimeline(appshotPreview)
        }
    }

    private func tableContent(_ tablePreview: ToolArtifactTablePreview) -> some View {
        previewSurface(minHeight: 116) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "tablecells")
                },
                title: artifact.label,
                subtitle: tablePreview.metadataLines.joined(separator: " · "),
                subtitleLineLimit: 2
            )
            tableGrid(tablePreview)
        }
    }

    private func pdfContent(_ pdfPreview: ToolArtifactPDFPreview, previewURL: URL) -> some View {
        previewSurface(minHeight: 252) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "doc.richtext")
                },
                title: pdfPreview.title ?? artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            QuillCodeArtifactPDFPagePreviewView(url: previewURL)
            HStack(alignment: .center, spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                metadataPills(pdfPreview.metadataLines)
                Spacer(minLength: 4)
                Link(destination: previewURL) {
                    Label("Open", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeLinkTarget(minWidth: 74, alignment: .center, radius: 12)
                .accessibilityLabel("Open \(artifact.label)")
            }
        }
    }

    private func mediaContent(_ mediaPreview: ToolArtifactMediaPreview, playbackURL: URL) -> some View {
        previewSurface(minHeight: mediaPreview.kind == .video ? 230 : 146) {
            header(
                thumbnail: {
                    iconThumbnail(width: 44, height: 52, systemImage: preview?.systemImage ?? "play.rectangle")
                },
                title: mediaPreview.title ?? artifact.label,
                subtitle: preview?.detail ?? artifact.detail
            )
            QuillCodeArtifactMediaPlaybackView(preview: mediaPreview, url: playbackURL)
            HStack(alignment: .center, spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                metadataPills(mediaPreview.metadataLines)
                Spacer(minLength: 4)
                Link(destination: playbackURL) {
                    Label("Open", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeLinkTarget(minWidth: 74, alignment: .center, radius: 12)
                .accessibilityLabel("Open \(artifact.label)")
            }
        }
    }

    private func previewSurface<Content: View>(
        minHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .quillCodeSurface(
            fill: Color.white.opacity(0.05),
            radius: 18,
            stroke: Color.white.opacity(0.08),
            shadow: false
        )
    }

    private func header<Thumbnail: View>(
        @ViewBuilder thumbnail: () -> Thumbnail,
        title: String,
        subtitle: String,
        subtitleLineLimit: Int = 1
    ) -> some View {
        HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
            thumbnail()
            VStack(alignment: .leading, spacing: 4) {
                Text(typeLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.blue)
                    .lineLimit(1)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(subtitleLineLimit)
            }
            Spacer(minLength: 4)
            externalLinkIcon
        }
    }

    @ViewBuilder
    private var externalLinkIcon: some View {
        if artifactURL != nil {
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .accessibilityHidden(true)
        }
    }

    private func iconThumbnail(width: CGFloat, height: CGFloat, systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(QuillCodePalette.blue.opacity(0.14))
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(QuillCodePalette.blue)
                .accessibilityHidden(true)
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func appshotThumbnail(_ appshotPreview: ToolArtifactAppshotPreview) -> some View {
        if let screenshotURL = appshotPreview.screenshotURL.flatMap(URL.init(string:)) {
            AsyncImage(url: screenshotURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    appshotFallbackThumbnail
                @unknown default:
                    appshotFallbackThumbnail
                }
            }
            .frame(width: 92, height: 58)
            .clipped()
            .background(Color.black.opacity(0.22))
            .quillCodeImageOutline(radius: 10)
        } else {
            appshotFallbackThumbnail
        }
    }

    private var appshotFallbackThumbnail: some View {
        iconThumbnail(width: 92, height: 58, systemImage: preview?.systemImage ?? "camera.viewfinder")
    }

    @ViewBuilder
    private func metadataPills(_ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func appshotMetadata(_ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 2)
        }
    }

    @ViewBuilder
    private func appshotReplayTimeline(_ appshotPreview: ToolArtifactAppshotPreview) -> some View {
        let groups = [
            ("Actions", appshotPreview.actionLabels),
            ("Frames", appshotPreview.frameLabels),
            ("Events", appshotPreview.eventLabels)
        ].filter { !$0.1.isEmpty }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.0) { title, labels in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QuillCodePalette.muted)
                        ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(QuillCodePalette.blue)
                                    .frame(width: 18, alignment: .trailing)
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(QuillCodePalette.text)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func tableGrid(_ tablePreview: ToolArtifactTablePreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tableRow(tablePreview.headers, isHeader: true)
            ForEach(Array(tablePreview.rows.enumerated()), id: \.offset) { _, row in
                tableRow(row, isHeader: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func tableRow(_ row: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                Text(cell.isEmpty ? " " : cell)
                    .font(.caption2.weight(isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? QuillCodePalette.text : QuillCodePalette.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 1)
                    }
            }
        }
        .background(isHeader ? Color.white.opacity(0.06) : Color.white.opacity(0.025))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
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
