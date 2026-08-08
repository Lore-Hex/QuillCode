import SwiftUI
import QuillCodeCore

struct QuillCodeKeyboardShortcutsView: View {
    var commands: [WorkspaceCommandSurface]
    var onSave: (KeyboardShortcutPreferences) -> Void
    var onClose: () -> Void

    @State private var editor: WorkspaceShortcutEditor
    @State private var query = ""
    @State private var searchMode = WorkspaceShortcutSearchMode.action
    @State private var editingCommandID: String?
    @State private var validationMessage: String?
    @FocusState private var isSearchFocused: Bool

    init(
        commands: [WorkspaceCommandSurface],
        preferences: KeyboardShortcutPreferences,
        onSave: @escaping (KeyboardShortcutPreferences) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.commands = commands
        self.onSave = onSave
        self.onClose = onClose
        self._editor = State(initialValue: WorkspaceShortcutEditor(preferences: preferences))
    }

    private var groups: [WorkspaceCommandGroupSurface] {
        editor.groups(commands: commands, query: query, mode: searchMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuillCodeDialogHeader(
                title: "Keyboard shortcuts",
                subtitle: "Search commands or click a shortcut to change it.",
                closeTitle: "Close",
                onClose: onClose
            )

            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Picker("Search by", selection: $searchMode) {
                    ForEach(WorkspaceShortcutSearchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .quillCodeSegmentedControlTarget()
                .labelsHidden()
                .frame(width: 190)
                .accessibilityIdentifier("quillcode-shortcuts-search-mode")

                TextField(searchPlaceholder, text: $query)
                    .textFieldStyle(QuillCodeTextFieldStyle())
                    .focused($isSearchFocused)
                    .accessibilityIdentifier("quillcode-shortcuts-search-input")
                    .quillCodeTextEntryTarget()
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(QuillCodePalette.yellow.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("quillcode-shortcuts-validation")
            }

            if groups.isEmpty {
                QuillCodeDialogEmptyState(
                    systemImage: "keyboard",
                    title: "No matching shortcuts",
                    subtitle: "Try an action name, shortcut, or category."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                QuillCodeDialogSectionTitle(group.title)
                                ForEach(group.commands) { command in
                                    QuillCodeShortcutRow(
                                        command: command,
                                        shortcut: editor.shortcut(for: command.id),
                                        isEditing: editingCommandID == command.id,
                                        isCustomized: editor.isCustomized(command.id),
                                        onEdit: { beginEditing(command.id) },
                                        onReset: { reset(command.id) }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Button("Reset all") {
                    editor.resetAll()
                    validationMessage = nil
                    editingCommandID = nil
                    onSave(editor.preferences)
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .foregroundStyle(editor.hasOverrides ? QuillCodePalette.text : QuillCodePalette.muted)
                .disabled(!editor.hasOverrides)
                .quillCodeTextButtonTarget()

                Spacer()

                Button("Done", action: onClose)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    .quillCodeTextButtonTarget()
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("quillcode-shortcuts-done-button")
            }
        }
        .padding(18)
        .frame(width: 620, height: 560)
        .background(QuillCodePalette.background)
        .onAppear {
            focusSearchField()
        }
        .onChange(of: searchMode) { _, _ in
            query = ""
            validationMessage = nil
            focusSearchField()
        }
        .onKeyPress(phases: .down, action: handleKeyPress)
        .onDisappear {
            isSearchFocused = false
        }
    }

    private var searchPlaceholder: String {
        searchMode == .action ? "Search commands" : "Type or press a shortcut"
    }

    private func beginEditing(_ commandID: String) {
        editingCommandID = commandID
        validationMessage = nil
        isSearchFocused = false
    }

    private func reset(_ commandID: String) {
        editor.reset(commandID: commandID)
        validationMessage = nil
        editingCommandID = nil
        onSave(editor.preferences)
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            if editingCommandID != nil {
                editingCommandID = nil
                validationMessage = nil
                focusSearchField()
            } else {
                onClose()
            }
            return .handled
        }

        if let commandID = editingCommandID {
            if press.key == .delete, press.modifiers.isEmpty {
                reset(commandID)
                return .handled
            }
            guard let shortcut = WorkspaceShortcut(commandID: commandID, keyPress: press) else {
                return .handled
            }
            switch editor.assign(shortcut) {
            case .assigned:
                editingCommandID = nil
                validationMessage = nil
                onSave(editor.preferences)
                focusSearchField()
            case .conflict(let commandIDs):
                let titles = commandIDs.map(commandTitle).joined(separator: ", ")
                validationMessage = "\(shortcut.displayLabel) is already used by \(titles)."
            case .invalid(let reason):
                validationMessage = reason
            }
            return .handled
        }

        if searchMode == .keystroke,
           !press.modifiers.intersection([.command, .control, .option]).isEmpty,
           let shortcut = WorkspaceShortcut(commandID: "search", keyPress: press) {
            query = shortcut.displayLabel
            return .handled
        }
        return .ignored
    }

    private func commandTitle(_ commandID: String) -> String {
        commands.first { $0.id == commandID }?.title ?? commandID
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
        }
    }
}

private struct QuillCodeShortcutRow: View {
    var command: WorkspaceCommandSurface
    var shortcut: WorkspaceShortcut?
    var isEditing: Bool
    var isCustomized: Bool
    var onEdit: () -> Void
    var onReset: () -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
            if isCustomized {
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .quillCodeIconButtonTarget()
                }
                .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
                .foregroundStyle(QuillCodePalette.muted)
                .help("Reset \(command.title)")
                .accessibilityLabel("Reset \(command.title)")
                .accessibilityIdentifier("quillcode-shortcut-reset-\(command.id)")
            }
            Button(action: onEdit) {
                Text(isEditing ? "Press shortcut…" : shortcut?.displayLabel ?? "Unassigned")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isEditing ? QuillCodePalette.blue : QuillCodePalette.text)
                    .padding(.horizontal, 9)
                    .quillCodeTextButtonTarget(minWidth: 104)
                    .background(isEditing ? QuillCodePalette.blue.opacity(0.14) : QuillCodePalette.selection)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isEditing ? QuillCodePalette.blue.opacity(0.65) : Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
            .accessibilityLabel("Change shortcut for \(command.title)")
            .accessibilityIdentifier("quillcode-shortcut-edit-\(command.id)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
        .background(QuillCodePalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private extension WorkspaceShortcut {
    init?(commandID: String, keyPress: KeyPress) {
        let key: String
        switch keyPress.key {
        case .escape:
            key = "escape"
        case .tab:
            key = "tab"
        case .leftArrow:
            key = "arrowLeft"
        case .rightArrow:
            key = "arrowRight"
        case .upArrow:
            key = "arrowUp"
        case .downArrow:
            key = "arrowDown"
        case .return, .delete, .deleteForward, .home, .end, .pageUp, .pageDown, .clear, .space:
            return nil
        default:
            let characters = keyPress.characters.trimmingCharacters(in: .whitespacesAndNewlines)
            let character = characters.count == 1 ? characters : String(keyPress.key.character)
            guard character.count == 1 else { return nil }
            key = character.lowercased()
        }

        var modifiers: [KeyboardShortcutModifier] = []
        if keyPress.modifiers.contains(.command) { modifiers.append(.command) }
        if keyPress.modifiers.contains(.control) { modifiers.append(.control) }
        if keyPress.modifiers.contains(.option) { modifiers.append(.option) }
        if keyPress.modifiers.contains(.shift) { modifiers.append(.shift) }
        self.init(commandID: commandID, key: key, modifiers: modifiers)
    }
}
