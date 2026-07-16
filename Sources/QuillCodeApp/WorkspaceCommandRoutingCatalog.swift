public enum WorkspaceCommandRoutingCatalog {
    private static let hostCommandIDs: Set<String> = [
        "stop-all",
        "computer-use-open-screen-recording",
        "computer-use-open-accessibility",
        "computer-use-refresh",
        "trustedrouter-credits-refresh",
        "dictation"
    ]

    public static func isHostCommand(_ commandID: String) -> Bool {
        hostCommandIDs.contains(commandID)
    }

    public static func canRunInWorkspaceModel(_ commandID: String) -> Bool {
        WorkspaceCommandPlan(commandID: commandID) != nil
    }

    public static func isDispatchable(_ commandID: String) -> Bool {
        isHostCommand(commandID) || canRunInWorkspaceModel(commandID)
    }
}
