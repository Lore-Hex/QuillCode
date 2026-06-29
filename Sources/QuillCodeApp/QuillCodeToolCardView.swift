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
                        if showsDetailsCopyAction {
                            copyActionButton
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
                    .quillCodeFullRowButtonTarget(minHeight: QuillCodeMetrics.compactToolCardMinimumHeight)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var toolHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(statusColor)
                .quillCodeDecorativeIconFrame()
                .background(statusColor.opacity(0.14))
                .clipShape(Circle())

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
            return Color.white.opacity(0.09)
        case .review:
            return card.needsReview
                ? QuillCodePalette.yellow.opacity(0.24)
                : QuillCodePalette.green.opacity(0.24)
        case .failed:
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
            return card.needsReview ? "hand.raised.fill" : "play.circle.fill"
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
        return "\(card.title), \(card.statusAccessibilityLabel), \(card.densityAccessibilityLabel)\(context)"
    }
}
