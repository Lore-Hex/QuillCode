import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceMemoryWorkflowContext: Sendable {
    var globalMemoryDirectory: URL?
    var editableProject: ProjectRef?
    var editableProjectRoot: URL?
    var sshRemoteShellExecutor: SSHRemoteShellExecutor
}

enum WorkspaceMemoryWorkflow {
    static func scope(for id: String) -> MemoryScope {
        id.hasPrefix("\(MemoryScope.project.rawValue):") ? .project : .global
    }

    static func editableNote(
        id: String,
        globalMemories: [MemoryNote],
        project: ProjectRef?
    ) -> MemoryNote? {
        switch scope(for: id) {
        case .global:
            return globalMemories.first { $0.id == id && $0.scope == .global }
        case .project:
            return project?.memories.first { $0.id == id && $0.scope == .project }
        }
    }

    static func delete(
        id: String,
        context: WorkspaceMemoryWorkflowContext
    ) -> WorkspaceMemoryMutation? {
        switch scope(for: id) {
        case .global:
            return WorkspaceMemoryEngine.deleteGlobal(
                id: id,
                directory: context.globalMemoryDirectory
            )
        case .project:
            return projectMutation(context: context) { project in
                WorkspaceMemoryEngine.deleteRemoteProject(
                    id: id,
                    project: project,
                    executor: context.sshRemoteShellExecutor
                )
            } local: {
                WorkspaceMemoryEngine.deleteProject(
                    id: id,
                    projectRoot: context.editableProjectRoot
                )
            }
        }
    }

    static func update(
        id: String,
        content: String,
        userText: String,
        context: WorkspaceMemoryWorkflowContext
    ) -> WorkspaceMemoryMutation {
        switch scope(for: id) {
        case .global:
            return WorkspaceMemoryEngine.updateGlobal(
                id: id,
                content: content,
                userText: userText,
                directory: context.globalMemoryDirectory
            )
        case .project:
            return projectMutation(context: context) { project in
                WorkspaceMemoryEngine.updateRemoteProject(
                    id: id,
                    content: content,
                    userText: userText,
                    project: project,
                    executor: context.sshRemoteShellExecutor
                )
            } local: {
                WorkspaceMemoryEngine.updateProject(
                    id: id,
                    content: content,
                    userText: userText,
                    projectRoot: context.editableProjectRoot
                )
            }
        }
    }

    private static func projectMutation(
        context: WorkspaceMemoryWorkflowContext,
        remote: (ProjectRef) -> WorkspaceMemoryMutation,
        local: () -> WorkspaceMemoryMutation
    ) -> WorkspaceMemoryMutation {
        guard context.editableProject?.isRemote == true,
              let project = context.editableProject
        else {
            return local()
        }
        return remote(project)
    }
}
