import SwiftUI

/// A compact bar above the transcript offering the two "jump" motions of every post-run
/// investigation: **jump to last error** (most recent failed tool run) and **jump to last diff**
/// (most recent file write / patch). Each affordance is disabled — never hidden — when the
/// transcript has no such turn, so the control's presence is stable and its state is legible.
struct QuillCodeTranscriptJumpBar: View {
    var anchors: TranscriptNavigationAnchors
    var onJumpToLastError: () -> Void
    var onJumpToLastDiff: () -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            jumpButton(
                title: "Last error",
                systemImage: "exclamationmark.triangle",
                tint: QuillCodePalette.red,
                isEnabled: anchors.hasError,
                identifier: "quillcode-transcript-jump-last-error",
                action: onJumpToLastError
            )
            jumpButton(
                title: "Last diff",
                systemImage: "plusminus",
                tint: QuillCodePalette.green,
                isEnabled: anchors.hasDiff,
                identifier: "quillcode-transcript-jump-last-diff",
                action: onJumpToLastDiff
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(QuillCodePalette.panel.opacity(0.55))
    }

    private func jumpButton(
        title: String,
        systemImage: String,
        tint: Color,
        isEnabled: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isEnabled ? tint : QuillCodePalette.muted)
            .quillCodeCapsuleButtonTarget(minWidth: 96, alignment: .center)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("Jump to \(title.lowercased())")
        .help(isEnabled ? "Jump to \(title.lowercased())" : "No \(title.lowercased()) in this chat")
    }
}

/// The floating "N new turns" pill shown on return to a thread that grew while away. Tapping it
/// scrolls to the first unseen item.
struct QuillCodeTranscriptNewTurnsPill: View {
    var pill: TranscriptNewTurnsPill
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption.weight(.bold))
                Text(pill.label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(QuillCodePalette.blue)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.25), radius: 8, y: 3)
            .quillCodeCapsuleButtonTarget(minWidth: 120, alignment: .center)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .accessibilityIdentifier("quillcode-transcript-new-turns-pill")
        .accessibilityLabel(pill.label)
        .accessibilityHint("Scroll to the first new message")
    }
}
