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

    func reportUnrecognizedAutomationSchedule(_ message: String) {
        setLastError(message)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }
}
