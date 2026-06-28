import SwiftUI

struct QuillCodeReviewPaneView: View {
    var review: WorkspaceReviewSurface
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

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(QuillCodePalette.blue)
                .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
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
                    onAction: onPullRequestReviewThreadAction,
                    onReply: onPullRequestReviewThreadReply
                )
            }
        }
    }
}

private struct QuillCodePullRequestReviewDraftView: View {
    var draft: WorkspacePullRequestReviewDraftSurface
    var onChange: (WorkspacePullRequestReviewDraftSurface) -> Void
    var onCancel: () -> Void
    var onSubmit: () -> Void

    private var actionBinding: Binding<WorkspacePullRequestReviewActionKind> {
        Binding(
            get: { draft.action },
            set: { update(action: $0) }
        )
    }

    private var selectorBinding: Binding<String> {
        Binding(
            get: { draft.selector },
            set: { update(selector: $0) }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { draft.body },
            set: { update(body: $0) }
        )
    }

    private var includeInlineCommentsBinding: Binding<Bool> {
        Binding(
            get: { draft.includeInlineComments },
            set: { update(includeInlineComments: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Review action", selection: actionBinding) {
                ForEach(WorkspacePullRequestReviewActionKind.allCases, id: \.self) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.segmented)
            .quillCodeSegmentedControlTarget()
            .accessibilityLabel("Pull request review action")

            TextField("PR number, URL, or branch (optional)", text: selectorBinding)
                .textFieldStyle(.plain)
                .font(.callout.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .quillCodeTextEntryTarget(alignment: .center, radius: 10)
                .background(QuillCodePalette.background.opacity(0.64))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Pull request selector")

            TextField(draft.action.bodyPlaceholder, text: bodyBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(2...6)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .quillCodeTextEntryTarget(alignment: .topLeading, radius: 10)
                .background(QuillCodePalette.background.opacity(0.64))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Pull request review body")

            if draft.inlineCommentCount > 0 {
                Toggle(isOn: includeInlineCommentsBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(inlineCommentToggleTitle)
                            .font(.caption.weight(.semibold))
                        Text("Review the pending line notes before submitting.")
                            .font(.caption2)
                            .foregroundStyle(QuillCodePalette.muted)
                    }
                }
                .toggleStyle(.switch)
                .quillCodeSwitchRowTarget()
                .accessibilityLabel("Include inline review notes")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pending inline notes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                        .textCase(.uppercase)

                    ForEach(Array(draft.inlineComments.enumerated()), id: \.element.id) { index, comment in
                        inlineCommentRow(comment, index: index)
                    }
                }
                .padding(.horizontal, 10)
            }

            submitSummary

            HStack(spacing: 8) {
                if let submitBlockReason {
                    Text(submitBlockReason)
                        .font(.caption2)
                        .foregroundStyle(QuillCodePalette.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(submitBlockReason)
                } else {
                    Spacer()
                }
                Button("Cancel", action: onCancel)
                    .font(.caption.weight(.semibold))
                    .quillCodeFormActionTarget(minWidth: 82)
                    .foregroundStyle(QuillCodePalette.muted)
                    .background(QuillCodePalette.selection.opacity(0.45))
                    .clipShape(Capsule())
                    .buttonStyle(QuillCodePressableButtonStyle())

                Button(submitTitle, action: onSubmit)
                    .font(.caption.weight(.semibold))
                    .quillCodeFormActionTarget(minWidth: 116)
                    .foregroundStyle(draft.canSubmit ? Color.white : QuillCodePalette.muted)
                    .background(draft.canSubmit ? QuillCodePalette.blue : QuillCodePalette.selection.opacity(0.45))
                    .clipShape(Capsule())
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .disabled(!draft.canSubmit)
            }
        }
        .padding(12)
        .background(QuillCodePalette.background.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var submitSummary: some View {
        let summary = draft.submitSummary
        let tint = summary.status == .ready ? QuillCodePalette.green : QuillCodePalette.yellow
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: summary.status == .ready ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(summary.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(summary.detail)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.text)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(summary.items.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(QuillCodePalette.muted)
                            .lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.title). \(summary.detail). \(summary.items.joined(separator: ". "))")
    }

    private var submitTitle: String {
        switch draft.action {
        case .approve:
            return "Submit approval"
        case .comment:
            return "Submit comment"
        case .requestChanges:
            return "Request changes"
        }
    }

    private var submitBlockReason: String? {
        if draft.action.requiresBody && draft.normalizedBody.isEmpty {
            return "Review body is required."
        }
        if !draft.invalidSelectedInlineComments.isEmpty {
            return "Selected inline notes need text."
        }
        return nil
    }

    private var inlineCommentToggleTitle: String {
        let selectedCount = draft.selectedInlineCommentCount
        if selectedCount == draft.inlineCommentCount {
            return "Include \(draft.inlineCommentCount) inline review note\(draft.inlineCommentCount == 1 ? "" : "s")"
        }
        return "Include \(selectedCount) of \(draft.inlineCommentCount) inline review notes"
    }

    private func inlineCommentRow(
        _ comment: WorkspacePullRequestReviewDraftCommentSurface,
        index: Int
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(comment.locationLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(QuillCodePalette.blue)
                    .lineLimit(1)
                TextField("Inline review note", text: inlineCommentBodyBinding(for: comment.id), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .lineLimit(1...3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .quillCodeTextEntryTarget(minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .topLeading, radius: 8)
                    .background(QuillCodePalette.background.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Inline note text at \(comment.locationLabel)")
                if draft.includeInlineComments && comment.isIncluded && comment.normalizedBody.isEmpty {
                    Text("Add note text or skip this note.")
                        .font(.caption2)
                        .foregroundStyle(QuillCodePalette.yellow)
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 4) {
                inlineCommentMoveButton(
                    title: "Move inline note at \(comment.locationLabel) up",
                    systemImage: "chevron.up",
                    isDisabled: !draft.includeInlineComments || index == 0
                ) {
                    moveInlineComment(id: comment.id, offset: -1)
                }
                inlineCommentMoveButton(
                    title: "Move inline note at \(comment.locationLabel) down",
                    systemImage: "chevron.down",
                    isDisabled: !draft.includeInlineComments || index >= draft.inlineComments.count - 1
                ) {
                    moveInlineComment(id: comment.id, offset: 1)
                }
            }
            Button(comment.isIncluded ? "Included" : "Skipped") {
                updateInlineComment(id: comment.id, isIncluded: !comment.isIncluded)
            }
            .font(.caption.weight(.semibold))
            .quillCodeTextButtonTarget(minWidth: 82, alignment: .center)
            .foregroundStyle(comment.isIncluded ? QuillCodePalette.green : QuillCodePalette.muted)
            .background((comment.isIncluded ? QuillCodePalette.green : QuillCodePalette.selection).opacity(0.14))
            .clipShape(Capsule())
            .buttonStyle(QuillCodePressableButtonStyle())
            .disabled(!draft.includeInlineComments)
            .opacity(draft.includeInlineComments ? 1 : 0.48)
            .accessibilityLabel("\(comment.isIncluded ? "Skip" : "Include") inline note at \(comment.locationLabel)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(QuillCodePalette.selection.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func inlineCommentMoveButton(
        title: String,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .quillCodeIconButtonTarget(size: QuillCodeMetrics.minimumHitTarget)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .foregroundStyle(isDisabled ? QuillCodePalette.muted : QuillCodePalette.blue)
        .opacity(isDisabled ? 0.42 : 1)
        .disabled(isDisabled)
        .help(title)
        .accessibilityLabel(title)
    }

    private func update(
        action: WorkspacePullRequestReviewActionKind? = nil,
        selector: String? = nil,
        body: String? = nil,
        includeInlineComments: Bool? = nil
    ) {
        var next = draft
        if let action {
            next.action = action
        }
        if let selector {
            next.selector = selector
        }
        if let body {
            next.body = body
        }
        if let includeInlineComments {
            next.includeInlineComments = includeInlineComments
        }
        onChange(next)
    }

    private func updateInlineComment(id: UUID, isIncluded: Bool) {
        var next = draft
        next.setInlineComment(id: id, isIncluded: isIncluded)
        onChange(next)
    }

    private func updateInlineComment(id: UUID, body: String) {
        var next = draft
        next.updateInlineComment(id: id, body: body)
        onChange(next)
    }

    private func moveInlineComment(id: UUID, offset: Int) {
        var next = draft
        next.moveInlineComment(id: id, offset: offset)
        onChange(next)
    }

    private func inlineCommentBodyBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                draft.inlineComments.first(where: { $0.id == id })?.body ?? ""
            },
            set: { body in
                updateInlineComment(id: id, body: body)
            }
        )
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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: thread.isResolved ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(thread.isResolved ? QuillCodePalette.green : QuillCodePalette.yellow)
                    .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                    .background((thread.isResolved ? QuillCodePalette.green : QuillCodePalette.yellow).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.iconControlRadius, style: .continuous))
                    .accessibilityHidden(true)
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
        HStack(spacing: 8) {
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
        HStack(alignment: .bottom, spacing: 8) {
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
