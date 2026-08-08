import SwiftUI
import QuillCodeCore

struct QuillCodeToolCardView: View {
    var card: ToolCardState
    var isCopied: Bool
    var onCopy: () -> Void
    var onAction: (ToolCardActionSurface) -> Void
    @State private var isDetailsOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        card: ToolCardState,
        isCopied: Bool = false,
        onCopy: @escaping () -> Void = {},
        onAction: @escaping (ToolCardActionSurface) -> Void = { _ in }
    ) {
        self.card = card
        self.isCopied = isCopied
        self.onCopy = onCopy
        self.onAction = onAction
        self._isDetailsOpen = State(initialValue: card.opensDetailsByDefault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolHeaderControl
            if let progress = card.progress, card.status == .running {
                progressView(progress)
            }
            if !card.actions.isEmpty {
                QuillCodeToolCardActionRow(actions: card.actions, onAction: onAction)
            }
            if showsTopLevelCopyAction {
                copyActionButton
            }
            if !displayedArtifacts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                        ForEach(Array(displayedArtifacts.enumerated()), id: \.offset) { _, artifact in
                            QuillCodeArtifactChip(artifact: artifact)
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
                    LazyVGrid(columns: adaptivePreviewColumns, spacing: QuillCodeMetrics.controlClusterSpacing) {
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
                    LazyVGrid(columns: adaptivePreviewColumns, spacing: QuillCodeMetrics.controlClusterSpacing) {
                        ForEach(Array(card.imagePreviewArtifacts.enumerated()), id: \.element.id) { index, artifact in
                            QuillCodeArtifactImagePreview(
                                artifact: artifact,
                                sequenceLabel: imagePreviewSequenceLabel(index: index)
                            )
                        }
                    }
                }
            }

            if hasDetails, isDetailsOpen {
                detailsContent
                    .padding(.top, 2)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: 760, minHeight: minimumHeight, alignment: .topLeading)
        // Flat, not floating: a dozen stacked tool cards with per-card drop shadows read as lumpy,
        // heavy chrome. The panel2 fill + hairline stroke already separate cards from the transcript.
        .quillCodeSurface(
            fill: QuillCodePalette.panel2,
            radius: QuillCodeMetrics.toolCardRadius,
            stroke: cardStrokeColor,
            shadow: false
        )
        .overlay(alignment: .leading) {
            if let executionContext = card.executionContext {
                QuillCodeExecutionRail(context: executionContext)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isDetailsOpen)
        .onChange(of: card.status) { _, status in
            let density = ToolCardState.defaultDensity(
                status: status,
                isExpanded: card.isExpanded
            )
            isDetailsOpen = density == .expanded
        }
        .onChange(of: card.density) { _, density in
            isDetailsOpen = density == .expanded
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func progressView(_ progress: ToolProgressSurface) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction)
                    .tint(QuillCodePalette.blue)
                    .accessibilityLabel(progress.message ?? "Tool progress")
                    .accessibilityValue(progress.percentLabel ?? "")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(progress.message ?? "Tool in progress")
            }
            let secondaryMessage = progress.message.flatMap { message in
                message == card.subtitle ? nil : message
            }
            if secondaryMessage != nil || progress.percentLabel != nil {
                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    if let secondaryMessage {
                        Text(secondaryMessage)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(QuillCodePalette.muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if let percent = progress.percentLabel {
                        Text(percent)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(QuillCodePalette.blue)
                    }
                }
            }
        }
        .accessibilityIdentifier("quillcode-tool-card-progress")
    }

    private var adaptivePreviewColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 220),
                spacing: QuillCodeMetrics.controlClusterSpacing
            )
        ]
    }

    private func imagePreviewSequenceLabel(index: Int) -> String? {
        let count = card.imagePreviewArtifacts.count
        guard count > 1 else { return nil }
        return "Image \(index + 1) of \(count)"
    }

    @ViewBuilder
    private var toolHeaderControl: some View {
        if hasDetails {
            Button {
                isDetailsOpen.toggle()
            } label: {
                toolHeader
            }
            .quillCodeFullRowButtonTarget(
                minHeight: QuillCodeMetrics.toolCardHeaderHeight,
                alignment: .leading,
                radius: QuillCodeMetrics.toolCardRadius
            )
            .buttonStyle(QuillCodePressableButtonStyle())
            .contentShape(Rectangle())
            .accessibilityIdentifier("quillcode-tool-card-details")
            .accessibilityLabel(detailsToggleLabel)
            .help(detailsToggleLabel)
        } else {
            toolHeader
        }
    }

    private var toolHeader: some View {
        HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
            if hasDetails {
                Image(systemName: isDetailsOpen ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(QuillCodePalette.blue)
                    .frame(width: 12)
                    .accessibilityHidden(true)
            }

            Image(systemName: toolGlyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusColor)
                .quillCodeDecorativeIconFrame(size: 30)

            Text(displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)

            if let visibleSubtitle {
                Text(visibleSubtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(QuillCodePalette.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let executionContext = card.executionContext {
                QuillCodeExecutionContextChip(context: executionContext)
            }

            Spacer(minLength: 10)

            QuillCodeToolStatusBadge(
                label: card.statusDisplayLabel,
                accessibilityLabel: card.statusAccessibilityLabel,
                tint: statusColor,
                iconName: statusBadgeIconName
            )
        }
        .frame(minHeight: QuillCodeMetrics.toolCardHeaderHeight, alignment: .center)
    }

    private var copyActionButton: some View {
        HStack {
            QuillCodeTranscriptCopyButton(
                label: copyActionLabel,
                copiedLabel: "Copied",
                isCopied: isCopied,
                action: onCopy
            )
            Spacer()
        }
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let inputJSON = card.inputJSON {
                QuillCodeCodeBlock(title: "Input", text: inputJSON)
            }
            if let outputJSON = card.outputJSON {
                QuillCodeCodeBlock(title: "Output", text: outputJSON)
            }
            if showsDetailsCopyAction {
                copyActionButton
            }
        }
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
            return card.needsReview ? QuillCodePalette.yellow : QuillCodePalette.green
        }
    }

    private var cardStrokeColor: Color {
        switch card.status {
        case .queued, .running, .done:
            return QuillCodePalette.line
        case .review:
            return card.needsReview
                ? QuillCodePalette.yellow.opacity(0.24)
                : QuillCodePalette.green.opacity(0.24)
        case .failed:
            return statusColor.opacity(0.42)
        }
    }

    private var toolGlyph: String {
        WorkspaceToolGlyphBuilder.symbolName(for: card.title)
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
            return card.needsReview ? "hand.raised.fill" : "play.circle.fill"
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

    private var showsTopLevelCopyAction: Bool {
        !showsDetailsCopyAction
    }

    private var showsDetailsCopyAction: Bool {
        card.inputJSON != nil || card.outputJSON != nil
    }

    private var hasDetails: Bool {
        card.inputJSON != nil || card.outputJSON != nil
    }

    private var displayedArtifacts: [ToolArtifactState] {
        guard let visibleSubtitle else { return card.artifacts }
        return card.artifacts.filter {
            $0.label.localizedCaseInsensitiveCompare(visibleSubtitle) != .orderedSame
        }
    }

    private var accessibilityLabel: String {
        let context = card.executionContext.map {
            ", \($0.label) \($0.detail)"
        } ?? ""
        return "\(displayTitle), \(card.statusAccessibilityLabel), \(card.densityAccessibilityLabel)\(context)"
    }

    private var displayTitle: String {
        WorkspaceToolDisplayNameBuilder.cardTitle(for: card.title)
    }

    private var visibleSubtitle: String? {
        WorkspaceToolCardSubtitleBuilder.visibleDetail(from: card.subtitle)
    }
}
