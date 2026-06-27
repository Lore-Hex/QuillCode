import SwiftUI

struct QuillCodeReviewPaneView: View {
    var review: WorkspaceReviewSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onPullRequestReviewThreadAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !review.files.isEmpty {
                fileList
            }
            if !review.files.isEmpty && !review.pullRequestThreads.isEmpty {
                Divider()
            }
            if !review.pullRequestThreads.isEmpty {
                pullRequestThreadList
            }
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
            Text(review.badgeLabel)
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

    private var pullRequestThreadList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pull request review threads")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .textCase(.uppercase)
            ForEach(review.pullRequestThreads) { thread in
                QuillCodePullRequestReviewThreadRowView(
                    thread: thread,
                    onAction: onPullRequestReviewThreadAction
                )
            }
        }
    }
}

private struct QuillCodePullRequestReviewThreadRowView: View {
    var thread: WorkspacePullRequestReviewThreadSurface
    var onAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: thread.isResolved ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(thread.isResolved ? QuillCodePalette.green : QuillCodePalette.yellow)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(thread.statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(thread.isResolved ? QuillCodePalette.green : QuillCodePalette.yellow)
                    Text(thread.locationLabel)
                        .font(.caption.monospaced())
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                }
                Text(thread.summaryText)
                    .font(.callout)
                    .lineLimit(2)
                if let author = thread.authorLabel {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
            }
            Spacer(minLength: 12)
            ForEach(thread.actions) { action in
                Button {
                    onAction(action)
                } label: {
                    Label(action.kind.title, systemImage: action.kind.systemImage)
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 92, minHeight: 40)
                        .background(QuillCodePalette.blue.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .foregroundStyle(QuillCodePalette.blue)
                .help("\(action.kind.title) review thread \(thread.id)")
            }
        }
        .padding(10)
        .background(QuillCodePalette.background.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
