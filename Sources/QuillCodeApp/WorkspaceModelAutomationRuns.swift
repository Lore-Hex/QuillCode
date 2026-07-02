import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public func updateAutomationStatus(id: UUID, status: QuillAutomationStatus) -> Bool {
        let mutation = WorkspaceAutomationStateReducer.updateStatus(
            in: automations,
            id: id,
            status: status,
            now: Date()
        )
        guard mutation.value else { return false }
        applyAutomationState(mutation.state)
        return mutation.value
    }

    @discardableResult
    public func runAutomation(id: UUID) -> UUID? {
        runAutomationReport(id: id)?.followUpThreadID
    }

    @discardableResult
    public func runAutomationReport(id: UUID, now: Date = Date()) -> AutomationRunReport? {
        runAutomationReport(id: id, now: now, eventDescription: nil)
    }

    private func runAutomationReport(
        id: UUID,
        now: Date,
        eventDescription: String?
    ) -> AutomationRunReport? {
        guard let automation = automations.items.first(where: { $0.id == id }) else { return nil }
        guard automation.status == .active else { return nil }

        switch automation.kind {
        case .threadFollowUp:
            return runThreadFollowUpAutomation(automation, now: now)
        case .workspaceSchedule:
            return runWorkspaceScheduleAutomation(automation, now: now)
        case .localEnvironmentAction:
            return runLocalEnvironmentActionAutomation(automation, now: now)
        case .monitor:
            return runMonitorAutomation(automation, eventDescription: eventDescription, now: now)
        }
    }

    @discardableResult
    public func runDueAutomations(now: Date = Date(), limit: Int = 5) -> [UUID] {
        runDueAutomationReports(now: now, limit: limit).map(\.followUpThreadID)
    }

    @discardableResult
    public func runDueAutomationReports(now: Date = Date(), limit: Int = 5) -> [AutomationRunReport] {
        let triggers = WorkspaceAutomationRunner.dueAutomationTriggers(
            in: automations.items,
            now: now,
            eventSources: automationEventSources(),
            limit: limit
        )
        return triggers.compactMap {
            runAutomationReport(
                id: $0.automationID,
                now: now,
                eventDescription: $0.eventDescription
            )
        }
    }

    public func deleteAutomation(id: UUID) -> Bool {
        let mutation = WorkspaceAutomationStateReducer.delete(from: automations, id: id)
        guard mutation.value else { return false }
        applyAutomationState(mutation.state)
        return mutation.value
    }

    private func runThreadFollowUpAutomation(
        _ automation: QuillAutomation,
        now: Date
    ) -> AutomationRunReport? {
        guard let threadID = automation.threadID,
              let source = root.threads.first(where: { $0.id == threadID })
        else {
            return reportMissingAutomationDependency(
                "The original thread for \(automation.title) is no longer available."
            )
        }

        let projectID = knownProjectID(automation.projectID ?? source.projectID)
        let copiedMessages = WorkspaceThreadSeedBuilder.forkSeedMessages(from: source.messages)
        let draft = WorkspaceAutomationRunner.threadFollowUpDraft(
            automation: automation,
            source: source,
            selectedProjectID: projectID,
            copiedMessages: copiedMessages,
            now: now
        )
        return applyAutomationRunDraft(draft)
    }

    private func runWorkspaceScheduleAutomation(
        _ automation: QuillAutomation,
        now: Date
    ) -> AutomationRunReport? {
        guard let projectID = automation.projectID,
              let project = project(id: projectID)
        else {
            return reportMissingAutomationDependency(
                "The project for \(automation.title) is no longer available."
            )
        }

        refreshAutomationProjectContext(project)

        let context = workspaceThreadContext(projectID)
        let draft = WorkspaceAutomationRunner.workspaceScheduleDraft(
            automation: automation,
            project: project,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: context.instructions,
            memories: context.memories,
            now: now
        )
        return applyAutomationRunDraft(draft)
    }

    private func runLocalEnvironmentActionAutomation(
        _ automation: QuillAutomation,
        now: Date
    ) -> AutomationRunReport? {
        guard let projectID = automation.projectID,
              let initialProject = project(id: projectID)
        else {
            return reportMissingAutomationDependency(
                "The project for \(automation.title) is no longer available."
            )
        }
        guard !initialProject.isRemote else {
            return reportMissingAutomationDependency(
                "\(automation.title) uses a local environment action, but \(initialProject.name) is an SSH Remote project."
            )
        }

        refreshProjectMetadata(initialProject.id)
        guard let refreshedProject = project(id: initialProject.id),
              let actionID = automation.localEnvironmentActionID,
              let action = LocalEnvironmentActionMatcher.action(withID: actionID, in: refreshedProject.localActions)
        else {
            return reportMissingAutomationDependency(
                "The local environment action for \(automation.title) is no longer available."
            )
        }

        let context = workspaceThreadContext(refreshedProject.id)
        let draft = WorkspaceAutomationRunner.localEnvironmentActionDraft(
            automation: automation,
            project: refreshedProject,
            action: action,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: context.instructions,
            memories: context.memories,
            now: now
        )
        let report = applyAutomationRunDraft(draft)
        let result = runToolCall(
            WorkspaceShellToolCallPlanner.localEnvironmentAction(action),
            workspaceRoot: URL(fileURLWithPath: refreshedProject.path)
        )
        refreshProjectMetadata(refreshedProject.id)
        appendNotice(result.ok
            ? "Scheduled local environment action completed: \(action.title)"
            : "Scheduled local environment action failed: \(action.title)")
        return report
    }

    private func runMonitorAutomation(
        _ automation: QuillAutomation,
        eventDescription: String?,
        now: Date
    ) -> AutomationRunReport? {
        var resolvedProject: ProjectRef?
        if let projectID = automation.projectID {
            guard let project = project(id: projectID) else {
                return reportMissingAutomationDependency(
                    "The project for \(automation.title) is no longer available."
                )
            }
            refreshAutomationProjectContext(project)
            resolvedProject = project
        }

        let context = resolvedProject.map { workspaceThreadContext($0.id) }
        let draft = WorkspaceAutomationRunner.monitorDraft(
            automation: automation,
            project: resolvedProject,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: context?.instructions ?? [],
            memories: context?.memories ?? [],
            triggerDescription: eventDescription,
            now: now
        )
        return applyAutomationRunDraft(draft)
    }

    private func refreshAutomationProjectContext(_ project: ProjectRef) {
        if project.isRemote {
            _ = refreshRemoteProjectContext(project.id)
        } else {
            refreshProjectMetadata(project.id)
        }
    }

    private func applyAutomationRunDraft(_ draft: WorkspaceAutomationRunDraft) -> AutomationRunReport {
        replaceAutomation(draft.automation)
        _ = insertCreatedThread(draft.thread, selectedProjectID: draft.selectedProjectID, saveThread: true)
        setAutomationsVisible(true)
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return draft.report
    }

    private func reportMissingAutomationDependency(_ message: String) -> AutomationRunReport? {
        setLastError(message)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return nil
    }

    private func replaceAutomation(_ automation: QuillAutomation) {
        let mutation = WorkspaceAutomationStateReducer.replace(
            in: automations,
            automation: automation
        )
        guard mutation.value else { return }
        applyAutomationState(mutation.state)
    }

    private func automationEventSources() -> [UUID: any AutomationEventSource] {
        var sources: [UUID: any AutomationEventSource] = [:]
        for automation in automations.items
        where automation.status == .active
            && automation.kind == .monitor
            && automation.scheduleKind == .event {
            guard let eventSource = automation.eventSource else { continue }
            let resolvedProject = automation.projectID.flatMap { project(id: $0) }
            if let source = AutomationEventSourceResolver.eventSource(
                for: eventSource,
                project: resolvedProject
            ) {
                sources[automation.id] = source
            }
        }
        return sources
    }
}
