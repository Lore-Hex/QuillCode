enum WorkspaceHTMLSecondaryPaneRenderer {
    static func renderExtensions(_ extensions: WorkspaceExtensionsSurface) -> String {
        WorkspaceHTMLExtensionsPaneRenderer.render(extensions)
    }

    static func renderMemories(_ memories: WorkspaceMemoriesSurface) -> String {
        WorkspaceHTMLMemoriesPaneRenderer.render(memories)
    }

    static func renderActivity(_ activity: WorkspaceActivitySurface) -> String {
        WorkspaceHTMLActivityPaneRenderer.render(activity)
    }

    static func renderAutomations(_ automations: WorkspaceAutomationsSurface) -> String {
        WorkspaceHTMLAutomationsPaneRenderer.render(automations)
    }
}
