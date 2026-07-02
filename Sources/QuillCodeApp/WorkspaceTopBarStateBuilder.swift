import Foundation
import QuillCodeCore

enum WorkspaceTopBarStateBuilder {
    static func state(from root: QuillCodeRootState, agentStatus: String? = nil) -> TopBarState {
        let thread = root.selectedThreadID.flatMap { selectedThreadID in
            root.threads.first { $0.id == selectedThreadID }
        }
        let projectID = thread?.projectID ?? root.selectedProjectID
        let project = projectID.flatMap { selectedProjectID in
            root.projects.first { $0.id == selectedProjectID }
        }

        // Only carry the branch chip forward while it still belongs to the selected
        // project, so switching projects (via any path) never shows a stale branch.
        let branchMatchesSelection = root.topBar.branchStatusProjectID != nil
            && root.topBar.branchStatusProjectID == projectID
        let branchStatus = branchMatchesSelection ? root.topBar.branchStatus : nil
        let branchStatusProjectID = branchMatchesSelection ? root.topBar.branchStatusProjectID : nil

        return TopBarState(
            appName: root.topBar.appName,
            projectName: project?.name,
            threadTitle: thread?.title,
            model: thread?.model ?? root.config.defaultModel,
            mode: thread?.mode ?? root.config.mode,
            agentStatus: agentStatus ?? root.topBar.agentStatus,
            computerUseStatus: root.topBar.computerUseStatus,
            computerUseForegroundApplication: root.topBar.computerUseForegroundApplication,
            branchStatus: branchStatus,
            branchStatusProjectID: branchStatusProjectID
        )
    }
}
