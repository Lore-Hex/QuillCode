import SwiftUI
import QuillCodeCore

enum QuillCodeWorktreeSheet: String, Identifiable {
    case create
    case open
    case remove
    case prune

    var id: String { rawValue }
}

struct QuillCodeWorktreeCreateDraft: Equatable {
    var path = ""
    var branch = ""
    var base = ""

    var canCreate: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeCreateRequest {
        WorkspaceWorktreeCreateRequest(
            path: path.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
            base: base.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct QuillCodeWorktreeChoiceLoadState: Equatable {
    var choices: [WorkspaceWorktreeChoice] = []
    var isLoading = false
    var hasLoaded = false
    var errorMessage: String?

    static var loading: Self {
        Self(isLoading: true)
    }

    static func loaded(_ load: WorkspaceWorktreeChoiceLoad) -> Self {
        Self(
            choices: load.choices,
            hasLoaded: true,
            errorMessage: load.errorMessage
        )
    }
}

struct QuillCodeWorktreeOpenDraft: Equatable {
    var path = ""
    var choiceLoad = QuillCodeWorktreeChoiceLoadState()

    init(path: String = "", choiceLoad: QuillCodeWorktreeChoiceLoadState = QuillCodeWorktreeChoiceLoadState()) {
        self.path = path
        self.choiceLoad = choiceLoad
    }

    var canOpen: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeOpenRequest {
        WorkspaceWorktreeOpenRequest(path: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    mutating func select(_ choice: WorkspaceWorktreeChoice) {
        path = choice.path
    }
}

struct QuillCodeWorktreeRemoveDraft: Equatable {
    var path = ""
    var choiceLoad = QuillCodeWorktreeChoiceLoadState()
    var force = false

    init(
        path: String = "",
        choiceLoad: QuillCodeWorktreeChoiceLoadState = QuillCodeWorktreeChoiceLoadState(),
        force: Bool = false
    ) {
        self.path = path
        self.choiceLoad = choiceLoad
        self.force = force
    }

    var canRemove: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeRemoveRequest {
        WorkspaceWorktreeRemoveRequest(
            path: path.trimmingCharacters(in: .whitespacesAndNewlines),
            force: force
        )
    }

    mutating func select(_ choice: WorkspaceWorktreeChoice) {
        path = choice.path
    }
}

struct QuillCodeWorktreePrunePreviewLoadState: Equatable {
    var records: [String] = []
    var output = ""
    var isLoading = false
    var hasLoaded = false
    var errorMessage: String?

    static var loading: Self {
        Self(isLoading: true)
    }

    static func loaded(_ preview: WorkspaceWorktreePrunePreview) -> Self {
        Self(
            records: preview.records,
            output: preview.output,
            hasLoaded: true,
            errorMessage: preview.errorMessage
        )
    }
}

struct QuillCodeWorktreePruneDraft: Equatable {
    var preview = QuillCodeWorktreePrunePreviewLoadState()

    var canPrune: Bool {
        preview.hasLoaded && !preview.isLoading && preview.errorMessage == nil && !preview.records.isEmpty
    }

    var confirmRequest: WorkspaceWorktreePruneRequest {
        WorkspaceWorktreePruneRequest(dryRun: false, verbose: true)
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

private struct QuillCodeWorktreeChoiceSection: View {
    var state: QuillCodeWorktreeChoiceLoadState
    var selectedPath: String
    var iconName: String
    var iconColor: Color
    var emptyMessage: String
    var onSelect: (WorkspaceWorktreeChoice) -> Void
    var onRetry: () -> Void

    var body: some View {
        if shouldShowSection {
            content
        }
    }

    private var shouldShowSection: Bool {
        state.isLoading || state.hasLoaded || state.errorMessage != nil || !state.choices.isEmpty
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Known Worktrees")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .textCase(.uppercase)
            VStack(spacing: 6) {
                if state.isLoading {
                    QuillCodeWorktreeChoiceStatusRow(
                        systemImage: "clock.arrow.circlepath",
                        message: "Loading registered worktrees...",
                        color: QuillCodePalette.blue,
                        showsSpinner: true
                    )
                } else if let errorMessage = state.errorMessage {
                    QuillCodeWorktreeChoiceStatusRow(
                        systemImage: "exclamationmark.triangle",
                        message: "\(errorMessage) You can still paste a worktree path.",
                        color: QuillCodePalette.yellow,
                        actionTitle: "Retry",
                        action: onRetry
                    )
                } else if state.hasLoaded && state.choices.isEmpty {
                    QuillCodeWorktreeChoiceStatusRow(
                        systemImage: "rectangle.stack.badge.questionmark",
                        message: "\(emptyMessage) You can still paste a path.",
                        color: QuillCodePalette.muted
                    )
                }
                ForEach(state.choices) { choice in
                    QuillCodeWorktreeChoiceRow(
                        choice: choice,
                        selectedPath: selectedPath,
                        iconName: iconName,
                        iconColor: iconColor,
                        onSelect: onSelect
                    )
                }
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

private struct QuillCodeWorktreePruneRecordRow: View {
    var record: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(QuillCodePalette.yellow)
                .accessibilityHidden(true)
            Text(record)
                .font(.caption.monospaced())
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(QuillCodePalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(QuillCodePalette.yellow.opacity(0.25))
        )
    }
}

private struct QuillCodeWorktreeChoiceStatusRow: View {
    var systemImage: String
    var message: String
    var color: Color
    var showsSpinner = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading")
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("quillcode-worktree-choice-retry")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(QuillCodePalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08))
        )
    }
}

private struct QuillCodeWorktreeChoiceRow: View {
    var choice: WorkspaceWorktreeChoice
    var selectedPath: String
    var iconName: String
    var iconColor: Color
    var onSelect: (WorkspaceWorktreeChoice) -> Void

    var body: some View {
        Button {
            onSelect(choice)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(choice.detail)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                    Text(choice.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(QuillCodePalette.muted.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if choice.path == selectedPath {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(QuillCodePalette.green)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(choice.path == selectedPath
                        ? QuillCodePalette.blue.opacity(0.14)
                        : QuillCodePalette.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(choice.path == selectedPath
                        ? QuillCodePalette.blue.opacity(0.45)
                        : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct QuillCodeWorktreeDialogFrame<Content: View, Footer: View>: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var iconColor: Color
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }

            content
            footer
        }
        .padding(24)
        .frame(width: 520)
        .background(QuillCodePalette.background)
    }
}
