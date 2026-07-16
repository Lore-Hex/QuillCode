public enum ManagedApprovalPolicy: Sendable, Equatable {
    case named(String)
    case granular(ManagedGranularApprovalPolicy)
}

public struct ManagedGranularApprovalPolicy: Sendable, Equatable {
    public var sandboxApproval: Bool
    public var rules: Bool
    public var mcpElicitations: Bool
    public var skillApproval: Bool
    public var requestPermissions: Bool

    public init(
        sandboxApproval: Bool,
        rules: Bool,
        mcpElicitations: Bool,
        skillApproval: Bool = false,
        requestPermissions: Bool = false
    ) {
        self.sandboxApproval = sandboxApproval
        self.rules = rules
        self.mcpElicitations = mcpElicitations
        self.skillApproval = skillApproval
        self.requestPermissions = requestPermissions
    }
}
