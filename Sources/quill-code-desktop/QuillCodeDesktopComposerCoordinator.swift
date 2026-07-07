import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopComposerCoordinator {
    func openBrowserSessionFromSlashIfNeeded(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void,
        openVisibleBrowserSession: @escaping @MainActor () -> Void
    ) -> Bool {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty,
              !tasks.isRunning(.send),
              let slashTarget = browserSessionSlashTarget(prompt)
        else {
            return false
        }

        draft = ""
        let root = model.activeWorkspaceRoot ?? fallbackWorkspaceRoot
        guard model.runBrowserSessionSlashCommand(slashTarget.target, originalPrompt: prompt, workspaceRoot: root) else {
            refresh()
            return true
        }
        refresh()
        openVisibleBrowserSession()
        return true
    }

    func send(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void,
        onSlotFree: @escaping @MainActor () -> Void = {}
    ) {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        // Never lock the composer: a submit arriving DURING a live run enqueues as a follow-up
        // chip (drained at the next turn boundary by the run's own drain loop) instead of being
        // silently rejected. When idle, it sends immediately as before.
        if tasks.isRunning(.send) {
            model.enqueueFollowUp(prompt)
            draft = ""
            refresh()
            return
        }

        model.setDraft(prompt)
        draft = ""
        submitPreparedComposer(
            model: model,
            fallbackWorkspaceRoot: fallbackWorkspaceRoot,
            tasks: tasks,
            refresh: refresh,
            onSlotFree: onSlotFree
        )
    }

    func retryLastTurn(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void,
        onSlotFree: @escaping @MainActor () -> Void = {}
    ) {
        guard !tasks.isRunning(.send), model.prepareRetryLastUserTurn() else { return }

        draft = ""
        submitPreparedComposer(
            model: model,
            fallbackWorkspaceRoot: fallbackWorkspaceRoot,
            tasks: tasks,
            refresh: refresh,
            onSlotFree: onSlotFree
        )
    }

    private func submitPreparedComposer(
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void,
        onSlotFree: @escaping @MainActor () -> Void
    ) {
        tasks.startIfIdle(.send) { [weak model] in
            guard let model else { return }
            await model.submitComposer(
                workspaceRoot: model.activeWorkspaceRoot ?? fallbackWorkspaceRoot,
                onStarted: refresh,
                onProgressUpdated: refresh
            )
        } onFinish: {
            refresh()
            // The `.send` slot just freed. Recover any OTHER thread's follow-up queue that was
            // stranded because it was decided/finished while this send held the single slot (a
            // cross-thread deny). Self-gated, so a no-op when there is nothing to recover.
            onSlotFree()
        }
    }

    private enum BrowserSessionSlashTarget {
        case currentTab
        case target(String)

        var target: String? {
            switch self {
            case .currentTab:
                return nil
            case .target(let target):
                return target
            }
        }
    }

    private func browserSessionSlashTarget(_ prompt: String) -> BrowserSessionSlashTarget? {
        let lowercased = prompt.lowercased()
        for prefix in ["/session", "/browser-session"] where lowercased == prefix || lowercased.hasPrefix(prefix + " ") {
            let argument = String(prompt.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return argument.isEmpty ? .currentTab : .target(argument)
        }
        return nil
    }
}
