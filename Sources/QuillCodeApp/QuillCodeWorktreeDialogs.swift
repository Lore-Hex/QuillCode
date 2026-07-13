import SwiftUI

struct QuillCodeNewWorktreeTaskView: View {
    @Binding var draft: QuillCodeNewWorktreeTaskDraft
    var onCancel: () -> Void
    var onCreate: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "New Worktree Task",
            subtitle: "Start an isolated task and choose how its local environment is prepared.",
            systemImage: "plus.rectangle.on.folder",
            iconColor: QuillCodePalette.blue
        ) {
            QuillCodeLabeledTextField(
                title: "Task name",
                placeholder: "Optional",
                text: $draft.name
            )
            .focused($isNameFocused)

            VStack(alignment: .leading, spacing: 6) {
                Text("Local environment")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .textCase(.uppercase)

                environmentButton(
                    choice: .automatic,
                    title: "Automatic",
                    detail: draft.environments.automaticDetail
                )
                environmentButton(
                    choice: .none,
                    title: "No setup",
                    detail: "Create the task without running a project setup script."
                )
                ForEach(draft.environments.options) { environment in
                    environmentButton(
                        choice: .named(environment.id),
                        title: environment.title,
                        detail: environment.description
                            ?? "Run this project's \(environment.title) setup."
                    )
                }
            }
        } footer: {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                Button("Create Task", action: onCreate)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 104))
                    .quillCodeFormActionTarget(minWidth: 104)
            }
        }
        .onAppear { isNameFocused = true }
    }

    private func environmentButton(
        choice: QuillCodeWorktreeSetupChoice,
        title: String,
        detail: String
    ) -> some View {
        Button {
            draft.setupChoice = choice
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: draft.setupChoice == choice ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.setupChoice == choice ? QuillCodePalette.blue : QuillCodePalette.muted)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.text)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(draft.setupChoice == choice ? QuillCodePalette.blue.opacity(0.12) : Color.white.opacity(0.035))
            )
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeFullRowButtonTarget(radius: 8)
        .accessibilityLabel("\(title) local environment")
        .accessibilityValue(draft.setupChoice == choice ? "Selected" : "Not selected")
    }
}

struct QuillCodeWorktreeCreateBranchView: View {
    @Binding var draft: QuillCodeWorktreeCreateBranchDraft
    var onCancel: () -> Void
    var onCreate: () -> Void
    @FocusState private var isBranchFocused: Bool

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "Create Branch Here",
            subtitle: "Keep this task in its worktree as a permanent Git branch.",
            systemImage: "arrow.triangle.branch",
            iconColor: QuillCodePalette.blue
        ) {
            QuillCodeLabeledTextField(
                title: "Branch name",
                placeholder: "feature/quillcode",
                text: $draft.branch,
                footer: "After creation, this worktree owns the branch and Handoff is no longer available."
            )
            .focused($isBranchFocused)
        } footer: {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                Button("Create Branch", action: onCreate)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 112))
                    .quillCodeFormActionTarget(minWidth: 112)
                    .disabled(!draft.canCreate)
            }
        }
        .onAppear { isBranchFocused = true }
    }
}

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
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                Button("Open", action: onOpen)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    .quillCodeFormActionTarget()
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
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                Button("Create", action: onCreate)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 82))
                    .quillCodeFormActionTarget(minWidth: 82)
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
                .quillCodeSwitchRowTarget()
        } footer: {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                Button("Remove", action: onRemove)
                    .buttonStyle(QuillCodeActionButtonStyle(.destructive, minWidth: 84))
                    .quillCodeFormActionTarget(minWidth: 84)
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
            HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
                Text("Prune runs `git worktree prune --verbose` for the selected project.")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(2)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                Button("Prune", action: onPrune)
                    .buttonStyle(QuillCodeActionButtonStyle(.destructive))
                    .quillCodeFormActionTarget()
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
