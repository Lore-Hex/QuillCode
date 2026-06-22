import SwiftUI

struct QuillCodeReviewPaneView: View {
    var review: WorkspaceReviewSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            fileList
        }
        .padding(14)
        .frame(maxWidth: 760, alignment: .leading)
        .background(QuillCodePalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QuillCodePalette.blue.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(QuillCodePalette.blue)
                .frame(width: 34, height: 34)
                .background(QuillCodePalette.blue.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(review.title)
                    .font(.headline)
                Text(review.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer()
            Text("\(review.totalHunks) hunk\(review.totalHunks == 1 ? "" : "s")")
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(QuillCodePalette.blue.opacity(0.14))
                .foregroundStyle(QuillCodePalette.blue)
                .clipShape(Capsule())
        }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(review.files) { file in
                QuillCodeReviewFileRowView(
                    file: file,
                    onReviewAction: onReviewAction,
                    onAddReviewComment: onAddReviewComment
                )
                if file.id != review.files.last?.id {
                    Divider()
                }
            }
        }
    }
}

private struct QuillCodeReviewFileRowView: View {
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

private struct QuillCodeReviewLineRowView: View {
    var line: WorkspaceReviewLineSurface
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

    @State private var isAddingComment = false
    @State private var commentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            lineContent
            commentList
            lineComposer
        }
    }

    private var lineContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.lineLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(QuillCodePalette.muted)
                .frame(width: 34, alignment: .trailing)
            Text(line.kind.marker)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(markerColor)
                .frame(width: 10, alignment: .center)
            Text(line.content.isEmpty ? " " : line.content)
                .font(.caption.monospaced())
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if line.displayLineNumber != nil {
                Button {
                    isAddingComment.toggle()
                } label: {
                    Label("Comment on line \(line.lineLabel)", systemImage: "plus.bubble")
                        .labelStyle(.iconOnly)
                        .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .help("Comment on line \(line.lineLabel)")
                .foregroundStyle(QuillCodePalette.blue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(lineBackground)
    }

    @ViewBuilder
    private var commentList: some View {
        if !line.comments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(line.comments) { comment in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(QuillCodePalette.blue)
                        if let label = comment.lineRangeLabel {
                            Text(label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(QuillCodePalette.muted)
                        }
                        Text(comment.text)
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.text)
                    }
                }
            }
            .padding(.leading, 58)
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var lineComposer: some View {
        if isAddingComment {
            HStack(spacing: 8) {
                TextField("Line note", text: $commentDraft)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                    .background(QuillCodePalette.panel.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button("Add") {
                    guard let lineNumber = line.displayLineNumber else { return }
                    let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    onAddReviewComment(line.path, lineNumber, nil, line.kind, text)
                    commentDraft = ""
                    isAddingComment = false
                }
                .font(.caption.weight(.semibold))
                .frame(minWidth: QuillCodeMetrics.minimumHitTarget, minHeight: QuillCodeMetrics.minimumHitTarget)
                .buttonStyle(QuillCodePressableButtonStyle())
                .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.leading, 58)
            .padding(.trailing, 8)
            .padding(.bottom, 6)
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .context:
            return QuillCodePalette.muted
        case .insertion:
            return .green
        case .deletion:
            return .red
        }
    }

    private var lineBackground: Color {
        switch line.kind {
        case .context:
            return .clear
        case .insertion:
            return Color.green.opacity(0.08)
        case .deletion:
            return Color.red.opacity(0.08)
        }
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
