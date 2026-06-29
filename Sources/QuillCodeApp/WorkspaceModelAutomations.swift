import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public func setAutomations(_ items: [QuillAutomation]) {
        applyAutomationState(WorkspaceAutomationStateReducer.setItems(
            items,
            isVisible: automations.isVisible
        ))
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        scheduleDescription: String = "Manual follow-up",
        nextRunAt: Date? = nil,
        recurrence: QuillAutomationRecurrence? = nil,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let thread = selectedThread else { return nil }
        let mutation = WorkspaceAutomationStateReducer.createThreadFollowUp(
            in: automations,
            thread: thread,
            selectedProjectID: root.selectedProjectID,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        applyAutomationState(mutation.state)
        return mutation.value
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        after seconds: TimeInterval,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let schedule = WorkspaceAutomationFactory.relativeSchedule(seconds: seconds, now: now) else {
            return nil
        }
        return createThreadFollowUpAutomation(
            scheduleDescription: schedule.description,
            nextRunAt: schedule.nextRunAt,
            now: now
        )
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        matching scheduleText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        guard let schedule = ThreadFollowUpScheduleParser.parse(
            scheduleText,
            now: now,
            calendar: calendar
        ) else {
            setLastError("Could not understand that follow-up schedule. Try `/follow-up in 30 minutes`, `/follow-up tomorrow at 9 AM`, or `/follow-up daily`.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return nil
        }
        return createThreadFollowUpAutomation(
            scheduleDescription: schedule.scheduleDescription,
            nextRunAt: schedule.nextRunAt,
            recurrence: schedule.recurrence,
            now: now
        )
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        every recurrence: QuillAutomationRecurrence,
        now: Date = Date()
    ) -> QuillAutomation? {
        createThreadFollowUpAutomation(
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: recurrence.nextRun(after: now),
            recurrence: recurrence,
            now: now
        )
    }

    @discardableResult
    public func createTomorrowMorningThreadFollowUpAutomation(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        createThreadFollowUpAutomation(
            scheduleDescription: "Tomorrow at 9:00 AM",
            nextRunAt: WorkspaceAutomationFactory.tomorrowMorning(from: now, calendar: calendar),
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        scheduleDescription: String = "Manual workspace check",
        nextRunAt: Date? = nil,
        recurrence: QuillAutomationRecurrence? = nil,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let project = selectedProject else { return nil }
        let mutation = WorkspaceAutomationStateReducer.createWorkspaceSchedule(
            in: automations,
            project: project,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        applyAutomationState(mutation.state)
        return mutation.value
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        after seconds: TimeInterval,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let schedule = WorkspaceAutomationFactory.relativeSchedule(seconds: seconds, now: now) else {
            return nil
        }
        return createWorkspaceScheduleAutomation(
            scheduleDescription: schedule.description,
            nextRunAt: schedule.nextRunAt,
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        matching scheduleText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        guard let schedule = ThreadFollowUpScheduleParser.parse(
            scheduleText,
            now: now,
            calendar: calendar
        ) else {
            setLastError("Could not understand that workspace-check schedule. Try `/workspace-check in 1 hour`, `/workspace-check tomorrow at 9 AM`, or `/workspace-check every 2 hours`.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return nil
        }
        return createWorkspaceScheduleAutomation(
            scheduleDescription: schedule.scheduleDescription,
            nextRunAt: schedule.nextRunAt,
            recurrence: schedule.recurrence,
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        every recurrence: QuillAutomationRecurrence,
        now: Date = Date()
    ) -> QuillAutomation? {
        createWorkspaceScheduleAutomation(
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: recurrence.nextRun(after: now),
            recurrence: recurrence,
            now: now
        )
    }

    @discardableResult
    public func createTomorrowMorningWorkspaceScheduleAutomation(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        createWorkspaceScheduleAutomation(
            scheduleDescription: "Tomorrow at 9:00 AM",
            nextRunAt: WorkspaceAutomationFactory.tomorrowMorning(from: now, calendar: calendar),
            now: now
        )
    }

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
            setLastError("The original thread for \(automation.title) is no longer available.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return nil
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
            setLastError("The project for \(automation.title) is no longer available.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return nil
        }

        if project.isRemote {
            _ = refreshRemoteProjectContext(projectID)
        } else {
            refreshProjectMetadata(projectID)
        }

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

    private func runMonitorAutomation(
        _ automation: QuillAutomation,
        eventDescription: String?,
        now: Date
    ) -> AutomationRunReport? {
        var resolvedProject: ProjectRef?
        if let projectID = automation.projectID {
            guard let project = project(id: projectID) else {
                setLastError("The project for \(automation.title) is no longer available.")
                refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
                return nil
            }

            if project.isRemote {
                _ = refreshRemoteProjectContext(projectID)
            } else {
                refreshProjectMetadata(projectID)
            }
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

    private func applyAutomationRunDraft(_ draft: WorkspaceAutomationRunDraft) -> AutomationRunReport {
        replaceAutomation(draft.automation)
        _ = insertCreatedThread(draft.thread, selectedProjectID: draft.selectedProjectID, saveThread: true)
        setAutomationsVisible(true)
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return draft.report
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
