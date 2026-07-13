import SwiftUI
import QuillCodeCore

struct QuillCodeSubagentTranscriptSheet: View {
    var surface: WorkspaceSubagentTranscriptSurface
    var onClose: () -> Void
    var onToolCardAction: (ToolCardActionSurface) -> Void
    var onCopyTranscriptItem: (String, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            context
            Divider()
            transcript
        }
        .frame(
            minWidth: 480,
            idealWidth: 760,
            maxWidth: 760,
            minHeight: 400,
            idealHeight: 640,
            maxHeight: 640
        )
        .background(QuillCodePalette.background)
        .foregroundStyle(QuillCodePalette.text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Delegated transcript for \(surface.title)")
    }

    private var header: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title3)
                .foregroundStyle(QuillCodePalette.blue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(surface.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(surface.role)
                    Text(surface.workerID)
                        .fontDesign(.monospaced)
                }
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            }

            Spacer(minLength: 16)

            statusBadge

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .quillCodeIconButtonTarget()
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .help("Close")
            .accessibilityLabel("Close delegated transcript")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(QuillCodePalette.panel)
    }

    private var statusBadge: some View {
        Text(surface.statusLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.14))
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(surface.statusLabel)")
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataSection(title: "Objective", text: surface.objective)
            if let summary = surface.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                metadataSection(title: "Summary", text: summary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(QuillCodePalette.panel.opacity(0.58))
    }

    private func metadataSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            Text(text)
                .font(.callout)
                .lineLimit(title == "Summary" ? 3 : 2)
                .textSelection(.enabled)
        }
    }

    private var transcript: some View {
        Group {
            if surface.transcript.timelineItems.isEmpty && surface.transcript.thinking == nil {
                emptyTranscript
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(surface.transcript.timelineItems) { item in
                            timelineItem(item)
                        }
                        if let thinking = surface.transcript.thinking {
                            QuillCodeThinkingView(thinking: thinking)
                                .id(thinking.id)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(18)
                }
                .defaultScrollAnchor(.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QuillCodePalette.background)
    }

    @ViewBuilder
    private func timelineItem(_ item: TranscriptTimelineItemSurface) -> some View {
        switch item.kind {
        case .message:
            if let message = item.message {
                QuillCodeSubagentMessageRow(message: message)
                    .id(item.id)
            }
        case .toolCard:
            if let card = item.toolCard {
                QuillCodeToolCardView(
                    card: card,
                    onCopy: {
                        onCopyTranscriptItem(item.id, TranscriptItemTextFormatter.text(for: card))
                    },
                    onAction: onToolCardAction
                )
                .id(item.id)
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.title2)
                .foregroundStyle(QuillCodePalette.muted)
            Text("No transcript yet")
                .font(.callout.weight(.semibold))
            Text("This worker has not recorded any turns.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch surface.status {
        case .completed:
            return QuillCodePalette.green
        case .failed, .cancelled, .interrupted:
            return QuillCodePalette.red
        case .awaitingApproval, .blocked:
            return QuillCodePalette.yellow
        case .queued:
            return QuillCodePalette.muted
        case .running:
            return QuillCodePalette.blue
        }
    }
}

private struct QuillCodeSubagentMessageRow: View {
    var message: MessageSurface

    var body: some View {
        HStack(spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 64)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !message.attachments.isEmpty {
                    QuillCodeMessageAttachmentGrid(attachments: message.attachments)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(messageBackground)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .accessibilityLabel(message.accessibilityLabel)

            if message.role != .user {
                Spacer(minLength: 64)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var messageBackground: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [QuillCodePalette.blue, QuillCodePalette.coral],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(QuillCodePalette.panel)
    }
}
