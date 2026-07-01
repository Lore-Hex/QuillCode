import SwiftUI

struct QuillCodeReviewFileRowView: View {
    var file: WorkspaceReviewFileSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

    @State private var commentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            hunkList
            commentList
            noteComposer
        }
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: file.isBinary ? "photo" : "doc.plaintext")
                .foregroundStyle(QuillCodePalette.muted)
                .frame(width: 20)
            Text(file.path)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer()
            Text(file.changeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(QuillCodePalette.muted)
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                ForEach(file.actions) { action in
                    QuillCodeReviewActionButton(action: action, path: file.path, onReviewAction: onReviewAction)
                }
            }
        }
    }

    private var hunkList: some View {
        ForEach(file.hunkItems) { hunk in
            QuillCodeReviewHunkView(
                hunk: hunk,
                onReviewAction: onReviewAction,
                onAddReviewComment: onAddReviewComment
            )
            .padding(.leading, 30)
        }
    }

    @ViewBuilder
    private var commentList: some View {
        if !file.comments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(file.comments) { comment in
                    Label(comment.text, systemImage: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.text)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.leading, 30)
        }
    }

    private var noteComposer: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            TextField("Add review note", text: $commentDraft)
                .textFieldStyle(.plain)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .quillCodeTextEntryTarget(radius: 8)
                .background(QuillCodePalette.background.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("quillcode-review-file-note")
            Button {
                let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                onAddReviewComment(file.path, nil, nil, nil, text)
                commentDraft = ""
            } label: {
                Label("Add review note", systemImage: "plus.bubble")
                    .labelStyle(.iconOnly)
                    .quillCodeIconButtonTarget()
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Add review note to \(file.path)")
        }
        .padding(.leading, 30)
    }
}
