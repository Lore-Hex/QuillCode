import QuillCodeCore

public struct ProjectPluginHookSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var pluginName: String
    public var event: String
    public var matcher: String?
    public var command: String?
    public var relativePath: String
    public var statusLabel: String
    public var supportDetail: String?
    public var actionTitle: String?
    public var actionCommandID: String?

    public init(hook: ProjectPluginHook) {
        self.id = hook.id
        self.name = hook.statusMessage ?? hook.event
        self.pluginName = hook.pluginName
        self.event = hook.event
        self.matcher = hook.matcher
        self.command = hook.command ?? hook.commandWindows
        self.relativePath = hook.relativePath
        self.statusLabel = Self.statusLabel(for: hook)
        self.supportDetail = Self.supportDetail(for: hook.supportStatus)
        switch (hook.isManaged, hook.supportStatus.isSupported, hook.trustStatus) {
        case (true, _, _):
            self.actionTitle = nil
            self.actionCommandID = nil
        case (false, true, .reviewRequired):
            self.actionTitle = "Trust"
            self.actionCommandID = "hook-trust:\(hook.id)"
        case (false, true, .trusted):
            self.actionTitle = "Disable"
            self.actionCommandID = "hook-disable:\(hook.id)"
        case (false, true, .disabled):
            self.actionTitle = "Enable"
            self.actionCommandID = "hook-trust:\(hook.id)"
        case (false, false, _):
            self.actionTitle = nil
            self.actionCommandID = nil
        }
    }

    private static func statusLabel(for hook: ProjectPluginHook) -> String {
        guard hook.supportStatus.isSupported else { return "Unsupported" }
        if hook.isManaged { return "Managed" }
        switch hook.trustStatus {
        case .reviewRequired: return "Review required"
        case .trusted: return "Trusted"
        case .disabled: return "Disabled"
        }
    }

    private static func supportDetail(for status: ProjectHookSupportStatus) -> String? {
        switch status {
        case .supported:
            return nil
        case .unsupportedEvent:
            return "This lifecycle event is not executable in this build."
        case .unsupportedMatcher:
            return "This matcher is not supported for this lifecycle event."
        case .unsupportedHandler:
            return "Only command hooks are executable."
        case .asynchronousHandler:
            return "Asynchronous hooks are parsed but not executable."
        case .missingCommand:
            return "This command hook has no command for this platform."
        }
    }
}
