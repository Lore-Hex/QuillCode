import SwiftUI
import QuillCodeCore

enum QuillCodeWorktreeSheet: String, Identifiable {
    case create
    case open
    case remove

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

struct QuillCodeWorktreeOpenDraft: Equatable {
    var path = ""
    var choices: [WorkspaceWorktreeChoice] = []
    var isLoadingChoices = false
    var choicesError: String?
    var hasLoadedChoices = false

    var canOpen: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeOpenRequest {
        WorkspaceWorktreeOpenRequest(path: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    mutating func select(_ choice: WorkspaceWorktreeChoice) {
        path = choice.path
    }

    mutating func beginLoadingChoices() {
        choices = []
        choicesError = nil
        hasLoadedChoices = false
        isLoadingChoices = true
    }

    mutating func apply(_ result: WorkspaceWorktreeChoiceLoadResult) {
        choices = result.choices
        choicesError = result.error
        hasLoadedChoices = true
        isLoadingChoices = false
    }
}

struct QuillCodeWorktreeRemoveDraft: Equatable {
    var path = ""
    var choices: [WorkspaceWorktreeChoice] = []
    var force = false

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

struct QuillCodeWorktreeOpenView: View {
    @Binding var draft: QuillCodeWorktreeOpenDraft
    var onCancel: () -> Void
    var onOpen: () -> Void

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "Open Worktree",
            subtitle: "Open an existing registered git worktree as a focused project.",
            systemImage: "rectangle.on.rectangle",
            iconColor: QuillCodePalette.blue
        ) {
            worktreeChoicesSection

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

    @ViewBuilder
    private var worktreeChoicesSection: some View {
        if draft.isLoadingChoices {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading known worktrees...")
                    .font(.callout)
                    .foregroundStyle(QuillCodePalette.muted)
                Spacer()
            }
            .padding(12)
            .background(QuillCodePalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let choicesError = draft.choicesError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(QuillCodePalette.yellow)
                    .accessibilityHidden(true)
                Text(choicesError)
                    .font(.callout)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(12)
                .background(QuillCodePalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if !draft.choices.isEmpty {
            QuillCodeWorktreeChoiceList(
                choices: draft.choices,
                selectedPath: draft.request.path,
                iconName: "arrow.turn.down.right",
                iconColor: QuillCodePalette.blue,
                onSelect: { choice in
                    draft.select(choice)
                }
            )
        } else if draft.hasLoadedChoices {
            Text("No other registered worktrees found. Enter a registered path manually.")
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QuillCodePalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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

private struct QuillCodeWorktreeChoiceList: View {
    var choices: [WorkspaceWorktreeChoice]
    var selectedPath: String
    var iconName: String
    var iconColor: Color
    var onSelect: (WorkspaceWorktreeChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Known Worktrees")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .textCase(.uppercase)
            VStack(spacing: 6) {
                ForEach(choices) { choice in
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
        }
    }
}

struct QuillCodeWorktreeRemoveView: View {
    @Binding var draft: QuillCodeWorktreeRemoveDraft
    var onCancel: () -> Void
    var onRemove: () -> Void

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "Remove Worktree",
            subtitle: "Remove an existing registered git worktree.",
            systemImage: "minus.rectangle",
            iconColor: QuillCodePalette.yellow
        ) {
            if !draft.choices.isEmpty {
                QuillCodeWorktreeChoiceList(
                    choices: draft.choices,
                    selectedPath: draft.request.path,
                    iconName: "minus.circle",
                    iconColor: QuillCodePalette.yellow,
                    onSelect: { choice in
                        draft.select(choice)
                    }
                )
            }

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
