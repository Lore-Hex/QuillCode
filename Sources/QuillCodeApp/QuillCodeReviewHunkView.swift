import SwiftUI

struct QuillCodeReviewHunkView: View {
    var hunk: WorkspaceReviewHunkSurface
    var scope: WorkspaceReviewScope
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
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
                    .quillCodeIconButtonTarget()
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .help("Add range note")
            .foregroundStyle(QuillCodePalette.blue)
            .disabled(hunk.lines.isEmpty)
            ForEach(hunk.actions(in: scope)) { action in
                QuillCodeReviewActionButton(action: action, path: hunk.path, onReviewAction: onReviewAction)
            }
        }
    }

    @ViewBuilder
    private var rangeComposer: some View {
        if isAddingRangeComment {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                TextField("From", text: $rangeStartDraft)
                    .textFieldStyle(.plain)
                    .font(.caption.monospacedDigit())
                    .frame(width: 52)
                    .padding(.horizontal, 8)
                    .quillCodeTextEntryTarget(radius: 8)
                    .background(QuillCodePalette.background.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("quillcode-review-range-start")
                TextField("To", text: $rangeEndDraft)
                    .textFieldStyle(.plain)
                    .font(.caption.monospacedDigit())
                    .frame(width: 52)
                    .padding(.horizontal, 8)
                    .quillCodeTextEntryTarget(radius: 8)
                    .background(QuillCodePalette.background.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("quillcode-review-range-end")
                TextField("Range note", text: $rangeCommentDraft)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .quillCodeTextEntryTarget(radius: 8)
                    .background(QuillCodePalette.background.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("quillcode-review-range-note")
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
                .quillCodeFormActionTarget()
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
