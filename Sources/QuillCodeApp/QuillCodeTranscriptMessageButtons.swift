import SwiftUI
import QuillCodeCore

struct QuillCodeMessageDraftButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Use as draft", systemImage: "square.and.pencil")
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .quillCodeIconButtonTarget(radius: QuillCodeMetrics.minimumHitTarget / 2)
                .foregroundStyle(Color.white.opacity(0.85))
                .background(Color.black.opacity(0.30))
                .clipShape(Capsule())
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

struct QuillCodeMessageRetryButton: View {
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
                .foregroundStyle(isCopied ? QuillCodePalette.green : Color.white.opacity(0.85))
                .background(isCopied ? QuillCodePalette.green.opacity(0.16) : Color.black.opacity(0.30))
                .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help(isCopied ? copiedLabel : label)
    }
}
