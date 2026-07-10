import SwiftUI
import QuillCodeCore

struct QuillCodeKeyboardShortcutsView: View {
    var commands: [WorkspaceCommandSurface]
    var onClose: () -> Void

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var shortcutCommands: [WorkspaceCommandSurface] {
        commands.filter { $0.shortcut?.isEmpty == false }
    }

    private var groups: [WorkspaceCommandGroupSurface] {
        WorkspaceCommandPalette.groupedActionCommands(shortcutCommands, matching: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuillCodeDialogHeader(
                title: "Keyboard shortcuts",
                subtitle: "Fast paths for the workspace actions available right now.",
                closeTitle: "Close",
                onClose: onClose
            )

            TextField("Search shortcuts", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .accessibilityIdentifier("quillcode-shortcuts-search-input")
                .quillCodeTextEntryTarget()

            if groups.isEmpty {
                QuillCodeDialogEmptyState(
                    systemImage: "keyboard",
                    title: "No matching shortcuts",
                    subtitle: "Try an action name, shortcut, or category."
                )
            } else {
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
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(QuillCodePalette.background)
        .onAppear {
            focusSearchField()
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onDisappear {
            isSearchFocused = false
        }
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

struct QuillCodeSearchView: View {
    var sidebar: SidebarSurface
    @Binding var query: String
    var onSelectThread: (UUID) -> Void
    var onClose: () -> Void

    @State private var localQuery: String
    @State private var selection = WorkspaceSearchSelection()
    @FocusState private var isSearchFocused: Bool

    init(
        sidebar: SidebarSurface,
        query: Binding<String>,
        onSelectThread: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.sidebar = sidebar
        self._query = query
        self.onSelectThread = onSelectThread
        self.onClose = onClose
        self._localQuery = State(initialValue: query.wrappedValue)
    }

    private var results: [SidebarItemSurface] {
        sidebar.filteredItems(matching: localQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuillCodeDialogHeader(
                title: "Search chats",
                subtitle: "Find a thread by title, model, pinned state, archived state, or transcript text.",
                closeTitle: "Close",
                onClose: onClose
            )

            TextField("Search chats", text: $localQuery)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .accessibilityIdentifier("quillcode-search-input")
                .quillCodeTextEntryTarget()
                .onSubmit {
                    selectHighlightedResult()
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
                            QuillCodeSearchResultRow(
                                item: item,
                                isHighlighted: selection.highlightedThreadID == item.id,
                                onSelect: selectResult
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
            selection.reconcile(with: results, preferredID: sidebar.selectedThreadID)
            focusSearchField()
        }
        .onChange(of: localQuery) { _, newValue in
            if query != newValue {
                query = newValue
            }
            selection.reconcile(with: results)
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
        .onDisappear {
            isSearchFocused = false
            selection = WorkspaceSearchSelection()
        }
    }

    private func selectHighlightedResult() {
        guard let highlighted = selection.selectedItem(in: results) else { return }
        onSelectThread(highlighted.id)
    }

    private func selectResult(_ id: UUID) {
        guard let item = results.first(where: { $0.id == id }) else { return }
        selection.select(item)
        onSelectThread(id)
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
    var isHighlighted: Bool
    var onSelect: (UUID) -> Void

    var body: some View {
        Button {
            onSelect(item.id)
        } label: {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
            .quillCodeFullRowButtonTarget(radius: 12)
            .background(rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(rowStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
    }

    private var rowBackground: Color {
        if item.isSelected {
            return QuillCodePalette.selection
        }
        return isHighlighted ? QuillCodePalette.blue.opacity(0.08) : QuillCodePalette.panel
    }

    private var rowStroke: Color {
        if isHighlighted {
            return QuillCodePalette.blue.opacity(0.48)
        }
        return item.isSelected ? QuillCodePalette.blue.opacity(0.22) : Color.white.opacity(0.08)
    }
}
