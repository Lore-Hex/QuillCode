import Foundation

public enum ProjectRunHookTiming: String, Codable, Sendable, Hashable {
    case beforeAgentRun = "before_agent_run"
    case afterAgentRun = "after_agent_run"
}

public struct ProjectRunHook: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var timing: ProjectRunHookTiming
    public var title: String
    public var detail: String?
    public var relativePath: String
    public var command: String
    public var sortOrder: Int?
    public var environment: [String: String]?
    public var workingDirectory: String?
    public var timeoutSeconds: Int?
    public var pluginID: String?
    public var pluginRootRelativePath: String?
    /// `nil` decodes legacy hooks as workspace-scoped.
    public var trustScope: ProjectHookTrustScope?

    public init(
        id: String,
        timing: ProjectRunHookTiming,
        title: String,
        detail: String? = nil,
        relativePath: String,
        command: String,
        sortOrder: Int? = nil,
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeoutSeconds: Int? = nil,
        pluginID: String? = nil,
        pluginRootRelativePath: String? = nil,
        trustScope: ProjectHookTrustScope? = nil
    ) {
        self.id = id
        self.timing = timing
        self.title = title
        self.detail = detail
        self.relativePath = relativePath
        self.command = command
        self.sortOrder = sortOrder
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.pluginID = pluginID
        self.pluginRootRelativePath = pluginRootRelativePath
        self.trustScope = trustScope
    }

    public var effectiveTrustScope: ProjectHookTrustScope {
        trustScope ?? .workspace
    }
}
