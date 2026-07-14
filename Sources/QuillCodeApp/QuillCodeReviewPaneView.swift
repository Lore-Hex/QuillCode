import SwiftUI

struct QuillCodeReviewPaneView: View {
    var review: WorkspaceReviewSurface
    var onReviewScopeChange: (WorkspaceReviewSelection) -> Void
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onPullRequestReviewThreadAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void
    var onPullRequestReviewThreadReply: (WorkspacePullRequestReviewThreadReplyRequest) -> Void
    var onPullRequestReviewDraftChange: (WorkspacePullRequestReviewDraftSurface) -> Void
    var onCancelPullRequestReviewDraft: () -> Void
    var onSubmitPullRequestReviewDraft: () -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !review.availableScopes.isEmpty {
                scopePicker
            }
            if let notice = review.scopeNotice {
                scopeNotice(notice)
            }
            if !review.wholeDiffActions.isEmpty {
                wholeDiffActions
            }
            if let draft = review.pullRequestReviewDraft {
                QuillCodePullRequestReviewDraftView(
                    draft: draft,
                    onChange: onPullRequestReviewDraftChange,
                    onCancel: onCancelPullRequestReviewDraft,
                    onSubmit: onSubmitPullRequestReviewDraft
                )
            }
            if review.pullRequestReviewDraft != nil && (!review.files.isEmpty || !review.pullRequestThreads.isEmpty) {
                Divider()
            }
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

    private var scopePicker: some View {
        QuillCodeReviewScopePicker(
            availableScopes: review.availableScopes,
            activeSelection: review.activeSelection,
            onSelection: onReviewScopeChange
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(QuillCodePalette.blue)
                .quillCodeDecorativeIconFrame()
                .background(QuillCodePalette.blue.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.iconControlRadius, style: .continuous))
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

    private var wholeDiffActions: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Spacer()
            ForEach(review.wholeDiffActions) { action in
                Button {
                    onReviewAction(action)
                } label: {
                    Label(action.kind.title, systemImage: action.kind.systemImage)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .quillCodeCapsuleButtonTarget(minWidth: 92)
                        .background(actionBackground(for: action))
                        .clipShape(Capsule())
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .foregroundStyle(actionForeground(for: action))
                .help("\(action.kind.title) in the visible diff")
                .accessibilityIdentifier("quillcode-review-\(action.kind.rawValue)")
            }
        }
    }

    private func scopeNotice(_ notice: String) -> some View {
        Label(notice, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(QuillCodePalette.yellow)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(QuillCodePalette.yellow.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func actionForeground(for action: WorkspaceReviewActionSurface) -> Color {
        action.kind == .restoreAll || action.kind == .revertTurn
            ? QuillCodePalette.yellow
            : QuillCodePalette.blue
    }

    private func actionBackground(for action: WorkspaceReviewActionSurface) -> Color {
        actionForeground(for: action).opacity(0.14)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(review.files) { file in
                QuillCodeReviewFileRowView(
                    file: file,
                    scope: review.activeScope ?? .unstaged,
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
                    onAction: onPullRequestReviewThreadAction,
                    onReply: onPullRequestReviewThreadReply
                )
            }
        }
    }
}

private struct QuillCodePullRequestReviewThreadRowView: View {
    var thread: WorkspacePullRequestReviewThreadSurface
    var onAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void
    var onReply: (WorkspacePullRequestReviewThreadReplyRequest) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isReplyFocused: Bool
    @State private var isReplyExpanded = false
    @State private var replyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
                Image(systemName: thread.isResolved ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(thread.isResolved ? QuillCodePalette.green : QuillCodePalette.yellow)
                    .quillCodeDecorativeIconFrame()
                    .background((thread.isResolved ? QuillCodePalette.green : QuillCodePalette.yellow).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.iconControlRadius, style: .continuous))
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
                threadActions
            }
            if isReplyExpanded, thread.replyTarget != nil {
                replyForm
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(QuillCodePalette.background.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isReplyExpanded)
    }

    private var threadActions: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            if let replyTarget = thread.replyTarget {
                Button {
                    isReplyExpanded.toggle()
                    if isReplyExpanded {
                        focusReplyField()
                    }
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                        .quillCodeCapsuleButtonTarget(minWidth: 86)
                        .background(replyButtonBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .foregroundStyle(QuillCodePalette.blue)
                .help("Reply to review comment \(replyTarget.commentID)")
            }
            ForEach(thread.actions) { action in
                Button {
                    onAction(action)
                } label: {
                    Label(action.kind.title, systemImage: action.kind.systemImage)
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                        .quillCodeCapsuleButtonTarget(minWidth: 96)
                        .background(QuillCodePalette.blue.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .foregroundStyle(QuillCodePalette.blue)
                .help("\(action.kind.title) review thread \(thread.id)")
            }
        }
    }

    private var replyButtonBackground: Color {
        isReplyExpanded
            ? QuillCodePalette.blue.opacity(0.20)
            : QuillCodePalette.blue.opacity(0.12)
    }

    private var replyForm: some View {
        HStack(alignment: .bottom, spacing: QuillCodeMetrics.controlClusterSpacing) {
            TextField("Reply to review thread", text: $replyDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...4)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .quillCodeTextEntryTarget(alignment: .center, radius: 10)
                .background(QuillCodePalette.panel.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($isReplyFocused)
                .onSubmit(submitReply)
                .accessibilityLabel("Review thread reply")
                .accessibilityIdentifier("quillcode-review-thread-reply")

            Button("Cancel", action: cancelReply)
                .font(.caption.weight(.semibold))
                .quillCodeFormActionTarget(minWidth: 74)
                .foregroundStyle(QuillCodePalette.muted)
                .background(QuillCodePalette.selection.opacity(0.45))
                .clipShape(Capsule())
                .buttonStyle(QuillCodePressableButtonStyle())

            Button("Post reply", action: submitReply)
                .font(.caption.weight(.semibold))
                .quillCodeFormActionTarget(minWidth: 92)
                .foregroundStyle(replyCanSubmit ? Color.white : QuillCodePalette.muted)
                .background(replyCanSubmit ? QuillCodePalette.blue : QuillCodePalette.selection.opacity(0.45))
                .clipShape(Capsule())
                .buttonStyle(QuillCodePressableButtonStyle())
                .disabled(!replyCanSubmit)
        }
        .padding(8)
        .background(QuillCodePalette.panel.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var replyCanSubmit: Bool {
        !replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func focusReplyField() {
        DispatchQueue.main.async {
            isReplyFocused = true
        }
    }

    private func cancelReply() {
        isReplyExpanded = false
        replyDraft = ""
        isReplyFocused = false
    }

    private func submitReply() {
        guard let request = thread.replyRequest(body: replyDraft) else { return }
        onReply(request)
        cancelReply()
    }
}
