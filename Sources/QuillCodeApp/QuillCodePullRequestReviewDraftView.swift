import SwiftUI

struct QuillCodePullRequestReviewDraftView: View {
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
                .accessibilityIdentifier("quillcode-pr-review-selector")

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
                .accessibilityIdentifier("quillcode-pr-review-body")

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

            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
        return HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
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
        HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
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
                    .quillCodeTextEntryTarget(
                        minHeight: QuillCodeMetrics.minimumHitTarget,
                        alignment: .topLeading,
                        radius: 8
                    )
                    .background(QuillCodePalette.background.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Inline note text at \(comment.locationLabel)")
                    .accessibilityIdentifier("quillcode-pr-review-inline-note")
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
