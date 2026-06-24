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
