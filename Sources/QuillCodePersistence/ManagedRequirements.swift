import Foundation

public struct ManagedRequirements: Sendable, Equatable {
    public static let builtInPermissionProfiles: [String: String] = [
        ":read-only": "read-only",
        ":workspace": "workspace-write",
        ":danger-full-access": "danger-full-access"
    ]

    public var allowedApprovalPolicies: [ManagedApprovalPolicy]?
    public var allowedApprovalsReviewers: [String]?
    public var allowedSandboxModes: [String]?
    public var allowedWindowsSandboxImplementations: [String]?
    public var allowedPermissionProfiles: [String: Bool]?
    public var defaultPermissions: String?
    public var allowedWebSearchModes: [String]?
    public var allowManagedHooksOnly: Bool?
    public var allowAppshots: Bool?
    public var allowRemoteControl: Bool?
    public var computerUse: ManagedComputerUseRequirements?
    public var featureRequirements: [String: Bool]?
    public var hooks: ManagedHookRequirements?
    public var enforceResidency: String?
    public var network: ManagedNetworkRequirements?

    public init(
        allowedApprovalPolicies: [ManagedApprovalPolicy]? = nil,
        allowedApprovalsReviewers: [String]? = nil,
        allowedSandboxModes: [String]? = nil,
        allowedWindowsSandboxImplementations: [String]? = nil,
        allowedPermissionProfiles: [String: Bool]? = nil,
        defaultPermissions: String? = nil,
        allowedWebSearchModes: [String]? = nil,
        allowManagedHooksOnly: Bool? = nil,
        allowAppshots: Bool? = nil,
        allowRemoteControl: Bool? = nil,
        computerUse: ManagedComputerUseRequirements? = nil,
        featureRequirements: [String: Bool]? = nil,
        hooks: ManagedHookRequirements? = nil,
        enforceResidency: String? = nil,
        network: ManagedNetworkRequirements? = nil
    ) {
        self.allowedApprovalPolicies = allowedApprovalPolicies
        self.allowedApprovalsReviewers = allowedApprovalsReviewers
        self.allowedSandboxModes = allowedSandboxModes
        self.allowedWindowsSandboxImplementations = allowedWindowsSandboxImplementations
        self.allowedPermissionProfiles = allowedPermissionProfiles
        self.defaultPermissions = defaultPermissions
        self.allowedWebSearchModes = allowedWebSearchModes
        self.allowManagedHooksOnly = allowManagedHooksOnly
        self.allowAppshots = allowAppshots
        self.allowRemoteControl = allowRemoteControl
        self.computerUse = computerUse
        self.featureRequirements = featureRequirements
        self.hooks = hooks
        self.enforceResidency = enforceResidency
        self.network = network
    }

    public var effectiveDefaultPermissions: String? {
        guard let allowedPermissionProfiles else { return nil }
        if let defaultPermissions { return defaultPermissions }
        let supportsStandardPair = allowedPermissionProfiles[":read-only"] == true
            && allowedPermissionProfiles[":workspace"] == true
        return supportsStandardPair ? ":workspace" : nil
    }

    public func allowsSandboxMode(_ mode: String) -> Bool {
        allowedSandboxModes?.contains(mode) ?? true
    }

    public func allowsPermissionProfile(_ identifier: String, sandboxMode: String) -> Bool {
        let allowedByIdentifier = allowedPermissionProfiles?[identifier]
            ?? (allowedPermissionProfiles == nil)
        return allowedByIdentifier && allowsSandboxMode(sandboxMode)
    }

    public func allowsApprovalPolicy(_ policy: ManagedApprovalPolicy) -> Bool {
        allowedApprovalPolicies?.contains(policy) ?? true
    }

    public func allowsApprovalsReviewer(_ reviewer: String) -> Bool {
        guard let allowedApprovalsReviewers else { return true }
        let canonicalReviewer = Self.canonicalApprovalsReviewer(reviewer)
        return allowedApprovalsReviewers.contains {
            Self.canonicalApprovalsReviewer($0) == canonicalReviewer
        }
    }

    private static func canonicalApprovalsReviewer(_ reviewer: String) -> String {
        reviewer == "guardian_subagent" ? "auto_review" : reviewer
    }
}

public struct ManagedRequirementsLoadError: Error, CustomStringConvertible, Sendable, Equatable {
    public var path: String
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    public var description: String {
        path.isEmpty ? reason : "\(path): \(reason)"
    }
}

public enum ManagedRequirementsLoader {
    public static func load(from paths: HookConfigurationPaths) throws -> ManagedRequirements? {
        var merged = ConfigDocument()
        var foundDocument = false
        for file in paths.managedRequirementFiles {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            foundDocument = true
            do {
                merged.merge(overridingWith: try ConfigDocumentStore(fileURL: file).load())
            } catch {
                throw ManagedRequirementsLoadError(
                    path: file.path,
                    reason: error.localizedDescription
                )
            }
        }
        guard foundDocument, !merged.values.isEmpty else { return nil }
        return try ManagedRequirementsDecoder(values: merged.values).decode()
    }
}
