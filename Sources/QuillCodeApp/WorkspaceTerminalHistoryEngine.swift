extension WorkspaceTerminalEngine {
    static func setDraft(_ draft: String, terminal: inout TerminalState) {
        terminal.draft = draft
        terminal.historyCursor = nil
        terminal.historyDraft = nil
    }

    @discardableResult
    static func clearHistory(terminal: inout TerminalState) -> Bool {
        guard !terminal.isRunning else { return false }
        terminal.entries = []
        terminal.historyCursor = nil
        terminal.historyDraft = nil
        return true
    }

    @discardableResult
    static func recallPreviousCommand(terminal: inout TerminalState) -> Bool {
        guard !terminal.isRunning else { return false }
        let history = commandHistory(from: terminal)
        guard !history.isEmpty else { return false }

        if let cursor = terminal.historyCursor {
            guard history.indices.contains(cursor) else {
                resetHistoryCursor(terminal: &terminal)
                return false
            }
            guard cursor > history.startIndex else { return false }
            terminal.historyCursor = history.index(before: cursor)
        } else {
            terminal.historyDraft = terminal.draft
            terminal.historyCursor = history.index(before: history.endIndex)
        }

        if let cursor = terminal.historyCursor {
            terminal.draft = history[cursor]
        }
        return true
    }

    @discardableResult
    static func recallNextCommand(terminal: inout TerminalState) -> Bool {
        guard !terminal.isRunning, let cursor = terminal.historyCursor else { return false }
        let history = commandHistory(from: terminal)
        guard history.indices.contains(cursor) else {
            resetHistoryCursor(terminal: &terminal)
            return false
        }

        let next = history.index(after: cursor)
        if next < history.endIndex {
            terminal.historyCursor = next
            terminal.draft = history[next]
        } else {
            resetHistoryCursor(terminal: &terminal, restoreDraft: true)
        }
        return true
    }

    private static func resetHistoryCursor(
        terminal: inout TerminalState,
        restoreDraft: Bool = false
    ) {
        terminal.historyCursor = nil
        terminal.draft = restoreDraft ? terminal.historyDraft ?? "" : terminal.draft
        terminal.historyDraft = nil
    }

    private static func commandHistory(from terminal: TerminalState) -> [String] {
        terminal.entries.compactMap { entry in
            guard entry.status != .running else { return nil }
            let command = normalizedCommand(entry.command)
            return command.isEmpty ? nil : command
        }
    }
}
