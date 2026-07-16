import Foundation
import QuillCodePersistence

extension AppServerSession {
    func listPermissionProfiles(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        _ = try resolvedCWD(try params.optionalString("cwd"), fallback: currentDirectory)
        let requirements = try managedRequirements()
        let profiles = [":read-only", ":workspace", ":danger-full-access"].map { identifier in
            let sandboxMode = ManagedRequirements.builtInPermissionProfiles[identifier] ?? "read-only"
            return CLIJSONValue.object([
                "id": .string(identifier),
                "description": .null,
                "allowed": .bool(
                    requirements?.allowsPermissionProfile(identifier, sandboxMode: sandboxMode)
                        ?? true
                )
            ])
        }

        let requestedLimit = try params.optionalInt("limit")
        if let requestedLimit, requestedLimit < 0 {
            throw AppServerRPCError.invalidParams("limit must be an unsigned integer or null")
        }
        let limit = min(max(requestedLimit ?? profiles.count, 1), profiles.count)
        let start = try Self.permissionProfileCursorOffset(
            try params.optionalString("cursor"),
            total: profiles.count
        )
        let end = min(start + limit, profiles.count)
        return .object([
            "data": .array(Array(profiles[start..<end])),
            "nextCursor": end < profiles.count ? .string(String(end)) : .null
        ])
    }

    func listCollaborationModes(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        guard experimentalAPIEnabled else {
            throw AppServerRPCError.invalidRequest(
                "collaborationMode/list requires experimentalApi capability"
            )
        }
        _ = try AppServerParams(raw)
        return .object([
            "data": .array([
                .object([
                    "name": .string("Plan"),
                    "mode": .string("plan"),
                    "model": .null,
                    "reasoning_effort": .string("medium")
                ]),
                .object([
                    "name": .string("Default"),
                    "mode": .string("default"),
                    "model": .null,
                    "reasoning_effort": .null
                ])
            ])
        ])
    }

    func readConfigRequirements(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        _ = try AppServerParams(raw)
        guard let requirements = try managedRequirements() else {
            return .object(["requirements": .null])
        }
        return .object([
            "requirements": requirements.appServerProjection(
                includesExperimentalFields: experimentalAPIEnabled
            )
        ])
    }

    func managedRequirements() throws -> ManagedRequirements? {
        do {
            return try ManagedRequirementsLoader.load(from: paths.hookConfigurationPaths)
        } catch {
            throw AppServerRPCError.internalError(
                "failed to load managed requirements: \(String(describing: error))"
            )
        }
    }

    func permissionProfileMode(_ identifier: String) throws -> CLISandboxMode {
        switch identifier {
        case ":read-only": .readOnly
        case ":workspace": .workspaceWrite
        case ":danger-full-access": .dangerFullAccess
        default:
            throw AppServerRPCError.invalidRequest(
                "failed to load configuration: default_permissions refers to "
                    + "unknown built-in profile `\(identifier)`"
            )
        }
    }

    func validateManagedPermissionProfile(
        _ identifier: String,
        mode: CLISandboxMode,
        against requirements: ManagedRequirements?
    ) throws {
        guard let requirements else { return }
        let sandboxMode = Self.sandboxModeIdentifier(mode)
        guard requirements.allowsPermissionProfile(identifier, sandboxMode: sandboxMode) else {
            throw AppServerRPCError.invalidRequest(
                "permission profile `\(identifier)` is disallowed by managed requirements"
            )
        }
    }

    func validateManagedSandboxMode(
        _ mode: CLISandboxMode,
        against requirements: ManagedRequirements?
    ) throws {
        try validateManagedPermissionProfile(
            Self.permissionProfileIdentifier(mode),
            mode: mode,
            against: requirements
        )
    }

    func validateManagedApprovalPolicy(
        _ value: CLIJSONValue,
        against requirements: ManagedRequirements?
    ) throws {
        guard let requirements,
              let policies = requirements.allowedApprovalPolicies else { return }
        let candidate = try managedApprovalPolicy(value)
        guard policies.contains(candidate) else {
            throw AppServerRPCError.invalidRequest(
                "approval policy is disallowed by managed requirements"
            )
        }
    }

    func validateManagedApprovalsReviewer(
        _ reviewer: String,
        against requirements: ManagedRequirements?
    ) throws {
        guard let requirements,
              !requirements.allowsApprovalsReviewer(reviewer) else { return }
        throw AppServerRPCError.invalidRequest(
            "approvals reviewer `\(reviewer)` is disallowed by managed requirements"
        )
    }

    func managedApprovalPolicy(_ value: CLIJSONValue) throws -> ManagedApprovalPolicy {
        if let name = value.stringValue { return .named(name) }
        guard let granular = value.objectValue?["granular"]?.objectValue,
              let sandboxApproval = granular["sandbox_approval"]?.boolValue,
              let rules = granular["rules"]?.boolValue,
              let mcpElicitations = granular["mcp_elicitations"]?.boolValue else {
            throw AppServerRPCError.invalidRequest("invalid granular approval policy")
        }
        return .granular(ManagedGranularApprovalPolicy(
            sandboxApproval: sandboxApproval,
            rules: rules,
            mcpElicitations: mcpElicitations,
            skillApproval: granular["skill_approval"]?.boolValue ?? false,
            requestPermissions: granular["request_permissions"]?.boolValue ?? false
        ))
    }

    static func permissionProfileIdentifier(_ mode: CLISandboxMode) -> String {
        switch mode {
        case .readOnly: ":read-only"
        case .workspaceWrite: ":workspace"
        case .dangerFullAccess: ":danger-full-access"
        }
    }

    static func sandboxModeIdentifier(_ mode: CLISandboxMode) -> String {
        switch mode {
        case .readOnly: "read-only"
        case .workspaceWrite: "workspace-write"
        case .dangerFullAccess: "danger-full-access"
        }
    }

    private static func permissionProfileCursorOffset(
        _ cursor: String?,
        total: Int
    ) throws -> Int {
        guard let cursor else { return 0 }
        guard let offset = Int(cursor), offset >= 0 else {
            throw AppServerRPCError.invalidRequest("invalid cursor: \(cursor)")
        }
        guard offset <= total else {
            throw AppServerRPCError.invalidRequest(
                "cursor \(offset) exceeds total permission profiles \(total)"
            )
        }
        return offset
    }
}

private extension ManagedRequirements {
    func appServerProjection(includesExperimentalFields: Bool) -> CLIJSONValue {
        var result: [String: CLIJSONValue] = [
            "allowedApprovalPolicies": optionalArray(allowedApprovalPolicies?.map(\.appServerProjection)),
            "allowedSandboxModes": optionalStrings(allowedSandboxModes),
            "allowedWindowsSandboxImplementations": optionalStrings(
                allowedWindowsSandboxImplementations
            ),
            "allowedPermissionProfiles": optionalBools(allowedPermissionProfiles),
            "defaultPermissions": optionalString(defaultPermissions),
            "allowedWebSearchModes": optionalStrings(allowedWebSearchModes),
            "allowManagedHooksOnly": optionalBool(allowManagedHooksOnly),
            "allowAppshots": optionalBool(allowAppshots),
            "allowRemoteControl": optionalBool(allowRemoteControl),
            "computerUse": computerUse?.appServerProjection ?? .null,
            "featureRequirements": optionalBools(featureRequirements),
            "enforceResidency": optionalString(enforceResidency)
        ]
        if includesExperimentalFields {
            result["allowedApprovalsReviewers"] = optionalStrings(allowedApprovalsReviewers)
            result["hooks"] = hooks?.appServerProjection ?? .null
            result["network"] = network?.appServerProjection ?? .null
        }
        return .object(result)
    }

    private func optionalArray(_ value: [CLIJSONValue]?) -> CLIJSONValue {
        value.map(CLIJSONValue.array) ?? .null
    }

    private func optionalStrings(_ value: [String]?) -> CLIJSONValue {
        value.map { .array($0.map(CLIJSONValue.string)) } ?? .null
    }

    private func optionalBools(_ value: [String: Bool]?) -> CLIJSONValue {
        value.map { .object($0.mapValues(CLIJSONValue.bool)) } ?? .null
    }

    private func optionalString(_ value: String?) -> CLIJSONValue {
        value.map(CLIJSONValue.string) ?? .null
    }

    private func optionalBool(_ value: Bool?) -> CLIJSONValue {
        value.map(CLIJSONValue.bool) ?? .null
    }
}

private extension ManagedApprovalPolicy {
    var appServerProjection: CLIJSONValue {
        switch self {
        case .named(let value): .string(value)
        case .granular(let value):
            .object(["granular": .object([
                "sandbox_approval": .bool(value.sandboxApproval),
                "rules": .bool(value.rules),
                "mcp_elicitations": .bool(value.mcpElicitations),
                "skill_approval": .bool(value.skillApproval),
                "request_permissions": .bool(value.requestPermissions)
            ])])
        }
    }
}

private extension ManagedComputerUseRequirements {
    var appServerProjection: CLIJSONValue {
        .object([
            "allowLockedComputerUse": allowLockedComputerUse.map(CLIJSONValue.bool) ?? .null
        ])
    }
}

private extension ManagedHookRequirements {
    var appServerProjection: CLIJSONValue {
        var result = Dictionary(uniqueKeysWithValues: Self.eventNames.map { event in
            (
                event,
                CLIJSONValue.array((events[event] ?? []).map(\.appServerProjection))
            )
        })
        result["managedDir"] = managedDirectory.map(CLIJSONValue.string) ?? .null
        result["windowsManagedDir"] = windowsManagedDirectory.map(CLIJSONValue.string) ?? .null
        return .object(result)
    }
}

private extension ManagedHookMatcherGroup {
    var appServerProjection: CLIJSONValue {
        .object([
            "matcher": matcher.map(CLIJSONValue.string) ?? .null,
            "hooks": .array(hooks.map(\.appServerProjection))
        ])
    }
}

private extension ManagedHookHandler {
    var appServerProjection: CLIJSONValue {
        switch self {
        case .prompt: .object(["type": .string("prompt")])
        case .agent: .object(["type": .string("agent")])
        case .command(let value):
            .object([
                "type": .string("command"),
                "command": .string(value.command),
                "commandWindows": value.commandWindows.map(CLIJSONValue.string) ?? .null,
                "timeoutSec": value.timeoutSeconds.map { .number(Double($0)) } ?? .null,
                "async": .bool(value.isAsync),
                "statusMessage": value.statusMessage.map(CLIJSONValue.string) ?? .null
            ])
        }
    }
}

private extension ManagedNetworkRequirements {
    var appServerProjection: CLIJSONValue {
        .object([
            "enabled": enabled.map(CLIJSONValue.bool) ?? .null,
            "httpPort": httpPort.map { .number(Double($0)) } ?? .null,
            "socksPort": socksPort.map { .number(Double($0)) } ?? .null,
            "allowUpstreamProxy": allowUpstreamProxy.map(CLIJSONValue.bool) ?? .null,
            "dangerouslyAllowNonLoopbackProxy": dangerouslyAllowNonLoopbackProxy
                .map(CLIJSONValue.bool) ?? .null,
            "dangerouslyAllowAllUnixSockets": dangerouslyAllowAllUnixSockets
                .map(CLIJSONValue.bool) ?? .null,
            "domains": domains.map { .object($0.mapValues(CLIJSONValue.string)) } ?? .null,
            "managedAllowedDomainsOnly": managedAllowedDomainsOnly.map(CLIJSONValue.bool) ?? .null,
            "allowedDomains": allowedDomains.map { .array($0.map(CLIJSONValue.string)) } ?? .null,
            "deniedDomains": deniedDomains.map { .array($0.map(CLIJSONValue.string)) } ?? .null,
            "unixSockets": unixSockets.map {
                .object($0.mapValues(CLIJSONValue.string))
            } ?? .null,
            "allowUnixSockets": allowedUnixSockets.map {
                .array($0.map(CLIJSONValue.string))
            } ?? .null,
            "allowLocalBinding": allowLocalBinding.map(CLIJSONValue.bool) ?? .null
        ])
    }
}
