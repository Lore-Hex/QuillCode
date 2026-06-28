import SwiftUI
import QuillCodeCore

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

    @State private var localQuery: String
    @State private var highlightedThreadID: UUID?
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
                                isHighlighted: highlightedThreadID == item.id,
                                onSelect: onSelectThread
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
            ensureHighlightedResult(preferredID: sidebar.selectedThreadID)
            focusSearchField()
        }
        .onChange(of: localQuery) { _, newValue in
            if query != newValue {
                query = newValue
            }
            ensureHighlightedResult(preferredID: highlightedThreadID)
        }
        .onChange(of: query) { _, newValue in
            if localQuery != newValue {
                localQuery = newValue
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                moveHighlightedResult(by: -1)
            case .down:
                moveHighlightedResult(by: 1)
            default:
                break
            }
        }
        .onDisappear {
            isSearchFocused = false
            highlightedThreadID = nil
        }
    }

    private func ensureHighlightedResult(preferredID: UUID?) {
        if let preferredID, results.contains(where: { $0.id == preferredID }) {
            highlightedThreadID = preferredID
            return
        }
        if let highlightedThreadID, results.contains(where: { $0.id == highlightedThreadID }) {
            return
        }
        highlightedThreadID = results.first?.id
    }

    private func moveHighlightedResult(by delta: Int) {
        guard !results.isEmpty else {
            highlightedThreadID = nil
            return
        }
        let currentIndex = highlightedThreadID.flatMap { id in
            results.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = (currentIndex + delta + results.count) % results.count
        highlightedThreadID = results[nextIndex].id
    }

    private func selectHighlightedResult() {
        guard let highlighted = highlightedThreadID.flatMap({ id in
            results.first { $0.id == id }
        }) ?? results.first else { return }
        onSelectThread(highlighted.id)
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
    var isHighlighted: Bool
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
