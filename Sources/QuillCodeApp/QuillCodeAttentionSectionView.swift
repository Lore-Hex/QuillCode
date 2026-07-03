import SwiftUI
import QuillCodeCore

/// The morning-triage "Attention" section rendered in the native sidebar (issue #877). Severity-ranked
/// rows (RED first) each show the run-integrity verdict badge, the thread title, and the unseen-turn
/// count. The section is keyboard-triageable with j/k/Enter/a/d; the keys dispatch the shared
/// `attention-*` commands so native and the HTML harness drive the same model. Renders nothing when the
/// section is empty.
struct QuillCodeAttentionSectionView: View {
    var attention: AttentionSectionSurface
    var onSelectThread: (UUID) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        if !attention.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Attention".uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(attention.rows) { row in
                    QuillCodeAttentionRowView(
                        row: row,
                        isCursor: row.threadID == attention.selectedThreadID,
                        onOpen: { onSelectThread(row.threadID) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Attention")
            // The five triage keys, active while the sidebar has focus. They route through the shared
            // command system so the semantics are identical to the harness.
            .onAttentionTriageKey("j") { runCommand(.attentionNext) }
            .onAttentionTriageKey("k") { runCommand(.attentionPrevious) }
            .onAttentionTriageKey("a") { runCommand(.attentionAcknowledge) }
            .onAttentionTriageKey("d") { runCommand(.attentionDismiss) }
            .onKeyPress(.return) { runCommand(.attentionOpen); return .handled }
        }
    }

    private func runCommand(_ action: WorkspaceCommandAction) {
        onCommand(WorkspaceCommandSurface(id: action.rawValue, title: action.rawValue))
    }
}

private extension View {
    /// Bind a single character to a triage command, returning `.handled` so the key does not fall
    /// through to other handlers.
    func onAttentionTriageKey(_ character: Character, action: @escaping () -> Void) -> some View {
        onKeyPress(keys: [KeyEquivalent(character)]) { _ in
            action()
            return .handled
        }
    }
}

struct QuillCodeAttentionRowView: View {
    var row: AttentionRowSurface
    var isCursor: Bool
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                verdictBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(QuillCodePalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !row.summary.isEmpty {
                        Text(row.summary)
                            .font(.caption2)
                            .foregroundStyle(QuillCodePalette.muted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                if let unseen = row.unseenLabel {
                    Text(unseen)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(QuillCodePalette.blue.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCursor ? QuillCodePalette.selection : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isCursor ? verdictColor.opacity(0.6) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeFullRowButtonTarget()
        .accessibilityIdentifier("quillcode-attention-row-\(row.threadID.uuidString)")
        .accessibilityAddTraits(isCursor ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel("\(row.badgeLabel). \(row.title).\(row.unseenLabel.map { " \($0)." } ?? "")")
    }

    private var verdictBadge: some View {
        Text(row.badgeLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(verdictColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(verdictColor.opacity(0.16))
            .clipShape(Capsule())
    }

    private var verdictColor: Color {
        switch row.verdict {
        case .red: return QuillCodePalette.red
        case .unverified: return QuillCodePalette.yellow
        case .verified: return QuillCodePalette.green
        }
    }
}
