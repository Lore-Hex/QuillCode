import QuillCodeCore

enum WorkspaceStatusContextBuilder {
    static func context(
        root: QuillCodeRootState,
        selectedProject: ProjectRef?,
        selectedThread: ChatThread?,
        fallbackThreadContext: WorkspaceThreadContextSnapshot
    ) -> WorkspaceStatusContext {
        WorkspaceStatusContext(
            projectName: selectedProject?.name ?? root.topBar.projectName ?? "No project",
            threadTitle: selectedThread?.title ?? "No chat",
            instructions: selectedProject?.instructions ?? selectedThread?.instructions ?? [],
            memories: selectedThread?.memories ?? fallbackThreadContext.memories,
            goal: selectedThread?.goal,
            mode: root.topBar.mode,
            model: root.topBar.model,
            agentStatus: root.topBar.agentStatus
        )
    }
}
