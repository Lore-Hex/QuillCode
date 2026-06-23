import SwiftUI
import QuillCodeCore

struct QuillCodeToolCardView: View {
    var card: ToolCardState
    var isCopied: Bool
    var onCopy: () -> Void
    @State private var isDetailsOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(card: ToolCardState, isCopied: Bool = false, onCopy: @escaping () -> Void = {}) {
        self.card = card
        self.isCopied = isCopied
        self.onCopy = onCopy
        self._isDetailsOpen = State(initialValue: card.opensDetailsByDefault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolHeader
            HStack {
                QuillCodeTranscriptCopyButton(
                    label: copyActionLabel,
                    copiedLabel: "Copied",
                    isCopied: isCopied,
                    action: onCopy
                )
                Spacer()
            }
            if !card.artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Artifacts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(card.artifacts.enumerated()), id: \.offset) { _, artifact in
                                QuillCodeArtifactChip(artifact: artifact)
                            }
                        }
                    }
                }
            }
            if !card.textPreviewArtifacts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Text previews")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(card.textPreviewArtifacts) { artifact in
                            QuillCodeArtifactTextPreview(artifact: artifact)
                        }
                    }
                }
            }
            if !card.documentPreviewArtifacts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Document previews")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(card.documentPreviewArtifacts) { artifact in
                            QuillCodeArtifactDocumentPreview(artifact: artifact)
                        }
                    }
                }
            }
            if !card.imagePreviewArtifacts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Previews")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(card.imagePreviewArtifacts) { artifact in
                            QuillCodeArtifactImagePreview(artifact: artifact)
                        }
                    }
                }
            }

            if card.inputJSON != nil || card.outputJSON != nil {
                DisclosureGroup(isExpanded: $isDetailsOpen) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let inputJSON = card.inputJSON {
                            QuillCodeCodeBlock(title: "Input", text: inputJSON)
                        }
                        if let outputJSON = card.outputJSON {
                            QuillCodeCodeBlock(title: "Output", text: outputJSON)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Text(detailsToggleLabel)
                        if !isDetailsOpen, card.status == .done {
                            Text("Raw tool data")
                                .foregroundStyle(QuillCodePalette.muted)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.blue)
                }
                .tint(QuillCodePalette.blue)
                .onChange(of: card.status) { _, status in
                    isDetailsOpen = ToolCardState.defaultDensity(status: status, isExpanded: card.isExpanded) == .expanded
                }
                .onChange(of: card.density) { _, density in
                    isDetailsOpen = density == .expanded
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 760, minHeight: minimumHeight, alignment: .topLeading)
        .quillCodeSurface(
            fill: QuillCodePalette.panel,
            radius: QuillCodeMetrics.toolCardRadius,
            stroke: cardStrokeColor,
            shadow: true
        )
        .overlay(alignment: .leading) {
            if let executionContext = card.executionContext {
                QuillCodeExecutionRail(context: executionContext)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isDetailsOpen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var toolHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 34, height: 34)
                .background(statusColor.opacity(0.14))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(card.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let executionContext = card.executionContext {
                        QuillCodeExecutionContextChip(context: executionContext)
                    }
                }
                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, alignment: .leading)

            Spacer(minLength: 10)

            QuillCodeToolStatusBadge(
                status: card.status,
                tint: statusColor,
                iconName: statusBadgeIconName
            )
        }
        .frame(minHeight: QuillCodeMetrics.toolCardHeaderHeight, alignment: .top)
    }

    private var minimumHeight: CGFloat {
        card.density == .collapsed
            ? QuillCodeMetrics.compactToolCardMinimumHeight
            : QuillCodeMetrics.toolCardMinimumHeight
    }

    private var statusColor: Color {
        switch card.status {
        case .queued, .running:
            return QuillCodePalette.blue
        case .done:
            return QuillCodePalette.green
        case .failed:
            return QuillCodePalette.red
        case .review:
            return QuillCodePalette.yellow
        }
    }

    private var cardStrokeColor: Color {
        switch card.status {
        case .queued, .running, .done:
            return Color.white.opacity(0.09)
        case .failed, .review:
            return statusColor.opacity(0.42)
        }
    }

    private var iconName: String {
        switch card.status {
        case .queued:
            return "clock"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .done:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .review:
            return "shield.lefthalf.filled"
        }
    }

    private var statusBadgeIconName: String {
        switch card.status {
        case .queued:
            return "clock.fill"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .done:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .review:
            return "checkmark.shield.fill"
        }
    }

    private var detailsToggleLabel: String {
        if isDetailsOpen {
            return "Hide details"
        }
        switch (card.inputJSON != nil, card.outputJSON != nil) {
        case (true, true):
            return "Show details"
        case (true, false):
            return "Show input"
        case (false, true):
            return "Show output"
        case (false, false):
            return "Show details"
        }
    }

    private var copyActionLabel: String {
        if card.outputJSON != nil {
            return "Copy output"
        }
        if card.inputJSON != nil {
            return "Copy input"
        }
        return "Copy"
    }

    private var accessibilityLabel: String {
        let context = card.executionContext.map {
            ", \($0.label) \($0.detail)"
        } ?? ""
        return "\(card.title), \(card.status.rawValue), \(card.densityAccessibilityLabel)\(context)"
    }
}

private struct QuillCodeToolStatusBadge: View {
    var status: ToolCardStatus
    var tint: Color
    var iconName: String

    var body: some View {
        Label(status.rawValue.capitalized, systemImage: iconName)
            .font(.caption.monospacedDigit().weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15))
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
            .clipShape(Capsule())
            .help(status.rawValue.capitalized)
            .accessibilityLabel("Tool status \(status.rawValue)")
    }
}

struct QuillCodeExecutionContextChip: View {
    var context: ExecutionContextSurface

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.caption2.weight(.bold))
            Text(title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(background)
        .overlay(
            Capsule()
                .stroke(tint.opacity(context.kind == .sshRemote ? 0.38 : 0.24), lineWidth: 1)
        )
        .clipShape(Capsule())
        .accessibilityLabel("\(context.label) \(context.detail)")
    }

    private var title: String {
        switch context.kind {
        case .local:
            return context.label
        case .sshRemote:
            return "\(context.label) · \(context.detail)"
        }
    }

    private var iconName: String {
        switch context.kind {
        case .local:
            return "desktopcomputer"
        case .sshRemote:
            return "point.3.connected.trianglepath.dotted"
        }
    }

    private var tint: Color {
        switch context.kind {
        case .local:
            return QuillCodePalette.muted
        case .sshRemote:
            return QuillCodePalette.purple
        }
    }

    private var background: Color {
        switch context.kind {
        case .local:
            return Color.white.opacity(0.07)
        case .sshRemote:
            return QuillCodePalette.purple.opacity(0.16)
        }
    }
}

struct QuillCodeExecutionRail: View {
    var context: ExecutionContextSurface

    var body: some View {
        Rectangle()
            .fill(tint.opacity(context.kind == .sshRemote ? 0.78 : 0.42))
            .frame(width: 3)
            .padding(.vertical, 8)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .padding(.leading, 1)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch context.kind {
        case .local:
            return QuillCodePalette.muted
        case .sshRemote:
            return QuillCodePalette.purple
        }
    }
}

private struct QuillCodeArtifactChip: View {
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

private struct QuillCodeArtifactDocumentPreview: View {
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

private struct QuillCodeArtifactImagePreview: View {
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

private struct QuillCodeArtifactTextPreview: View {
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

private struct QuillCodeCodeBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: QuillCodeMetrics.toolCardRawDetailsMaxHeight, alignment: .topLeading)
            .background(Color.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}
