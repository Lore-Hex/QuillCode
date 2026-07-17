import Foundation
import QuillCodeCore
import QuillCodePersistence

extension AppServerSession {
    func validateTrustedRouterProvider(in params: AppServerParams) throws {
        guard let provider = try params.optionalString("modelProvider") else { return }
        guard provider == "trustedrouter" else {
            throw AppServerRPCError.invalidParams(
                "modelProvider must be trustedrouter for the QuillCode app server"
            )
        }
    }

    func model(
        from params: AppServerParams,
        fallback: String
    ) throws -> String {
        guard let model = try params.optionalString("model") else { return fallback }
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AppServerRPCError.invalidParams("model must be a non-empty string")
        }
        return normalized
    }

    func rejectUnsupportedValues(
        _ keys: [String],
        in params: AppServerParams
    ) throws {
        let unsupported = keys.filter { key in
            guard let value = params.object[key] else { return false }
            return value != .null
        }
        guard unsupported.isEmpty else {
            throw AppServerRPCError.invalidParams(
                "unsupported app-server fields: \(unsupported.sorted().joined(separator: ", "))"
            )
        }
    }

    func loadRecord(_ id: UUID) async throws -> AppServerThreadRecord {
        do {
            return try await repository.load(id)
        } catch {
            let identifier = id.uuidString.lowercased()
            throw AppServerRPCError.invalidParams("thread \(identifier) was not found")
        }
    }

    func threadSettings(
        from params: AppServerParams,
        base: AppServerThreadSettings?,
        requirements: ManagedRequirements?
    ) throws -> AppServerThreadSettings {
        let cwd = try resolvedCWD(
            try params.optionalString("cwd"),
            fallback: base?.cwd ?? currentDirectory
        )
        let sandboxValue = params.object["sandbox"] ?? params.object["sandboxPolicy"]
        let permissionsValue = params.object["permissions"]
        if sandboxValue != nil, sandboxValue != .null,
           permissionsValue != nil, permissionsValue != .null {
            throw AppServerRPCError.invalidRequest(
                "`permissions` cannot be combined with `sandbox`"
            )
        }

        var sandbox = base?.sandbox ?? .readOnly
        var sandboxPolicy = base?.sandboxPolicy
        var permissionProfileID = base?.permissionProfileID
        var permissionProfileIsExplicit = base?.permissionProfileIsExplicit
        if let permissionsValue, permissionsValue != .null {
            guard let identifier = permissionsValue.stringValue else {
                throw AppServerRPCError.invalidParams("permissions must be a string or null")
            }
            sandbox = try permissionProfileMode(identifier)
            try validateManagedPermissionProfile(identifier, mode: sandbox, against: requirements)
            sandboxPolicy = AppServerSandboxPolicy(mode: sandbox)
            permissionProfileID = identifier
            permissionProfileIsExplicit = true
        } else if let sandboxValue, sandboxValue != .null {
            sandbox = try sandboxMode(sandboxValue) ?? sandbox
            try validateManagedSandboxMode(sandbox, against: requirements)
            sandboxPolicy = nil
            permissionProfileID = nil
            permissionProfileIsExplicit = nil
        }
        if let permissionProfileID {
            try validateManagedPermissionProfile(
                permissionProfileID,
                mode: sandbox,
                against: requirements
            )
        } else {
            try validateManagedSandboxMode(sandbox, against: requirements)
        }
        let approvalPolicy = try approvalPolicy(params.object["approvalPolicy"])
            ?? base?.approvalPolicy
            ?? .string("on-request")
        try validateManagedApprovalPolicy(approvalPolicy, against: requirements)
        let requestedReviewer = try params.optionalString("approvalsReviewer")
            ?? base?.approvalsReviewer
            ?? "user"
        guard ["user", "auto_review", "guardian_subagent"].contains(requestedReviewer) else {
            throw AppServerRPCError.invalidParams("approvalsReviewer is not supported")
        }
        try validateManagedApprovalsReviewer(requestedReviewer, against: requirements)
        return AppServerThreadSettings(
            cwd: cwd,
            ephemeral: try params.optionalBool("ephemeral") ?? base?.ephemeral ?? false,
            approvalPolicy: approvalPolicy,
            approvalsReviewer: requestedReviewer,
            sandbox: sandbox,
            sessionID: base?.sessionID,
            forkedFromID: base?.forkedFromID,
            runtimeAppConfig: base?.runtimeAppConfig,
            compactPrompt: base?.compactPrompt,
            name: base?.name,
            gitInfo: base?.gitInfo,
            reasoningEffort: base?.reasoningEffort,
            reasoningSummary: base?.reasoningSummary,
            serviceTier: base?.serviceTier,
            collaborationMode: base?.collaborationMode,
            memoryMode: base?.memoryMode,
            sandboxPolicy: sandboxPolicy,
            permissionProfileID: permissionProfileID,
            permissionProfileIsExplicit: permissionProfileIsExplicit,
            userShellTurns: base?.userShellTurns,
            environments: base?.environments
        )
    }

    func resolvedCWD(_ value: String?, fallback: URL) throws -> URL {
        let candidate: URL
        if let value, !value.isEmpty {
            candidate = NSString(string: value).isAbsolutePath
                ? URL(fileURLWithPath: value)
                : fallback.appendingPathComponent(value)
        } else {
            candidate = fallback
        }
        let normalized = candidate.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AppServerRPCError.invalidParams("cwd must name an existing directory")
        }
        return normalized
    }

    func sandboxMode(_ value: CLIJSONValue?) throws -> CLISandboxMode? {
        guard let value, value != .null else { return nil }
        let raw = value.stringValue ?? value.objectValue?["type"]?.stringValue
        switch raw {
        case nil:
            throw AppServerRPCError.invalidParams("sandbox must be a string or policy object")
        case "read-only", "readOnly":
            return .readOnly
        case "workspace-write", "workspaceWrite":
            return .workspaceWrite
        case "danger-full-access", "dangerFullAccess":
            return .dangerFullAccess
        default:
            throw AppServerRPCError.invalidParams("unsupported sandbox policy")
        }
    }

    func approvalPolicy(_ value: CLIJSONValue?) throws -> CLIJSONValue? {
        guard let value, value != .null else { return nil }
        if let string = value.stringValue {
            guard ["untrusted", "on-failure", "on-request", "never"].contains(string) else {
                throw AppServerRPCError.invalidParams("approvalPolicy is not supported")
            }
            return value
        }
        guard let granular = value.objectValue?["granular"]?.objectValue else {
            throw AppServerRPCError.invalidParams(
                "approvalPolicy must be a supported string or granular policy"
            )
        }
        let required = [
            "sandbox_approval",
            "rules",
            "mcp_elicitations"
        ]
        let optional = ["skill_approval", "request_permissions"]
        guard Set(granular.keys).isSubset(of: Set(required + optional)),
              required.allSatisfy({ granular[$0]?.boolValue != nil }) else {
            throw AppServerRPCError.invalidParams(
                "approvalPolicy.granular must contain the three required boolean fields"
            )
        }
        guard optional.allSatisfy({ granular[$0] == nil || granular[$0]?.boolValue != nil }) else {
            throw AppServerRPCError.invalidParams(
                "approvalPolicy.granular optional fields must be booleans"
            )
        }
        var normalized = granular
        optional.forEach { normalized[$0] = normalized[$0] ?? .bool(false) }
        return .object(["granular": .object(normalized)])
    }

    func mode(for settings: AppServerThreadSettings) -> AgentMode {
        if settings.sandbox == .readOnly { return .readOnly }
        if settings.approvalsReviewer != "user" || settings.approvalPolicy.stringValue == "never" {
            return .auto
        }
        return .review
    }

    func defaultThreadSettings(
        requirements: ManagedRequirements?
    ) throws -> AppServerThreadSettings {
        let access: (sandbox: CLISandboxMode, reviewer: String)
        switch appConfig.mode {
        case .auto:
            access = (.workspaceWrite, "auto_review")
        case .review:
            access = (.workspaceWrite, "user")
        case .readOnly, .plan:
            access = (.readOnly, "user")
        }
        let approvalPolicy = requirements?.allowedApprovalPolicies?.first
            .map { Self.appServerApprovalPolicy($0) } ?? .string("on-request")
        let reviewer = requirements?.allowedApprovalsReviewers?.first ?? access.reviewer

        let permissionProfileID: String?
        let sandbox: CLISandboxMode
        if let managedDefault = requirements?.effectiveDefaultPermissions {
            permissionProfileID = managedDefault
            sandbox = try permissionProfileMode(managedDefault)
        } else if requirements?.allowsPermissionProfile(
            Self.permissionProfileIdentifier(access.sandbox),
            sandboxMode: Self.sandboxModeIdentifier(access.sandbox)
        ) != false {
            permissionProfileID = nil
            sandbox = access.sandbox
        } else {
            permissionProfileID = ":read-only"
            sandbox = .readOnly
        }
        return AppServerThreadSettings(
            cwd: currentDirectory,
            ephemeral: false,
            approvalPolicy: approvalPolicy,
            approvalsReviewer: reviewer,
            sandbox: sandbox,
            forkedFromID: nil,
            sandboxPolicy: permissionProfileID.map { _ in AppServerSandboxPolicy(mode: sandbox) },
            permissionProfileID: permissionProfileID,
            permissionProfileIsExplicit: permissionProfileID == nil ? nil : true
        )
    }

    private static func appServerApprovalPolicy(_ policy: ManagedApprovalPolicy) -> CLIJSONValue {
        switch policy {
        case .named(let name): .string(name)
        case .granular(let policy):
            .object(["granular": .object([
                "sandbox_approval": .bool(policy.sandboxApproval),
                "rules": .bool(policy.rules),
                "mcp_elicitations": .bool(policy.mcpElicitations),
                "skill_approval": .bool(policy.skillApproval),
                "request_permissions": .bool(policy.requestPermissions)
            ])])
        }
    }

    func appendInstructions(from params: AppServerParams, to thread: inout ChatThread) throws {
        for key in ["baseInstructions", "developerInstructions"] {
            guard let value = try params.optionalString(key),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            thread.messages.append(ChatMessage(role: .system, content: value))
        }
    }
}
