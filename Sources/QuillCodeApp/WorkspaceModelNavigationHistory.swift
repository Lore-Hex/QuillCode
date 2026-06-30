import Foundation

@MainActor
extension QuillCodeWorkspaceModel {
    var currentNavigationLocation: WorkspaceNavigationLocation {
        WorkspaceNavigationLocation(
            threadID: root.selectedThreadID,
            projectID: root.selectedProjectID
        )
    }

    func recordNavigationTransition(from oldLocation: WorkspaceNavigationLocation) {
        navigationHistory.recordTransition(from: oldLocation, to: currentNavigationLocation)
    }

    func pruneNavigationHistory() {
        navigationHistory.prune(
            validThreadIDs: Set(root.threads.map(\.id)),
            validProjectIDs: Set(root.projects.map(\.id))
        )
    }

    @discardableResult
    public func navigateBackInWorkspace() -> Bool {
        while let location = navigationHistory.goBack() {
            if applyNavigationLocation(location) {
                return true
            }
        }
        return false
    }

    @discardableResult
    public func navigateForwardInWorkspace() -> Bool {
        while let location = navigationHistory.goForward() {
            if applyNavigationLocation(location) {
                return true
            }
        }
        return false
    }

    @discardableResult
    private func applyNavigationLocation(_ location: WorkspaceNavigationLocation) -> Bool {
        if let threadID = location.threadID,
           root.threads.contains(where: { $0.id == threadID }) {
            selectThread(threadID, recordsNavigation: false)
            return true
        }

        if let projectID = location.projectID,
           root.projects.contains(where: { $0.id == projectID }) {
            selectProject(projectID, recordsNavigation: false)
            return true
        }

        pruneNavigationHistory()
        return false
    }
}
