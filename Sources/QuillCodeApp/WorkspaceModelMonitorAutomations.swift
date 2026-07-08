import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func createMonitorAutomation(
        request: WorkspaceMonitorRequest,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard validateMonitorRequest(request) else { return nil }
        let mutation = WorkspaceAutomationStateReducer.createMonitor(
            in: automations,
            request: request,
            project: selectedProject,
            now: now
        )
        applyAutomationState(mutation.state)
        return mutation.value
    }

    private func validateMonitorRequest(_ request: WorkspaceMonitorRequest) -> Bool {
        switch request.kind {
        case .fileChange:
            guard AutomationEventSourceResolver.fileChangeURL(
                for: request.path,
                project: selectedProject
            ) != nil else {
                reportUnrecognizedAutomationSchedule(
                    "Could not watch that file. Use an absolute path or a path inside the selected local project."
                )
                return false
            }
        case .directoryChange:
            guard AutomationEventSourceResolver.directoryChangeURL(
                for: request.path,
                project: selectedProject
            ) != nil else {
                reportUnrecognizedAutomationSchedule(
                    "Could not watch that directory. Use an absolute path or a path inside the selected local project."
                )
                return false
            }
        case .urlLastModified:
            guard AutomationEventSourceResolver.urlLastModifiedURL(for: request.path) != nil else {
                reportUnrecognizedAutomationSchedule(
                    "Could not watch that URL. Use an explicit http:// or https:// URL."
                )
                return false
            }
        case .urlFeedUpdate:
            guard AutomationEventSourceResolver.urlFeedUpdateURL(for: request.path) != nil else {
                reportUnrecognizedAutomationSchedule(
                    "Could not watch that feed. Use an explicit http:// or https:// RSS or Atom URL."
                )
                return false
            }
        }
        return true
    }
}
