import SwiftUI
import QuillCodeCore

struct QuillCodeThreadRenameDraft: Identifiable, Hashable {
    var threadID: UUID
    var title: String

    var id: UUID { threadID }
}

struct QuillCodeProjectRenameDraft: Identifiable, Hashable {
    var projectID: UUID
    var name: String

    var id: UUID { projectID }
}

struct QuillCodeSidebarSavedSearchDraft: Identifiable, Hashable {
    let id = UUID()
    var title = ""
    var query = ""
}

struct QuillCodeSidebarSavedSearchView: View {
    var draft: QuillCodeSidebarSavedSearchDraft
    var onCancel: () -> Void
    var onSave: (String, String) -> Void

    @State private var title: String
    @State private var query: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case query
    }

    init(
        draft: QuillCodeSidebarSavedSearchDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String) -> Void
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        self._title = State(initialValue: draft.title)
        self._query = State(initialValue: draft.query)
    }

    private var canSave: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuillCodeDialogHeader(
                title: "Save Sidebar Search",
                subtitle: "Create a reusable sidebar filter for chats matching this query.",
                closeTitle: "Cancel",
                onClose: onCancel
            )

            QuillCodeLabeledTextField(
                title: "Query",
                placeholder: "error failed openclaw",
                text: $query,
                footer: "Matches chat titles, subtitles, and message text.",
                onSubmit: saveIfPossible
            )
            .focused($focusedField, equals: .query)
            .accessibilityIdentifier("quillcode-sidebar-saved-search-query")

            QuillCodeLabeledTextField(
                title: "Name",
                placeholder: "Defaults to the query",
                text: $title,
                footer: "Shown in the sidebar chip.",
                onSubmit: saveIfPossible
            )
            .accessibilityIdentifier("quillcode-sidebar-saved-search-title")

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .quillCodeTextButtonTarget()
                Button("Save", action: saveIfPossible)
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .quillCodeTextButtonTarget()
                    .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear {
            focusedField = .query
        }
    }

    private func saveIfPossible() {
        guard canSave else { return }
        onSave(title, query)
    }
}

struct QuillCodeThreadRenameView: View {
    var draft: QuillCodeThreadRenameDraft
    var onCancel: () -> Void
    var onSave: (UUID, String) -> Void

    @State private var title: String

    init(
        draft: QuillCodeThreadRenameDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (UUID, String) -> Void
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        self._title = State(initialValue: draft.title)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        QuillCodeRenameDialog(
            title: "Rename Chat",
            fieldTitle: "Chat title",
            fieldPlaceholder: "Chat title",
            value: $title,
            canSave: canSave,
            onCancel: onCancel,
            onSave: {
                onSave(draft.threadID, title)
            }
        )
    }
}

struct QuillCodeProjectRenameView: View {
    var draft: QuillCodeProjectRenameDraft
    var onCancel: () -> Void
    var onSave: (UUID, String) -> Void

    @State private var name: String

    init(
        draft: QuillCodeProjectRenameDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (UUID, String) -> Void
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        self._name = State(initialValue: draft.name)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        QuillCodeRenameDialog(
            title: "Rename Project",
            fieldTitle: "Project name",
            fieldPlaceholder: "Project name",
            value: $name,
            canSave: canSave,
            onCancel: onCancel,
            onSave: {
                onSave(draft.projectID, name)
            }
        )
    }
}

private struct QuillCodeRenameDialog: View {
    var title: String
    var fieldTitle: String
    var fieldPlaceholder: String
    @Binding var value: String
    var canSave: Bool
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            QuillCodeLabeledTextField(
                title: fieldTitle,
                placeholder: fieldPlaceholder,
                text: $value,
                onSubmit: {
                    if canSave {
                        onSave()
                    }
                }
            )

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .quillCodeTextButtonTarget()
                Button("Save", action: onSave)
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .quillCodeTextButtonTarget()
                    .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}
