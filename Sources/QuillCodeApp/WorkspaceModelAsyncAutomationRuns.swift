import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func runAutomationCancellable(
        id: UUID,
        now: Date = Date(),
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async -> UUID? {
        await runAutomationReportAsync(
            id: id,
            now: now,
            eventDescription: nil,
            onProgressUpdated: onProgressUpdated
        )?.followUpThreadID
    }

    @discardableResult
    public func runDueAutomationReportsAsync(
        now: Date = Date(),
        limit: Int = 5,
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async -> [AutomationRunReport] {
        await runDueAutomationReportsAsync(
            now: now,
            limit: limit,
            eventSources: automationEventSources(),
            onProgressUpdated: onProgressUpdated
        )
    }

    func runDueAutomationReportsAsync(
        now: Date,
        limit: Int,
        eventSources: [UUID: any AutomationEventSource],
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async -> [AutomationRunReport] {
        let snapshot = automations.items
        let triggers = await WorkspaceAutomationRunner.dueAutomationTriggersAsync(
            in: snapshot,
            now: now,
            eventSources: eventSources,
            limit: limit
        )
        guard !Task.isCancelled else { return [] }

        let snapshotByID = Dictionary(
            snapshot.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var reports: [AutomationRunReport] = []
        reports.reserveCapacity(triggers.count)
        for trigger in triggers {
            guard let original = snapshotByID[trigger.automationID],
                  automations.items.first(where: { $0.id == trigger.automationID }) == original
            else {
                continue
            }
            if let report = await runAutomationReportAsync(
                id: trigger.automationID,
                now: now,
                eventDescription: trigger.eventDescription,
                onProgressUpdated: onProgressUpdated
            ) {
                reports.append(report)
            }
            guard !Task.isCancelled else { break }
        }
        return reports
    }

    private func runAutomationReportAsync(
        id: UUID,
        now: Date,
        eventDescription: String?,
        onProgressUpdated: (@MainActor @Sendable () -> Void)?
    ) async -> AutomationRunReport? {
        guard let automation = automations.items.first(where: { $0.id == id }),
              automation.status == .active
        else {
            return nil
        }

        switch automation.kind {
        case .localEnvironmentAction:
            return await runLocalEnvironmentActionAutomationAsync(
                automation,
                now: now,
                onProgressUpdated: onProgressUpdated
            )
        case .threadFollowUp:
            return runThreadFollowUpAutomation(automation, now: now)
        case .workspaceSchedule:
            return runWorkspaceScheduleAutomation(automation, now: now)
        case .monitor:
            return runMonitorAutomation(automation, eventDescription: eventDescription, now: now)
        }
    }

    private func runLocalEnvironmentActionAutomationAsync(
        _ automation: QuillAutomation,
        now: Date,
        onProgressUpdated: (@MainActor @Sendable () -> Void)?
    ) async -> AutomationRunReport? {
        guard let projectID = automation.projectID,
              let project = project(id: projectID)
        else {
            return reportMissingAutomationDependency(
                "The project for \(automation.title) is no longer available."
            )
        }
        guard !project.isRemote else {
            return reportMissingAutomationDependency(
                "\(automation.title) uses a local environment action, but "
                    + "\(project.name) is an SSH Remote project."
            )
        }
        guard let actionID = automation.localEnvironmentActionID,
              let action = LocalEnvironmentActionMatcher.action(withID: actionID, in: project.localActions)
        else {
            return reportMissingAutomationDependency(
                "The local environment action for \(automation.title) is no longer available."
            )
        }

        let context = workspaceThreadContext(project.id)
        let draft = WorkspaceAutomationRunner.localEnvironmentActionDraft(
            automation: automation,
            project: project,
            action: action,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: context.instructions,
            memories: context.memories,
            now: now
        )
        let report = applyAutomationRunDraft(draft)
        let result = await runCancellableToolCall(
            WorkspaceShellToolCallPlanner.localEnvironmentAction(action),
            workspaceRoot: URL(fileURLWithPath: project.path),
            threadID: report.followUpThreadID,
            onProgressUpdated: onProgressUpdated
        )
        appendLocalEnvironmentActionNotice(
            action,
            succeeded: result?.ok == true,
            threadID: report.followUpThreadID
        )
        onProgressUpdated?()
        return report
    }

    private func appendLocalEnvironmentActionNotice(
        _ action: LocalEnvironmentAction,
        succeeded: Bool,
        threadID: UUID
    ) {
        mutateThread(threadID) { thread in
            WorkspaceThreadNoticeAppender.appendNotice(
                succeeded
                    ? "Scheduled local environment action completed: \(action.title)"
                    : "Scheduled local environment action failed: \(action.title)",
                to: &thread
            )
        }
    }
}
