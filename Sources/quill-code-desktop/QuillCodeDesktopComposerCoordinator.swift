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
              model.composer.attachments.isEmpty,
              !tasks.isSendRunning(threadID: model.selectedThread?.id),
              !model.isAgentRunActive(for: model.selectedThread?.id),
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
        guard !prompt.isEmpty || !model.composer.attachments.isEmpty else { return }

        // `/incognito` opens a fresh private session — intercept it BEFORE the busy-thread
        // follow-up queue below, which would otherwise enqueue the slash text into the running
        // (durable, non-E2E) thread and run it there. Mirrors the native slash dispatch order.
        if model.composer.attachments.isEmpty,
           WorkspaceIncognitoSlash.isIncognitoCommand(prompt) {
            draft = ""
            model.newIncognitoChat()
            refresh()
            return
        }

        // `/side` is intentionally available while the parent chat is running. Intercept it before
        // the normal busy-thread follow-up queue so the parent keeps working and the question runs
        // in its own ephemeral task slot.
        if model.composer.attachments.isEmpty,
           let sideSlash = WorkspaceSideConversationSlash.parse(prompt) {
            draft = ""
            guard let sideThreadID = model.startSideConversation(prompt: sideSlash.prompt) else {
                refresh()
                return
            }
            guard sideSlash.prompt != nil else {
                refresh()
                return
            }
            submitPreparedComposer(
                model: model,
                threadID: sideThreadID,
                fallbackWorkspaceRoot: fallbackWorkspaceRoot,
                tasks: tasks,
                refresh: refresh,
                onSlotFree: onSlotFree
            )
            return
        }

        // Never lock the composer: a submit arriving DURING a live run enqueues as a follow-up
        // chip (drained at the next turn boundary by the run's own drain loop) instead of being
        // silently rejected. When idle, it sends immediately as before.
        let selectedThreadID = model.selectedThread?.id
        if tasks.isSendRunning(threadID: selectedThreadID) || model.isAgentRunActive(for: selectedThreadID) {
            model.enqueueFollowUp(prompt)
            draft = ""
            refresh()
            return
        }

        model.setDraft(prompt)
        let threadID = model.prepareComposerSubmissionThread()
        draft = ""
        submitPreparedComposer(
            model: model,
            threadID: threadID,
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
        let threadID = model.selectedThread?.id
        guard !tasks.isSendRunning(threadID: threadID),
              !model.isAgentRunActive(for: threadID),
              model.prepareRetryLastUserTurn()
        else { return }

        draft = ""
        submitPreparedComposer(
            model: model,
            threadID: threadID,
            fallbackWorkspaceRoot: fallbackWorkspaceRoot,
            tasks: tasks,
            refresh: refresh,
            onSlotFree: onSlotFree
        )
    }

    private func submitPreparedComposer(
        model: QuillCodeWorkspaceModel,
        threadID: UUID?,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void,
        onSlotFree: @escaping @MainActor () -> Void
    ) {
        let runRoot = model.workspaceRoot(forThreadID: threadID) ?? fallbackWorkspaceRoot
        tasks.startIfIdle(.send(threadID)) { [weak model] in
            guard let model else { return }
            await model.submitComposer(
                threadID: threadID,
                workspaceRoot: runRoot,
                onStarted: refresh,
                onProgressUpdated: refresh
            )
        } onFinish: {
            refresh()
            // This chat's send slot just freed. Recover any gate-resolved follow-up queue that may
            // now continue; the recovery path is self-gated by its own chat slot.
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
