import SwiftUI
import QuillCodeCore

struct QuillCodeMessageBubble: View {
    var message: MessageSurface
    var timelineItemID: String
    var isCopied: Bool
    var onCopy: () -> Void
    var onUseAsDraft: () -> Void
    var canRetry: Bool
    var onRetry: () -> Void
    var onFeedback: (MessageFeedbackValue) -> Void
    var onRevertTurn: (UUID) -> Void = { _ in }

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            if message.role == .user {
                Spacer(minLength: 80)
            }
            VStack(alignment: actionAlignment, spacing: 6) {
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(background)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(message.accessibilityLabel)
                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    QuillCodeTranscriptCopyButton(
                        label: "Copy",
                        copiedLabel: "Copied",
                        isCopied: isCopied,
                        action: onCopy
                    )
                    .accessibilityIdentifier("transcript-copy-\(timelineItemID)")
                    if message.role == .user {
                        QuillCodeMessageDraftButton(action: onUseAsDraft)
                            .accessibilityIdentifier("message-use-as-draft")
                        if let revert = message.revert {
                            QuillCodeMessageRevertButton(
                                hasNonApplyPatchEdits: revert.hasNonApplyPatchEdits,
                                action: { onRevertTurn(revert.turnMessageID) }
                            )
                            .accessibilityIdentifier("message-revert-turn")
                        }
                    }
                    if message.role == .assistant {
                        if canRetry {
                            QuillCodeMessageRetryButton(action: onRetry)
                                .accessibilityIdentifier("message-retry")
                        }
                        QuillCodeMessageFeedbackButton(
                            label: "Helpful",
                            systemImage: "hand.thumbsup",
                            isSelected: message.feedback == .helpful,
                            action: { onFeedback(.helpful) }
                        )
                        QuillCodeMessageFeedbackButton(
                            label: "Not helpful",
                            systemImage: "hand.thumbsdown",
                            isSelected: message.feedback == .notHelpful,
                            action: { onFeedback(.notHelpful) }
                        )
                    }
                }
                .accessibilityIdentifier("message-actions-\(timelineItemID)")
            }
            if message.role != .user {
                Spacer(minLength: 80)
            }
        }
    }

    private var actionAlignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var background: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(LinearGradient(colors: [QuillCodePalette.blue, QuillCodePalette.coral], startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(QuillCodePalette.panel)
    }
}

private struct QuillCodeMessageDraftButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Use as draft", systemImage: "square.and.pencil")
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .quillCodeIconButtonTarget(radius: QuillCodeMetrics.minimumHitTarget / 2)
                .foregroundStyle(QuillCodePalette.text)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Use as draft")
    }
}

private struct QuillCodeMessageRevertButton: View {
    var hasNonApplyPatchEdits: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(TurnRevertCopy.buttonTitle, systemImage: "arrow.uturn.backward")
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .quillCodeIconButtonTarget(radius: QuillCodeMetrics.minimumHitTarget / 2)
                .foregroundStyle(QuillCodePalette.red)
                .background(QuillCodePalette.red.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help(TurnRevertCopy.buttonTitle + ". " + TurnRevertCopy.scope(hasNonApplyPatchEdits: hasNonApplyPatchEdits))
        .accessibilityLabel(TurnRevertCopy.buttonTitle)
        .accessibilityHint(TurnRevertCopy.scope(hasNonApplyPatchEdits: hasNonApplyPatchEdits))
    }
}

private struct QuillCodeMessageRetryButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Retry", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .quillCodeIconButtonTarget(radius: QuillCodeMetrics.minimumHitTarget / 2)
                .foregroundStyle(QuillCodePalette.blue)
                .background(QuillCodePalette.blue.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Retry last turn")
    }
}

private struct QuillCodeMessageFeedbackButton: View {
    var label: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .quillCodeIconButtonTarget(radius: QuillCodeMetrics.minimumHitTarget / 2)
                .foregroundStyle(isSelected ? QuillCodePalette.green : QuillCodePalette.muted)
                .background((isSelected ? QuillCodePalette.green : Color.white).opacity(isSelected ? 0.16 : 0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help(label)
    }
}

struct QuillCodeTranscriptCopyButton: View {
    var label: String
    var copiedLabel: String
    var isCopied: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isCopied ? copiedLabel : label, systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .quillCodeTextButtonTarget(minWidth: 64, radius: QuillCodeMetrics.minimumHitTarget / 2)
                .foregroundStyle(isCopied ? QuillCodePalette.green : QuillCodePalette.muted)
                .background((isCopied ? QuillCodePalette.green : Color.white).opacity(isCopied ? 0.16 : 0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help(isCopied ? copiedLabel : label)
    }
}
