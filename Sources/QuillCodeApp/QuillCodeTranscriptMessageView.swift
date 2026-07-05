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
            ? AnyShapeStyle(userBubbleGradient)
            : AnyShapeStyle(QuillCodePalette.panel)
    }

    private var userBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [QuillCodePalette.blue, QuillCodePalette.coral],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
