import Foundation
import QuillCodeCore

extension QuillCodeWorkspaceModel {
    @discardableResult
    public func runLocalEnvironmentAction(_ actionID: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let action = LocalEnvironmentActionMatcher.action(
            withID: actionID,
            in: selectedProject?.localActions ?? []
        ) else {
            return false
        }

        runToolCall(
            WorkspaceShellToolCallPlanner.localEnvironmentAction(action),
            workspaceRoot: workspaceRoot
        )
        return true
    }

    func runEnvironmentSlashCommand(_ query: String?, originalPrompt: String, workspaceRoot: URL) {
        refreshProjectMetadata(root.selectedProjectID)
        let plan = WorkspaceEnvironmentSlashCommandPlanner.plan(
            query: query,
            userText: originalPrompt,
            actions: selectedProject?.localActions ?? []
        )
        switch plan {
        case .transcript(let transcript):
            appendLocalCommandTranscript(transcript)
        case .runAction(let actionID):
            _ = runLocalEnvironmentAction(actionID, workspaceRoot: workspaceRoot)
        }
    }

    @discardableResult
    public func createLocalEnvironmentActionAutomation(
        actionID: String,
        scheduleDescription: String,
        nextRunAt: Date?,
        recurrence: QuillAutomationRecurrence? = nil,
        now: Date = Date()
    ) -> QuillAutomation? {
        refreshProjectMetadata(root.selectedProjectID)
        guard let project = selectedProject, !project.isRemote,
              let action = LocalEnvironmentActionMatcher.action(withID: actionID, in: project.localActions)
        else {
            return nil
        }

        let mutation = WorkspaceAutomationStateReducer.createLocalEnvironmentAction(
            in: automations,
            project: project,
            action: action,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        applyAutomationState(mutation.state)
        return mutation.value
    }

    @discardableResult
    public func createLocalEnvironmentActionAutomation(
        matching scheduleText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        refreshProjectMetadata(root.selectedProjectID)
        guard let plan = WorkspaceEnvironmentSchedulePlanner.plan(
            scheduleText,
            actions: selectedProject?.localActions ?? [],
            now: now,
            calendar: calendar
        ) else {
            reportUnrecognizedAutomationSchedule(environmentScheduleErrorMessage)
            return nil
        }
        return createLocalEnvironmentActionAutomation(
            actionID: plan.action.id,
            scheduleDescription: plan.schedule.scheduleDescription,
            nextRunAt: plan.schedule.nextRunAt,
            recurrence: plan.schedule.recurrence,
            now: now
        )
    }

    func runEnvironmentScheduleSlashCommand(_ scheduleText: String, originalPrompt: String) {
        let automation = createLocalEnvironmentActionAutomation(matching: scheduleText)
        let transcript = automation.map {
            WorkspaceSlashCommandTranscriptPlanner.environmentScheduleScheduled(
                userText: originalPrompt,
                actionTitle: localEnvironmentActionTitle(for: $0) ?? $0.title,
                scheduleDescription: $0.scheduleDescription
            )
        } ?? WorkspaceSlashCommandTranscriptPlanner.environmentScheduleFailed(
            userText: originalPrompt,
            message: lastError
        )
        appendLocalCommandTranscript(transcript)
    }

    private func localEnvironmentActionTitle(for automation: QuillAutomation) -> String? {
        guard let actionID = automation.localEnvironmentActionID else { return nil }
        return selectedProject?.localActions.first { $0.id == actionID }?.title
    }
}

private let environmentScheduleErrorMessage = """
Could not understand that local environment schedule. Try `/env schedule Build in 30 minutes`, \
`/env schedule Test Friday at 4 PM`, or `/env schedule Verify every 2 hours`.
"""
