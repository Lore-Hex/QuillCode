import SwiftUI
import QuillCodeCore

struct QuillCodeMessageDraftButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Use as draft", systemImage: "square.and.pencil")
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .quillCodeIconButtonTarget()
                .foregroundStyle(QuillCodePalette.body)
                .background(QuillCodePalette.panel)
                .overlay { transcriptButtonBorder(QuillCodePalette.lineStrong) }
                .clipShape(transcriptButtonShape)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Use as draft")
    }
}

struct QuillCodeMessageRevertButton: View {
    var hasNonApplyPatchEdits: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(TurnRevertCopy.buttonTitle, systemImage: "arrow.uturn.backward")
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .quillCodeIconButtonTarget()
                .foregroundStyle(QuillCodePalette.red)
                .background(QuillCodePalette.red.opacity(0.10))
                .overlay { transcriptButtonBorder(QuillCodePalette.red.opacity(0.45)) }
                .clipShape(transcriptButtonShape)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help(TurnRevertCopy.buttonTitle + ". " + TurnRevertCopy.scope(hasNonApplyPatchEdits: hasNonApplyPatchEdits))
        .accessibilityLabel(TurnRevertCopy.buttonTitle)
        .accessibilityHint(TurnRevertCopy.scope(hasNonApplyPatchEdits: hasNonApplyPatchEdits))
    }
}

struct QuillCodeMessageRetryButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Retry", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .quillCodeIconButtonTarget()
                .foregroundStyle(QuillCodePalette.blue)
                .background(QuillCodePalette.blue.opacity(0.08))
                .overlay { transcriptButtonBorder(QuillCodePalette.blue.opacity(0.40)) }
                .clipShape(transcriptButtonShape)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Retry last turn")
    }
}

struct QuillCodeTranscriptCopyButton: View {
    var label: String
    var copiedLabel: String
    var isCopied: Bool
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Label(isCopied ? copiedLabel : label, systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .contentTransition(.symbolEffect(.replace))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .quillCodeTextButtonTarget(minWidth: 64)
                .foregroundStyle(isCopied ? QuillCodePalette.green : QuillCodePalette.body)
                .background(isCopied ? QuillCodePalette.green.opacity(0.08) : QuillCodePalette.panel)
                .overlay {
                    transcriptButtonBorder(
                        isCopied ? QuillCodePalette.green.opacity(0.40) : QuillCodePalette.lineStrong
                    )
                }
                .clipShape(transcriptButtonShape)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isCopied)
        .help(isCopied ? copiedLabel : label)
    }
}

private var transcriptButtonShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
}

private func transcriptButtonBorder(_ color: Color) -> some View {
    transcriptButtonShape.stroke(color, lineWidth: 1)
}
