import SwiftUI
import QuillCodeCore

struct QuillCodeCommandPaletteView: View {
    var commands: [WorkspaceCommandSurface]
    @Binding var query: String
    var onSelectCommand: (WorkspaceCommandSurface) -> Void
    var onClose: () -> Void

    @State private var localQuery: String
    @State private var selection = WorkspaceCommandPaletteSelection()
    @FocusState private var isSearchFocused: Bool

    init(
        commands: [WorkspaceCommandSurface],
        query: Binding<String>,
        onSelectCommand: @escaping (WorkspaceCommandSurface) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.commands = commands
        self._query = query
        self.onSelectCommand = onSelectCommand
        self.onClose = onClose
        self._localQuery = State(initialValue: query.wrappedValue)
    }

    private var results: [WorkspaceCommandSurface] {
        WorkspaceCommandPalette.rankedCommands(commands, matching: localQuery)
    }

    private var groups: [WorkspaceCommandGroupSurface] {
        WorkspaceCommandPalette.groupedCommands(commands, matching: localQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuillCodeDialogHeader(
                title: "Command palette",
                subtitle: "Run actions, or type / to insert slash commands.",
                closeTitle: "Close",
                onClose: onClose
            )

            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                TextField("Search commands, > actions, / slash", text: $localQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .accessibilityIdentifier("quillcode-command-palette-input")
                    .quillCodeTextEntryTarget()
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
                                selectedCommandID: selection.selectedCommandID,
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
            focusSearchField()
        }
        .onDisappear {
            isSearchFocused = false
        }
        .onChange(of: localQuery) { _, newValue in
            if query != newValue {
                query = newValue
            }
            ensureSelection()
        }
        .onChange(of: query) { _, newValue in
            if localQuery != newValue {
                localQuery = newValue
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                selection.move(by: -1, in: results)
            case .down:
                selection.move(by: 1, in: results)
            default:
                break
            }
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    private var activeScopeLabel: String? {
        let trimmed = localQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return "Slash"
        }
        if trimmed.hasPrefix(">") {
            return "Actions"
        }
        return nil
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
        }
    }

    private func ensureSelection() {
        selection.reconcile(with: results)
    }

    private func selectHighlightedCommand() {
        guard let command = selection.selectedCommand(in: results) else {
            return
        }
        onSelectCommand(command)
    }

    private func selectCommand(_ command: WorkspaceCommandSurface) {
        selection.select(command)
        onSelectCommand(command)
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
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Image(systemName: QuillCodeCommandIconCatalog.systemImage(for: command.id))
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
            .padding(.horizontal, QuillCodeMetrics.commandPaletteRowHorizontalPadding)
            .padding(.vertical, QuillCodeMetrics.commandPaletteRowVerticalPadding)
            .quillCodeFullRowButtonTarget(radius: QuillCodeMetrics.commandPaletteRowRadius)
            .background(isSelected ? QuillCodePalette.selection : QuillCodePalette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: QuillCodeMetrics.commandPaletteRowRadius, style: .continuous)
                    .stroke(isSelected ? QuillCodePalette.blue.opacity(0.6) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.commandPaletteRowRadius, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .disabled(!command.isEnabled)
        .help(command.keywords.last ?? command.title)
    }
}
