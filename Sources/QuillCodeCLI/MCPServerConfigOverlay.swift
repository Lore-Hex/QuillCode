import Foundation
import QuillCodeCore

struct MCPServerEffectiveRunConfiguration: Sendable {
    var appConfig: AppConfig
    var model: String
    var sandbox: CLISandboxMode
    var approvalPolicy: MCPServerApprovalPolicy
    var approvalsReviewer: String
}

enum MCPServerConfigOverlay {
    static func resolve(
        input: MCPServerRunInput,
        base: AppConfig,
        serverModel: String?
    ) throws -> MCPServerEffectiveRunConfiguration {
        var raw = input.config
        let configModel = try takeString(["model", "default_model", "defaultModel"], from: &raw)
        let configSandbox = try takeString(["sandbox_mode", "sandbox"], from: &raw)
        let configApproval = try takeString(["approval_policy", "approval-policy"], from: &raw)
        if let provider = try takeString(["model_provider"], from: &raw), provider != "trustedrouter" {
            throw MCPServerToolInputError.invalid("model_provider must be trustedrouter")
        }

        let appConfig = try applying(raw, to: base)
        let model = input.model ?? configModel ?? serverModel ?? appConfig.defaultModel
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPServerToolInputError.invalid("model must be a non-empty string")
        }

        let sandbox: CLISandboxMode
        if let explicit = input.sandbox {
            sandbox = explicit
        } else if let configSandbox {
            guard let value = CLISandboxMode(rawValue: configSandbox) else {
                throw MCPServerToolInputError.invalid("sandbox_mode is not supported")
            }
            sandbox = value
        } else {
            switch appConfig.mode {
            case .auto, .review: sandbox = .workspaceWrite
            case .readOnly, .plan: sandbox = .readOnly
            }
        }

        let approvalPolicy: MCPServerApprovalPolicy
        if let explicit = input.approvalPolicy {
            approvalPolicy = explicit
        } else if let configApproval {
            guard let configured = MCPServerApprovalPolicy(rawValue: configApproval) else {
                throw MCPServerToolInputError.invalid("approval_policy is not supported")
            }
            approvalPolicy = configured
        } else {
            approvalPolicy = .onRequest
        }
        let hasExplicitApprovalPolicy = input.approvalPolicy != nil || configApproval != nil
        let reviewer: String
        if approvalPolicy == .never {
            reviewer = "auto_review"
        } else if hasExplicitApprovalPolicy {
            reviewer = "user"
        } else {
            reviewer = appConfig.mode == .auto ? "auto_review" : "user"
        }
        return MCPServerEffectiveRunConfiguration(
            appConfig: appConfig,
            model: model,
            sandbox: sandbox,
            approvalPolicy: approvalPolicy,
            approvalsReviewer: reviewer
        )
    }

    private static func applying(
        _ overrides: [String: CLIJSONValue],
        to base: AppConfig
    ) throws -> AppConfig {
        guard !overrides.isEmpty else { return base }
        let aliases = [
            "api_base_url": "apiBaseURL",
            "base_url": "apiBaseURL",
            "max_tool_steps": "maxToolSteps",
            "run_spend_fuse_usd": "runSpendFuseUSD",
            "run_spend_period_limits": "runSpendPeriodLimits",
            "favorite_models": "favoriteModels",
            "browser_allowed_domains": "browserAllowedDomains",
            "browser_blocked_domains": "browserBlockedDomains",
            "computer_use_approved_bundle_identifiers": "computerUseApprovedBundleIdentifiers",
            "computer_use_approved_app_names": "computerUseApprovedAppNames",
            "notification_preferences": "notificationPreferences",
            "managed_worktrees": "managedWorktrees",
            "keyboard_shortcuts": "keyboardShortcuts",
            "skill_configuration": "skillConfiguration",
            "default_personality": "defaultPersonality",
            "review_model": "reviewModel",
            "review_delivery": "reviewDelivery",
            "auth_mode": "authMode"
        ]
        let allowed = Set([
            "apiBaseURL", "maxToolSteps", "runSpendFuseUSD", "favoriteModels",
            "browserAllowedDomains", "browserBlockedDomains", "skillConfiguration",
            "defaultPersonality", "mode", "runSpendPeriodLimits",
            "computerUseApprovedBundleIdentifiers", "computerUseApprovedAppNames",
            "notificationPreferences", "managedWorktrees", "keyboardShortcuts",
            "reviewModel", "reviewDelivery", "authMode"
        ])
        var normalized: [String: CLIJSONValue] = [:]
        for (key, value) in overrides {
            let destination = aliases[key] ?? key
            guard allowed.contains(destination) else {
                throw MCPServerToolInputError.invalid("unsupported config override: \(key)")
            }
            guard normalized[destination] == nil else {
                throw MCPServerToolInputError.invalid("duplicate config override: \(destination)")
            }
            normalized[destination] = value
        }

        let encoder = JSONEncoder()
        let baseValue = try JSONDecoder().decode(
            CLIJSONValue.self,
            from: encoder.encode(base)
        )
        guard var object = baseValue.objectValue else {
            throw MCPServerToolInputError.invalid("could not encode the base QuillCode config")
        }
        object.merge(normalized) { _, override in override }
        do {
            return try JSONDecoder().decode(
                AppConfig.self,
                from: encoder.encode(CLIJSONValue.object(object))
            )
        } catch {
            throw MCPServerToolInputError.invalid("invalid config override: \(error.localizedDescription)")
        }
    }

    private static func takeString(
        _ keys: [String],
        from object: inout [String: CLIJSONValue]
    ) throws -> String? {
        let present = keys.filter { object[$0] != nil }
        guard present.count <= 1 else {
            throw MCPServerToolInputError.invalid(
                "conflicting config aliases: \(present.sorted().joined(separator: ", "))"
            )
        }
        guard let key = present.first, let value = object.removeValue(forKey: key) else { return nil }
        guard value != .null else { return nil }
        guard let string = value.stringValue else {
            throw MCPServerToolInputError.invalid("config.\(key) must be a string")
        }
        return string
    }
}
