import Foundation
import QuillCodeCore

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
        base: AppServerThreadSettings?
    ) throws -> AppServerThreadSettings {
        let cwd = try resolvedCWD(
            try params.optionalString("cwd"),
            fallback: base?.cwd ?? currentDirectory
        )
        let sandbox = try sandboxMode(params.object["sandbox"] ?? params.object["sandboxPolicy"])
            ?? base?.sandbox
            ?? .readOnly
        let approvalPolicy = try approvalPolicy(params.object["approvalPolicy"])
            ?? base?.approvalPolicy
            ?? .string("on-request")
        let reviewer = try params.optionalString("approvalsReviewer")
            ?? base?.approvalsReviewer
            ?? "user"
        guard ["user", "auto_review", "guardian_subagent"].contains(reviewer) else {
            throw AppServerRPCError.invalidParams("approvalsReviewer is not supported")
        }
        return AppServerThreadSettings(
            cwd: cwd,
            ephemeral: try params.optionalBool("ephemeral") ?? base?.ephemeral ?? false,
            approvalPolicy: approvalPolicy,
            approvalsReviewer: reviewer,
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
            sandboxPolicy: base?.sandboxPolicy,
            permissionProfileID: base?.permissionProfileID,
            permissionProfileIsExplicit: base?.permissionProfileIsExplicit
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

    func defaultThreadSettings() -> AppServerThreadSettings {
        let access: (sandbox: CLISandboxMode, reviewer: String)
        switch appConfig.mode {
        case .auto:
            access = (.workspaceWrite, "auto_review")
        case .review:
            access = (.workspaceWrite, "user")
        case .readOnly, .plan:
            access = (.readOnly, "user")
        }
        return AppServerThreadSettings(
            cwd: currentDirectory,
            ephemeral: false,
            approvalPolicy: .string("on-request"),
            approvalsReviewer: access.reviewer,
            sandbox: access.sandbox,
            forkedFromID: nil
        )
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
