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
    @State private var isHovering = false
    @FocusState private var isBubbleFocused: Bool
    @FocusState private var focusedAction: MessageAction?
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

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
                if showsActions {
                    HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                        QuillCodeTranscriptCopyButton(
                            label: "Copy",
                            copiedLabel: "Copied",
                            isCopied: isCopied,
                            action: onCopy
                        )
                        .focused($focusedAction, equals: .copy)
                        .accessibilityIdentifier("transcript-copy-\(timelineItemID)")
                        if message.role == .user {
                            QuillCodeMessageDraftButton(action: onUseAsDraft)
                                .focused($focusedAction, equals: .draft)
                                .accessibilityIdentifier("message-use-as-draft")
                            if let revert = message.revert {
                                QuillCodeMessageRevertButton(
                                    hasNonApplyPatchEdits: revert.hasNonApplyPatchEdits,
                                    action: { onRevertTurn(revert.turnMessageID) }
                                )
                                .focused($focusedAction, equals: .revert)
                                .accessibilityIdentifier("message-revert-turn")
                            }
                        }
                        if message.role == .assistant {
                            if canRetry {
                                QuillCodeMessageRetryButton(action: onRetry)
                                    .focused($focusedAction, equals: .retry)
                                    .accessibilityIdentifier("message-retry")
                            }
                        }
                    }
                    .accessibilityIdentifier("message-actions-\(timelineItemID)")
                    .transition(.opacity)
                }
            }
            if message.role != .user {
                Spacer(minLength: 80)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .focusable()
        .focused($isBubbleFocused)
        .focusEffectDisabled()
        .contextMenu {
            messageContextMenu
        }
    }

    private var actionAlignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var showsActions: Bool {
        isHovering || isBubbleFocused || focusedAction != nil || isVoiceOverEnabled
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        Button("Copy", action: onCopy)
            .quillCodePlatformMenuItemTarget(reason: Self.contextMenuItemTargetReason)
        if message.role == .user {
            Button("Use as draft", action: onUseAsDraft)
                .quillCodePlatformMenuItemTarget(reason: Self.contextMenuItemTargetReason)
            if let revert = message.revert {
                Button(TurnRevertCopy.buttonTitle) {
                    onRevertTurn(revert.turnMessageID)
                }
                .quillCodePlatformMenuItemTarget(reason: Self.contextMenuItemTargetReason)
            }
        }
        if message.role == .assistant, canRetry {
            Button("Retry", action: onRetry)
                .quillCodePlatformMenuItemTarget(reason: Self.contextMenuItemTargetReason)
        }
    }

    private static let contextMenuItemTargetReason =
        "AppKit owns context menu row geometry; the transcript bubble carries the custom hit-target contract."

    private enum MessageAction: Hashable {
        case copy
        case draft
        case revert
        case retry
    }

    @Environment(\.quillCodeConfidentialAppearance) private var isConfidentialAppearance

    // Own messages use the Charter sage plane; assistant replies use the standard raised surface.
    private var background: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(isConfidentialAppearance
                ? QuillCodePalette.Confidential.userBubble
                : QuillCodePalette.userBubble)
            : AnyShapeStyle(isConfidentialAppearance
                ? QuillCodePalette.Confidential.panel2
                : QuillCodePalette.panel2)
    }

    private var borderColor: Color {
        message.role == .user
            ? (isConfidentialAppearance
                ? QuillCodePalette.Confidential.userBubbleBorder
                : QuillCodePalette.userBubbleBorder)
            : (isConfidentialAppearance ? QuillCodePalette.Confidential.line : QuillCodePalette.line)
    }
}
