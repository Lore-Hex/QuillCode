import SwiftUI
import QuillCodeCore

/// The per-thread return digest card (issue #877), shown when the user presses Enter on an Attention row.
/// A compact summary of one overnight run — the integrity verdict + reasons, the final outcome, and the
/// "unseen turns since last viewed" seam — so the user sees exactly what changed without reading the
/// whole transcript. Mirrors `WorkspaceHTMLRenderer`'s digest markup for native/harness parity.
struct QuillCodeAttentionDigestView: View {
    var digest: AttentionDigestSurface
    var onClose: () -> Void
    var onAcknowledge: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let seam = digest.unseenSeamLabel {
                unseenSeam(seam)
            }
            outcomeSection
            if !digest.reasons.isEmpty {
                reasonsSection
            }
            actions
        }
        .padding(20)
        .frame(maxWidth: 460)
        .background(QuillCodePalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quillcode-attention-digest")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
            if let badge = digest.badgeLabel, let verdict = digest.verdict {
                Text(badge)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color(for: verdict))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color(for: verdict).opacity(0.16))
                    .clipShape(Capsule())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(digest.title)
                    .font(.headline)
                    .foregroundStyle(QuillCodePalette.text)
                if !digest.verdictSummary.isEmpty {
                    Text(digest.verdictSummary)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
            }
            Spacer(minLength: 0)
            Button("Close", action: onClose)
                .font(.caption.weight(.semibold))
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget(minWidth: 56)
                .foregroundStyle(QuillCodePalette.muted)
                .accessibilityIdentifier("quillcode-attention-digest-close")
        }
    }

    private func unseenSeam(_ label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(QuillCodePalette.blue.opacity(0.5))
                .frame(height: 1)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.blue)
            Rectangle()
                .fill(QuillCodePalette.blue.opacity(0.5))
                .frame(height: 1)
        }
        .accessibilityIdentifier("quillcode-attention-digest-seam")
        .accessibilityLabel(label)
    }

    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Final outcome".uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            Text(digest.outcome)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Why".uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            ForEach(Array(digest.reasons.enumerated()), id: \.offset) { _, reason in
                Text("• \(reason)")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Button("Acknowledge", action: onAcknowledge)
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget()
                .accessibilityIdentifier("quillcode-attention-digest-acknowledge")
            Button("Dismiss", action: onDismiss)
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget()
                .foregroundStyle(QuillCodePalette.muted)
                .accessibilityIdentifier("quillcode-attention-digest-dismiss")
        }
    }

    private func color(for verdict: TriageVerdict) -> Color {
        switch verdict {
        case .red: return QuillCodePalette.red
        case .unverified: return QuillCodePalette.yellow
        case .verified: return QuillCodePalette.green
        }
    }
}
