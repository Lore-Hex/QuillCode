import SwiftUI
import QuillCodeCore

/// SwiftUI-facing owner of the per-thread ``TranscriptNewTurnsTracker``. Held as a `@StateObject`
/// on the transcript view so it survives across thread switches (the transcript view is not
/// `.id(threadID)`-scoped), letting a background-grown thread show its pill on return. All real
/// logic lives in the pure tracker; this only republishes changes to SwiftUI.
final class QuillCodeTranscriptNewTurnsStore: ObservableObject {
    @Published private var tracker = TranscriptNewTurnsTracker()

    func observe(threadID: UUID?, transcript: TranscriptSurface) {
        tracker.observe(threadID: threadID, transcript: transcript)
    }

    func leave(threadID: UUID?) {
        tracker.leave(threadID: threadID)
    }

    func markSeen(threadID: UUID?, transcript: TranscriptSurface) {
        tracker.markSeen(threadID: threadID, transcript: transcript)
    }

    func pill(for threadID: UUID?, transcript: TranscriptSurface) -> TranscriptNewTurnsPill? {
        tracker.pill(for: threadID, transcript: transcript)
    }
}

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

/// The floating "Jump to latest" chip shown while the reader has scrolled up during a live run, so
/// streaming does not yank them down. Tapping it re-pins to the bottom. Mirrors the New-Turns pill's
/// capsule chrome, but lives in a `.overlay(alignment: .bottom)` so it floats just above the composer
/// and never collides with the top-aligned New-Turns pill.
struct QuillCodeTranscriptJumpToLatestChip: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption.weight(.bold))
                Text("Jump to latest")
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
        .accessibilityIdentifier("quillcode-transcript-jump-to-latest")
        .accessibilityLabel("Jump to latest")
        .accessibilityHint("Scroll to the latest message")
    }
}
