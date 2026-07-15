import QuillCodeCore

enum ProjectHookExecutionRouting {
    /// Project hooks follow the selected workspace, including SSH. User and managed config is
    /// discovered on this computer, so its commands must execute on this computer as well.
    static func selectedProject(
        for scope: ProjectHookTrustScope,
        selectedProject: ProjectRef?
    ) -> ProjectRef? {
        scope == .workspace ? selectedProject : nil
    }
}
