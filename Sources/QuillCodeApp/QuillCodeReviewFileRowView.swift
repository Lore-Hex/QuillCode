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
        HStack(spacing: 10) {
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
            HStack(spacing: 4) {
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
        HStack(spacing: 8) {
            TextField("Add review note", text: $commentDraft)
                .textFieldStyle(.plain)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                .background(QuillCodePalette.background.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button {
                let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                onAddReviewComment(file.path, nil, nil, nil, text)
                commentDraft = ""
            } label: {
                Label("Add review note", systemImage: "plus.bubble")
                    .labelStyle(.iconOnly)
                    .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Add review note to \(file.path)")
        }
        .padding(.leading, 30)
    }
}

private struct QuillCodeReviewHunkView: View {
    var hunk: WorkspaceReviewHunkSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

    @State private var isAddingRangeComment = false
    @State private var rangeStartDraft = ""
    @State private var rangeEndDraft = ""
    @State private var rangeCommentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            rangeComposer
            lineList
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(hunk.header)
                .font(.caption.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            Text(hunk.changeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(QuillCodePalette.muted)
            Spacer()
            Button {
                prepareRangeDraftIfNeeded()
                isAddingRangeComment.toggle()
            } label: {
                Label("Add range note", systemImage: "text.bubble.badge.plus")
                    .labelStyle(.iconOnly)
                    .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .help("Add range note")
            .foregroundStyle(QuillCodePalette.blue)
            .disabled(hunk.lines.isEmpty)
            ForEach(hunk.actions) { action in
                QuillCodeReviewActionButton(action: action, path: hunk.path, onReviewAction: onReviewAction)
            }
        }
    }

    @ViewBuilder
    private var rangeComposer: some View {
        if isAddingRangeComment {
            HStack(spacing: 8) {
                TextField("From", text: $rangeStartDraft)
                    .textFieldStyle(.plain)
                    .font(.caption.monospacedDigit())
                    .frame(width: 52)
                    .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                    .padding(.horizontal, 8)
                    .background(QuillCodePalette.background.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                TextField("To", text: $rangeEndDraft)
                    .textFieldStyle(.plain)
                    .font(.caption.monospacedDigit())
                    .frame(width: 52)
                    .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                    .padding(.horizontal, 8)
                    .background(QuillCodePalette.background.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                TextField("Range note", text: $rangeCommentDraft)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                    .background(QuillCodePalette.background.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button("Add") {
                    guard let start = Int(rangeStartDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
                          let end = Int(rangeEndDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    else { return }
                    let text = rangeCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    onAddReviewComment(hunk.path, start, end, nil, text)
                    rangeCommentDraft = ""
                    isAddingRangeComment = false
                }
                .font(.caption.weight(.semibold))
                .frame(minWidth: QuillCodeMetrics.minimumHitTarget, minHeight: QuillCodeMetrics.minimumHitTarget)
                .buttonStyle(QuillCodePressableButtonStyle())
                .disabled(!canAddRangeComment)
            }
        }
    }

    @ViewBuilder
    private var lineList: some View {
        if !hunk.lines.isEmpty {
            VStack(spacing: 0) {
                ForEach(hunk.lines) { line in
                    QuillCodeReviewLineRowView(
                        line: line,
                        onAddReviewComment: onAddReviewComment
                    )
                }
            }
            .background(QuillCodePalette.background.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var canAddRangeComment: Bool {
        Int(rangeStartDraft.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && Int(rangeEndDraft.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && !rangeCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prepareRangeDraftIfNeeded() {
        guard rangeStartDraft.isEmpty || rangeEndDraft.isEmpty else { return }
        let lineNumbers = hunk.lines.compactMap(\.displayLineNumber)
        guard let first = lineNumbers.first else { return }
        rangeStartDraft = String(first)
        rangeEndDraft = String(lineNumbers.dropFirst().first ?? first)
    }
}

private struct QuillCodeReviewActionButton: View {
    var action: WorkspaceReviewActionSurface
    var path: String
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void

    var body: some View {
        Button {
            onReviewAction(action)
        } label: {
            Label(action.kind.title, systemImage: action.kind.systemImage)
                .labelStyle(.iconOnly)
                .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("\(action.kind.title) \(path)")
        .foregroundStyle(action.kind == .restore || action.kind == .restoreHunk ? QuillCodePalette.yellow : QuillCodePalette.blue)
    }
}
