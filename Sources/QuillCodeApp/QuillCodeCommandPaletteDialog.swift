import SwiftUI
import QuillCodeCore

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
