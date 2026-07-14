import Foundation
import QuillCodeAgent
import QuillCodeCore

extension WorkspaceAgentSendSession {
    func prepareLifecycle(
        thread: ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async -> WorkspaceLifecyclePreparation {
        let event: ProjectPluginLifecycleHookEvent?
        switch lifecycle {
        case .primary(let coordinator):
            event = coordinator.consumeSource(for: thread.id).map(ProjectPluginLifecycleHookEvent.sessionStart)
        case .subagent(let context, let runsStartHook):
            event = runsStartHook ? .subagentStart(context) : nil
        }
        guard let event else { return WorkspaceLifecyclePreparation(thread: thread) }

        var activeThread = thread
        let report = await pluginLifecycleHooks.run(
            event: event,
            sessionThread: activeThread,
            workspaceRoot: workspaceRoot
        )
        appendLifecycleReport(report, eventName: event.name, to: &activeThread)
        if !report.continues {
            appendAssistantMessage(
                "Session stopped by a trusted plugin hook. \(report.stopReason ?? "The hook requested a stop.")",
                to: &activeThread
            )
        }
        await onProgress?(activeThread)
        return WorkspaceLifecyclePreparation(thread: activeThread, stopped: !report.continues)
    }

    func runSubagentStopHooks(
        thread: ChatThread,
        stopHookActive: Bool,
        onProgress: AgentRunProgressHandler?
    ) async throws -> WorkspaceAgentSendSessionResult {
        guard case .subagent(let context, _) = lifecycle else {
            return completed(thread: thread)
        }
        var activeThread = thread
        let report = await pluginLifecycleHooks.run(
            event: .subagentStop(
                context,
                stopHookActive: stopHookActive,
                lastAssistantMessage: activeThread.messages.last(where: { $0.role == .assistant })?.content
            ),
            sessionThread: activeThread,
            workspaceRoot: workspaceRoot
        )
        appendLifecycleReport(report, eventName: "SubagentStop", to: &activeThread)
        if !report.continues {
            activeThread.events.append(ThreadEvent(
                kind: .notice,
                summary: "SubagentStop hook ended the delegated run: "
                    + (report.stopReason ?? "A trusted hook requested a stop.")
            ))
            activeThread.updatedAt = Date()
            await onProgress?(activeThread)
            return completed(thread: activeThread)
        }
        guard let continuation = report.continuationReason else {
            await onProgress?(activeThread)
            return completed(thread: activeThread)
        }
        guard !stopHookActive else {
            activeThread.events.append(ThreadEvent(
                kind: .notice,
                summary: "Ignored another SubagentStop-hook continuation."
            ))
            activeThread.updatedAt = Date()
            await onProgress?(activeThread)
            return completed(thread: activeThread)
        }

        appendUserTurn(continuation, to: &activeThread)
        HookContinuationState.record(
            prompt: continuation,
            eventSummary: HookContinuationState.subagentStopEventSummary,
            in: &activeThread
        )
        await onProgress?(activeThread)
        return try await runAgentTurn(
            prompt: continuation,
            thread: activeThread,
            stopHookActive: false,
            subagentStopHookActive: true,
            onProgress: onProgress
        )
    }

    private func appendLifecycleReport(
        _ report: ProjectPluginLifecycleHookReport,
        eventName: String,
        to thread: inout ChatThread
    ) {
        for notice in report.notices {
            thread.events.append(ThreadEvent(kind: .notice, summary: notice))
        }
        guard !report.contexts.isEmpty else {
            if !report.notices.isEmpty { thread.updatedAt = Date() }
            return
        }
        let content = report.contexts.map { context in
            "Standard plugin \(eventName) context from \(context.hook.pluginName):\n\(context.content)"
        }.joined(separator: "\n\n")
        thread.messages.append(ChatMessage(role: .system, content: content))
        thread.updatedAt = Date()
    }
}

struct WorkspaceLifecyclePreparation: Sendable {
    var thread: ChatThread
    var stopped = false
}

struct HookContinuationState: Codable, Sendable, Equatable {
    static let stopEventSummary = "Stop hook requested another agent turn"
    static let subagentStopEventSummary = "SubagentStop hook requested another agent turn"

    var turnID: UUID
    var prompt: String

    static func record(
        prompt: String,
        eventSummary: String,
        in thread: inout ChatThread
    ) {
        guard let turnID = thread.messages.last(where: { $0.role == .user })?.id else { return }
        let state = Self(turnID: turnID, prompt: prompt)
        thread.events.append(ThreadEvent(
            kind: .notice,
            summary: eventSummary,
            payloadJSON: try? JSONHelpers.encodePretty(state)
        ))
        thread.updatedAt = Date()
    }

    static func active(eventSummary: String, in thread: ChatThread) -> Self? {
        guard let latestUserID = thread.messages.last(where: { $0.role == .user })?.id else {
            return nil
        }
        return thread.events.reversed().lazy.compactMap { event -> Self? in
            guard event.kind == .notice,
                  event.summary == eventSummary,
                  let payload = event.payloadJSON,
                  let state = try? JSONHelpers.decode(Self.self, from: payload),
                  state.turnID == latestUserID
            else { return nil }
            return state
        }.first
    }
}
