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

    var canOpen: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeOpenRequest {
        WorkspaceWorktreeOpenRequest(path: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct QuillCodeWorktreeRemoveDraft: Equatable {
    var path = ""
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

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "Remove Worktree",
            subtitle: "Remove an existing registered git worktree.",
            systemImage: "minus.rectangle",
            iconColor: QuillCodePalette.yellow
        ) {
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
