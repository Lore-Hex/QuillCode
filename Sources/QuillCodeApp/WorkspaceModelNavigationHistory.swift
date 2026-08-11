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

    /// Restores the complete workspace location. A legacy/projectless chat can coexist with an
    /// explicitly selected project, so thread and project are independent parts of the location.
    @discardableResult
    public func selectWorkspaceLocation(
        _ location: WorkspaceNavigationLocation,
        recordsNavigation: Bool = true
    ) -> Bool {
        let previousLocation = currentNavigationLocation
        if let threadID = location.threadID,
           let thread = root.threads.first(where: { $0.id == threadID }) {
            let projectContextID = knownProjectID(location.projectID)
                ?? knownProjectID(thread.projectID)
            selectThread(
                threadID,
                projectContextID: projectContextID,
                recordsNavigation: false
            )
        } else if let projectID = knownProjectID(location.projectID) {
            selectProject(projectID, recordsNavigation: false)
        } else {
            pruneNavigationHistory()
            return false
        }
        if recordsNavigation {
            recordNavigationTransition(from: previousLocation)
        }
        return true
    }

    @discardableResult
    private func applyNavigationLocation(_ location: WorkspaceNavigationLocation) -> Bool {
        selectWorkspaceLocation(location, recordsNavigation: false)
    }
}
