import SwiftUI

struct QuillCodeReviewLineRowView: View {
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
                        .quillCodeIconButtonTarget()
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
                .quillCodeTextButtonTarget(minWidth: QuillCodeMetrics.minimumHitTarget)
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
