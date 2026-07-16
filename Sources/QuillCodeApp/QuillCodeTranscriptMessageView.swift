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
    var onRevertTurn: (UUID) -> Void = { _ in }

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            if message.role == .user {
                Spacer(minLength: 80)
            }
            VStack(alignment: actionAlignment, spacing: 6) {
                VStack(alignment: .leading, spacing: 8) {
                    if !message.attachments.isEmpty {
                        QuillCodeMessageAttachmentGrid(attachments: message.attachments)
                    }
                    if !message.text.isEmpty {
                        // Assistant replies render their markdown (bold, `code`, fenced blocks) the way
                        // Codex/Claude Code do; the user's own words stay verbatim.
                        if message.role == .assistant {
                            QuillCodeMessageMarkdownView(text: message.text)
                        } else {
                            Text(message.text)
                                .font(.body)
                                .lineSpacing(6)
                                .textSelection(.enabled)
                        }
                    }
                }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: QuillCodeMetrics.messageBubbleRadius, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.messageBubbleRadius, style: .continuous))
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

    // Own message: a calm, on-brand accent-tinted bubble (not the old blue→coral gradient) so "mine vs
    // the agent's" reads at a glance without shouting; agent replies sit on a clean elevated surface.
    // Mirrors .message.user / .message.assistant in E2E/harness/index.html.
    private var background: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(QuillCodePalette.userBubble)
            : AnyShapeStyle(QuillCodePalette.panel2)
    }

    private var borderColor: Color {
        message.role == .user
            ? QuillCodePalette.userBubbleBorder
            : QuillCodePalette.line
    }
}
