import SwiftUI
import QuillCodeCore

enum QuillCodeWorktreeSheet: String, Identifiable {
    case create
    case remove

    var id: String { rawValue }
}

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

struct QuillCodeCommandPaletteView: View {
    var commands: [WorkspaceCommandSurface]
    @Binding var query: String
    var onSelectCommand: (WorkspaceCommandSurface) -> Void
    var onClose: () -> Void

    @State private var selectedCommandID: String?
    @FocusState private var isSearchFocused: Bool

    private var results: [WorkspaceCommandSurface] {
        WorkspaceCommandPalette.rankedCommands(commands, matching: query)
    }

    private var groups: [WorkspaceCommandGroupSurface] {
        WorkspaceCommandPalette.groupedCommands(commands, matching: query)
    }

    private var enabledResults: [WorkspaceCommandSurface] {
        results.filter(\.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuillCodeDialogHeader(
                title: "Command palette",
                subtitle: "Run actions, or type / to insert slash commands.",
                closeTitle: "Close",
                onClose: onClose
            )

            HStack(spacing: 10) {
                TextField("Search commands, > actions, / slash", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                    .onSubmit(selectHighlightedCommand)
                if let label = activeScopeLabel {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(QuillCodePalette.selection)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }

            if results.isEmpty {
                QuillCodeDialogEmptyState(
                    systemImage: "command",
                    title: "No matching commands",
                    subtitle: "Try a command name or shortcut."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            QuillCodeCommandGroupView(
                                group: group,
                                selectedCommandID: selectedCommandID,
                                onSelectCommand: selectCommand
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(QuillCodePalette.background)
        .onAppear {
            ensureSelection()
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onDisappear {
            isSearchFocused = false
        }
        .onChange(of: query) { _, _ in
            ensureSelection()
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                moveSelection(by: -1)
            case .down:
                moveSelection(by: 1)
            default:
                break
            }
        }
    }

    private var activeScopeLabel: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return "Slash"
        }
        if trimmed.hasPrefix(">") {
            return "Actions"
        }
        return nil
    }

    private func ensureSelection() {
        if let selectedCommandID, enabledResults.contains(where: { $0.id == selectedCommandID }) {
            return
        }
        selectedCommandID = enabledResults.first?.id
    }

    private func moveSelection(by delta: Int) {
        guard !enabledResults.isEmpty else {
            selectedCommandID = nil
            return
        }
        let currentIndex = selectedCommandID.flatMap { id in
            enabledResults.firstIndex(where: { $0.id == id })
        } ?? 0
        let nextIndex = (currentIndex + delta + enabledResults.count) % enabledResults.count
        selectedCommandID = enabledResults[nextIndex].id
    }

    private func selectHighlightedCommand() {
        guard let command = enabledResults.first(where: { $0.id == selectedCommandID }) ?? enabledResults.first else {
            return
        }
        onSelectCommand(command)
    }

    private func selectCommand(_ command: WorkspaceCommandSurface) {
        selectedCommandID = command.id
        onSelectCommand(command)
    }
}

struct QuillCodeKeyboardShortcutsView: View {
    var commands: [WorkspaceCommandSurface]
    var onClose: () -> Void

    private var shortcutCommands: [WorkspaceCommandSurface] {
        commands.filter { $0.shortcut?.isEmpty == false }
    }

    private var groups: [WorkspaceCommandGroupSurface] {
        WorkspaceCommandPalette.groupedCommands(shortcutCommands, matching: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuillCodeDialogHeader(
                title: "Keyboard shortcuts",
                subtitle: "Fast paths for the workspace actions available right now.",
                closeTitle: "Close",
                onClose: onClose
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            QuillCodeDialogSectionTitle(group.title)
                            ForEach(group.commands) { command in
                                QuillCodeShortcutRow(command: command)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(QuillCodePalette.background)
    }
}

struct QuillCodeSearchView: View {
    var sidebar: SidebarSurface
    @Binding var query: String
    var onSelectThread: (UUID) -> Void
    var onClose: () -> Void

    @FocusState private var isSearchFocused: Bool

    private var results: [SidebarItemSurface] {
        sidebar.filteredItems(matching: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuillCodeDialogHeader(
                title: "Search chats",
                subtitle: "Find a thread by title, model, pinned state, archived state, or transcript text.",
                closeTitle: "Close",
                onClose: onClose
            )

            TextField("Search chats", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                .onSubmit {
                    if let firstResult = results.first {
                        onSelectThread(firstResult.id)
                    }
                }

            if results.isEmpty {
                QuillCodeDialogEmptyState(
                    systemImage: "magnifyingglass",
                    title: "No matching chats",
                    subtitle: "Try a thread title, selected model, pinned, or prior message text."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { item in
                            QuillCodeSearchResultRow(item: item, onSelect: onSelectThread)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(QuillCodePalette.background)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onDisappear {
            isSearchFocused = false
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
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}

private struct QuillCodeCommandGroupView: View {
    var group: WorkspaceCommandGroupSurface
    var selectedCommandID: String?
    var onSelectCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            QuillCodeDialogSectionTitle(group.title)
            ForEach(group.commands) { command in
                QuillCodeCommandRow(
                    command: command,
                    isSelected: command.id == selectedCommandID,
                    onSelect: onSelectCommand
                )
            }
        }
    }
}

private struct QuillCodeCommandRow: View {
    var command: WorkspaceCommandSurface
    var isSelected: Bool
    var onSelect: (WorkspaceCommandSurface) -> Void

    var body: some View {
        Button {
            onSelect(command)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: QuillCodeCommandIcon.name(for: command.id))
                    .foregroundStyle(command.isEnabled ? QuillCodePalette.blue : QuillCodePalette.muted)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(command.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if !command.keywords.isEmpty {
                        Text(command.keywords.prefix(3).joined(separator: " - "))
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(QuillCodePalette.muted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .leading)
            .background(isSelected ? QuillCodePalette.selection : QuillCodePalette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? QuillCodePalette.blue.opacity(0.6) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .disabled(!command.isEnabled)
        .help(command.keywords.last ?? command.title)
    }
}

private struct QuillCodeShortcutRow: View {
    var command: WorkspaceCommandSurface

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(command.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(command.isEnabled ? QuillCodePalette.text : QuillCodePalette.muted)
                    .lineLimit(1)
                if !command.keywords.isEmpty {
                    Text(command.keywords.prefix(3).joined(separator: " - "))
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(command.shortcut ?? "")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(QuillCodePalette.selection)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
        .background(QuillCodePalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct QuillCodeSearchResultRow: View {
    var item: SidebarItemSurface
    var onSelect: (UUID) -> Void

    var body: some View {
        Button {
            onSelect(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isPinned ? "pin.fill" : "text.bubble")
                    .foregroundStyle(item.isSelected ? QuillCodePalette.blue : QuillCodePalette.muted)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(item.subtitle + (item.isPinned ? " - pinned" : "") + (item.isArchived ? " - archived" : ""))
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                }
                Spacer()
                if item.isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(QuillCodePalette.blue)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .leading)
            .background(item.isSelected ? QuillCodePalette.selection : QuillCodePalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
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

private struct QuillCodeLabeledTextField: View {
    var title: String
    var placeholder: String
    @Binding var text: String
    var footer: String?
    var onSubmit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                .onSubmit {
                    onSubmit?()
                }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
        }
    }
}

private struct QuillCodeDialogHeader: View {
    var title: String
    var subtitle: String
    var closeTitle: String
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer()
            Button(closeTitle, action: onClose)
                .keyboardShortcut(.cancelAction)
        }
    }
}

private struct QuillCodeDialogSectionTitle: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(QuillCodePalette.muted)
            .textCase(.uppercase)
    }
}

private struct QuillCodeDialogEmptyState: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(QuillCodePalette.muted)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private enum QuillCodeCommandIcon {
    static func name(for commandID: String) -> String {
        switch commandID {
        case _ where commandID.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix):
            return "slash.circle"
        case "new-chat":
            return "square.and.pencil"
        case "search":
            return "magnifyingglass"
        case "find-in-chat":
            return "text.magnifyingglass"
        case "add-project":
            return "folder.badge.plus"
        case "project-new-chat":
            return "plus.message"
        case "project-refresh-context":
            return "arrow.clockwise"
        case "project-rename":
            return "text.cursor"
        case "project-remove":
            return "minus.circle"
        case "toggle-terminal":
            return "terminal"
        case "terminal-clear":
            return "clear"
        case "toggle-browser":
            return "globe"
        case "toggle-activity":
            return "list.bullet.rectangle"
        case "toggle-automations":
            return "clock.arrow.circlepath"
        case "toggle-memories", "memory-add":
            return "brain.head.profile"
        case "toggle-extensions":
            return "puzzlepiece.extension"
        case "git-pr-create":
            return "arrow.up.doc"
        case "git-pr-checkout":
            return "arrow.down.doc"
        case "git-pr-reviewers":
            return "person.2.badge.gearshape"
        case "git-pr-labels":
            return "tag"
        case "git-pr-merge":
            return "arrow.triangle.merge"
        case "git-worktree-list":
            return "point.3.connected.trianglepath.dotted"
        case "git-worktree-create":
            return "plus.rectangle.on.folder"
        case "git-worktree-remove":
            return "minus.rectangle"
        case "settings":
            return "gearshape"
        case "keyboard-shortcuts":
            return "keyboard"
        case "computer-use-setup":
            return "display"
        case "stop-all":
            return "stop.circle"
        default:
            if commandID.hasPrefix("local-env:") {
                return "hammer"
            }
            return "command"
        }
    }
}
