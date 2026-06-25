import SwiftUI

struct QuillCodeWorktreeOpenView: View {
    @Binding var draft: QuillCodeWorktreeOpenDraft
    var onCancel: () -> Void
    var onOpen: () -> Void
    var onRetryChoices: () -> Void

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "Open Worktree",
            subtitle: "Open an existing registered git worktree as a focused project.",
            systemImage: "rectangle.on.rectangle",
            iconColor: QuillCodePalette.blue
        ) {
            QuillCodeWorktreeChoiceSection(
                state: draft.choiceLoad,
                selectedPath: draft.request.path,
                iconName: "arrow.turn.down.right",
                iconColor: QuillCodePalette.blue,
                emptyMessage: "No other registered worktrees found.",
                onSelect: { choice in
                    draft.select(choice)
                },
                onRetry: onRetryChoices
            )

            QuillCodeLabeledTextField(
                title: "Worktree folder",
                placeholder: "quillcode-feature",
                text: $draft.path,
                footer: "Opening is limited to worktrees registered by git."
            )
        } footer: {
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Open", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canOpen)
            }
        }
    }
}

struct QuillCodeWorktreeCreateView: View {
    @Binding var draft: QuillCodeWorktreeCreateDraft
    var onCancel: () -> Void
    var onCreate: () -> Void

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "Create Worktree",
            subtitle: "Create a sibling git worktree for this project.",
            systemImage: "plus.rectangle.on.folder",
            iconColor: QuillCodePalette.blue
        ) {
            QuillCodeLabeledTextField(
                title: "Worktree folder",
                placeholder: "quillcode-feature",
                text: $draft.path
            )

            QuillCodeLabeledTextField(
                title: "New branch",
                placeholder: "feature/quillcode",
                text: $draft.branch
            )

            QuillCodeLabeledTextField(
                title: "Base ref",
                placeholder: "main",
                text: $draft.base,
                footer: "Leave branch or base blank to use git defaults."
            )
        } footer: {
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canCreate)
            }
        }
    }
}

struct QuillCodeWorktreeRemoveView: View {
    @Binding var draft: QuillCodeWorktreeRemoveDraft
    var onCancel: () -> Void
    var onRemove: () -> Void
    var onRetryChoices: () -> Void

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "Remove Worktree",
            subtitle: "Remove an existing registered git worktree.",
            systemImage: "minus.rectangle",
            iconColor: QuillCodePalette.yellow
        ) {
            QuillCodeWorktreeChoiceSection(
                state: draft.choiceLoad,
                selectedPath: draft.request.path,
                iconName: "minus.circle",
                iconColor: QuillCodePalette.yellow,
                emptyMessage: "No removable registered worktrees found.",
                onSelect: { choice in
                    draft.select(choice)
                },
                onRetry: onRetryChoices
            )

            QuillCodeLabeledTextField(
                title: "Worktree folder",
                placeholder: "quillcode-feature",
                text: $draft.path,
                footer: "Removal is limited to worktrees registered by git."
            )

            Toggle("Force removal", isOn: $draft.force)
                .frame(minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .leading)
        } footer: {
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Remove", action: onRemove)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canRemove)
            }
        }
    }
}

struct QuillCodeWorktreePruneView: View {
    @Binding var draft: QuillCodeWorktreePruneDraft
    var onCancel: () -> Void
    var onPrune: () -> Void
    var onRetryPreview: () -> Void

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "Review Stale Worktrees",
            subtitle: "Preview stale git worktree records before pruning them.",
            systemImage: "trash.slash",
            iconColor: QuillCodePalette.yellow
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dry Run")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .textCase(.uppercase)
                prunePreviewContent
            }
        } footer: {
            HStack(alignment: .center) {
                Text("Prune runs `git worktree prune --verbose` for the selected project.")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(2)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Prune", action: onPrune)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canPrune)
            }
        }
    }

    @ViewBuilder
    private var prunePreviewContent: some View {
        if draft.preview.isLoading {
            QuillCodeWorktreeChoiceStatusRow(
                systemImage: "clock.arrow.circlepath",
                message: "Checking stale worktree records...",
                color: QuillCodePalette.blue,
                showsSpinner: true
            )
        } else if let errorMessage = draft.preview.errorMessage {
            QuillCodeWorktreeChoiceStatusRow(
                systemImage: "exclamationmark.triangle",
                message: errorMessage,
                color: QuillCodePalette.yellow,
                actionTitle: "Retry",
                action: onRetryPreview
            )
        } else if draft.preview.hasLoaded && draft.preview.records.isEmpty {
            QuillCodeWorktreeChoiceStatusRow(
                systemImage: "checkmark.circle",
                message: "No stale worktree records found.",
                color: QuillCodePalette.green
            )
        } else {
            VStack(spacing: 6) {
                ForEach(Array(draft.preview.records.enumerated()), id: \.offset) { _, record in
                    QuillCodeWorktreePruneRecordRow(record: record)
                }
            }
        }
    }
}
