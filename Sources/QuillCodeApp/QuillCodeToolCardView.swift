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
            toolHeader
            if let progress = card.progress, card.status == .running {
                progressView(progress)
            }
            if !card.actions.isEmpty {
                QuillCodeToolCardActionRow(actions: card.actions, onAction: onAction)
            }
            if showsTopLevelCopyAction {
                copyActionButton
            }
            if !card.artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Artifacts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
                        ForEach(card.imagePreviewArtifacts) { artifact in
                            QuillCodeArtifactImagePreview(artifact: artifact)
                        }
                    }
                }
            }

            if card.inputJSON != nil || card.outputJSON != nil {
                Button {
                    isDetailsOpen.toggle()
                } label: {
                    detailsToggleRow
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeFullRowButtonTarget(minHeight: QuillCodeMetrics.minimumHitTarget)
                .accessibilityIdentifier("quillcode-tool-card-details")
                .accessibilityLabel(detailsToggleLabel)
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

                if isDetailsOpen {
                    detailsContent
                        .padding(.top, 2)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                }
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

    private var toolHeader: some View {
        HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
            // Glyph = tool TYPE (terminal/read/edit/…); the circle's tint = run STATUS. So color still
            // carries status while shape carries identity, and the trailing badge keeps the status word.
            Image(systemName: toolGlyph)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(statusColor)
                .quillCodeDecorativeIconFrame()
                .background(statusColor.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                    Text(displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    if let executionContext = card.executionContext {
                        QuillCodeExecutionContextChip(context: executionContext)
                    }
                }
                // The path/command is the most scannable value on a card: render it monospaced at
                // near-primary brightness, one line, middle-truncated so a long path keeps its
                // meaningful tail (the filename) instead of wrapping or hiding it.
                Text(card.subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(QuillCodePalette.text.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 0, alignment: .leading)

            Spacer(minLength: 10)

            QuillCodeToolStatusBadge(
                label: card.statusDisplayLabel,
                accessibilityLabel: card.statusAccessibilityLabel,
                tint: statusColor,
                iconName: statusBadgeIconName
            )
        }
        .frame(minHeight: QuillCodeMetrics.toolCardHeaderHeight, alignment: .top)
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

    private var detailsToggleRow: some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Image(systemName: isDetailsOpen ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(QuillCodePalette.blue)
                .frame(width: 12)
                .accessibilityHidden(true)
            Text(detailsToggleLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.blue)
            if !isDetailsOpen, card.status == .done {
                Text("Raw tool data")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .background(QuillCodePalette.blue.opacity(isDetailsOpen ? 0.16 : 0.11))
        .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.composerControlRadius, style: .continuous))
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
        card.inputJSON != nil && card.outputJSON == nil
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
}
