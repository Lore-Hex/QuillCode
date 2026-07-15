import Foundation
import QuillCodeCore

extension AppServerSession {
    func readConfig(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let includeLayers = try params.optionalBool("includeLayers") ?? false
        _ = try resolvedCWD(try params.optionalString("cwd"), fallback: currentDirectory)

        let config = effectiveConfig
        let layers: CLIJSONValue
        if includeLayers, FileManager.default.fileExists(atPath: paths.configFile.path) {
            layers = .array([.object([
                "name": .object([
                    "type": .string("user"),
                    "file": .string(paths.configFile.path),
                    "profile": .null
                ]),
                "version": .string(Self.configVersion(paths.configFile)),
                "config": config,
                "disabledReason": .null
            ])])
        } else {
            layers = .null
        }
        return .object([
            "config": config,
            "origins": .object([:]),
            "layers": layers
        ])
    }

    private var effectiveConfig: CLIJSONValue {
        let access: (sandbox: String, reviewer: String)
        switch appConfig.mode {
        case .auto:
            access = ("workspace-write", "auto_review")
        case .review:
            access = ("workspace-write", "user")
        case .readOnly, .plan:
            access = ("read-only", "user")
        }
        return .object([
            "model": .string(request.model ?? appConfig.defaultModel),
            "review_model": appConfig.reviewModel.map(CLIJSONValue.string) ?? .null,
            "model_context_window": .null,
            "model_auto_compact_token_limit": .null,
            "model_auto_compact_token_limit_scope": .null,
            "model_provider": .string("trustedrouter"),
            "approval_policy": .string("on-request"),
            "approvals_reviewer": .string(access.reviewer),
            "sandbox_mode": .string(access.sandbox),
            "sandbox_workspace_write": .null,
            "forced_chatgpt_workspace_id": .null,
            "forced_login_method": .null,
            "web_search": .string("live"),
            "tools": .null,
            "instructions": .null,
            "developer_instructions": .null,
            "compact_prompt": .null,
            "model_reasoning_effort": .null,
            "model_reasoning_summary": .null,
            "model_verbosity": .null,
            "service_tier": .null,
            "analytics": .null,
            "desktop": .null
        ])
    }

    private static func configVersion(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "unknown"
        }
        let timestamp = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return "mtime:\(Int(timestamp));size:\(size)"
    }
}
