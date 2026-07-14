import SwiftUI

struct QuillCodeWorktreeFinishView: View {
    var draft: QuillCodeWorktreeFinishDraft
    var onCancel: () -> Void
    var onFinish: () -> Void

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: draft.title,
            subtitle: draft.subtitle,
            systemImage: "checkmark.circle",
            iconColor: QuillCodePalette.green
        ) {
            VStack(alignment: .leading, spacing: 10) {
                finishRow(
                    systemImage: "arrow.right",
                    title: draft.isCleanupOnly ? "Keep the task in Local" : "Transfer verified task state",
                    detail: draft.isCleanupOnly
                        ? "No task files move during cleanup."
                        : "Committed, staged, unstaged, and bounded local files must match in Local before cleanup."
                )
                finishRow(
                    systemImage: "checkmark.shield",
                    title: "Preserve concurrent edits",
                    detail: "The isolated checkout is removed without force. If Git finds new changes, it stays available for recovery."
                )
                finishRow(
                    systemImage: "folder",
                    title: "Continue in \(draft.destinationName)",
                    detail: "This chat and future commands use the Local checkout after completion."
                )
            }
        } footer: {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                Button(draft.isCleanupOnly ? "Retry Cleanup" : "Finish Task", action: onFinish)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 112))
                    .quillCodeFormActionTarget(minWidth: 112)
            }
        }
    }

    private func finishRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(QuillCodePalette.green)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
