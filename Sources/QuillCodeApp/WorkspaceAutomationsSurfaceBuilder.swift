import Foundation
import QuillCodeCore

struct WorkspaceAutomationsSurfaceBuilder: Sendable, Hashable {
    var isVisible: Bool
    var automations: [QuillAutomation]
    var hasSelectedThread: Bool
    var hasSelectedProject: Bool

    func surface() -> WorkspaceAutomationsSurface {
        WorkspaceAutomationsSurface(
            isVisible: isVisible,
            automations: automations,
            createThreadFollowUpCommand: .automationCreateThreadFollowUp(
                isEnabled: hasSelectedThread
            ),
            createWorkspaceScheduleCommand: .automationCreateWorkspaceSchedule(
                isEnabled: hasSelectedProject
            ),
            scheduleThreadFollowUpCommands: WorkspaceCommandSurface.automationScheduleThreadFollowUpCommands(
                isEnabled: hasSelectedThread
            ),
            scheduleWorkspaceScheduleCommands: WorkspaceCommandSurface.automationScheduleWorkspaceScheduleCommands(
                isEnabled: hasSelectedProject
            )
        )
    }
}
