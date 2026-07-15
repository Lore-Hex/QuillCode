import Foundation
import QuillCodeCore
import QuillCodePersistence

extension AppServerSession {
    func readConfig(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let includeLayers = try params.optionalBool("includeLayers") ?? false
        _ = try resolvedCWD(try params.optionalString("cwd"), fallback: currentDirectory)

        let snapshot: ConfigDocumentSnapshot
        do {
            snapshot = try ConfigDocumentStore(fileURL: paths.configFile).loadSnapshot()
        } catch {
            throw AppServerRPCError.internalError(
                "failed to read configuration: \(error.localizedDescription)"
            )
        }

        let version = Self.configVersion(snapshot.bytes)
        let currentConfig = (try? ConfigStore(fileURL: paths.configFile).load()) ?? appConfig
        var origins = Self.userOrigins(
            document: snapshot.document,
            file: paths.configFile,
            version: version
        )
        if request.model != nil {
            origins["model"] = Self.sessionOrigin
        }

        var response: [String: CLIJSONValue] = [
            "config": effectiveConfig(document: snapshot.document, appConfig: currentConfig),
            "origins": .object(origins)
        ]
        if includeLayers {
            if FileManager.default.fileExists(atPath: paths.configFile.path) {
                response["layers"] = .array([.object([
                    "name": Self.userLayerName(file: paths.configFile),
                    "version": .string(version),
                    "config": .object(snapshot.document.values.mapValues(\.jsonValue))
                ])])
            } else {
                response["layers"] = .array([])
            }
        }
        return .object(response)
    }

    private func effectiveConfig(
        document: ConfigDocument,
        appConfig: AppConfig
    ) -> CLIJSONValue {
        var values = document.values.mapValues(\.jsonValue)
        let access: (sandbox: String, reviewer: String)
        switch appConfig.mode {
        case .auto:
            access = ("workspace-write", "auto_review")
        case .review:
            access = ("workspace-write", "user")
        case .readOnly, .plan:
            access = ("read-only", "user")
        }

        values["model"] = .string(request.model ?? appConfig.defaultModel)
        values.setDefault("review_model", to: appConfig.reviewModel.map(CLIJSONValue.string) ?? .null)
        values.setDefault("model_context_window", to: .null)
        values.setDefault("model_auto_compact_token_limit", to: .null)
        values.setDefault("model_auto_compact_token_limit_scope", to: .null)
        values.setDefault("model_provider", to: .string("trustedrouter"))
        values.setDefault("approval_policy", to: .string("on-request"))
        values.setDefault("approvals_reviewer", to: .string(access.reviewer))
        values.setDefault("sandbox_mode", to: .string(access.sandbox))
        values.setDefault("sandbox_workspace_write", to: .null)
        values.setDefault("forced_chatgpt_workspace_id", to: .null)
        values.setDefault("forced_login_method", to: .null)
        values.setDefault("web_search", to: .string("live"))
        values.setDefault("tools", to: .null)
        values.setDefault("instructions", to: .null)
        values.setDefault("developer_instructions", to: .null)
        values.setDefault("compact_prompt", to: .null)
        values.setDefault("model_reasoning_effort", to: .null)
        values.setDefault("model_reasoning_summary", to: .null)
        values.setDefault("model_verbosity", to: .null)
        values.setDefault("service_tier", to: .null)
        values.setDefault("analytics", to: .null)
        values.setDefault("desktop", to: .null)
        return .object(values)
    }

    private static func userOrigins(
        document: ConfigDocument,
        file: URL,
        version: String
    ) -> [String: CLIJSONValue] {
        let metadata: CLIJSONValue = .object([
            "name": userLayerName(file: file),
            "version": .string(version)
        ])
        var origins: [String: CLIJSONValue] = [:]
        for key in document.values.keys.sorted() {
            guard let value = document.values[key] else { continue }
            appendOrigins(value: value, path: key, metadata: metadata, to: &origins)
        }
        return origins
    }

    private static func appendOrigins(
        value: ConfigValue,
        path: String,
        metadata: CLIJSONValue,
        to origins: inout [String: CLIJSONValue]
    ) {
        switch value {
        case .object(let object) where !object.isEmpty:
            for key in object.keys.sorted() {
                guard let child = object[key] else { continue }
                appendOrigins(
                    value: child,
                    path: "\(path).\(key)",
                    metadata: metadata,
                    to: &origins
                )
            }
        case .array(let array) where !array.isEmpty:
            for (index, child) in array.enumerated() {
                appendOrigins(
                    value: child,
                    path: "\(path).\(index)",
                    metadata: metadata,
                    to: &origins
                )
            }
        default:
            origins[path] = metadata
        }
    }

    private static func userLayerName(file: URL) -> CLIJSONValue {
        .object([
            "type": .string("user"),
            "file": .string(file.path),
            "profile": .null
        ])
    }

    private static var sessionOrigin: CLIJSONValue {
        .object([
            "name": .object(["type": .string("sessionFlags")]),
            "version": .string("session")
        ])
    }
}

private extension ConfigValue {
    var jsonValue: CLIJSONValue {
        switch self {
        case .object(let value): .object(value.mapValues(\.jsonValue))
        case .array(let value): .array(value.map(\.jsonValue))
        case .string(let value): .string(value)
        case .integer(let value): .number(Double(value))
        case .number(let value):
            value.isFinite
                ? .number(value)
                : .string(nonFiniteNumberStringValue ?? "nan")
        case .bool(let value): .bool(value)
        case .offsetDateTime, .localDateTime, .localDate, .localTime:
            .string(temporalStringValue ?? "")
        }
    }
}

private extension Dictionary where Key == String, Value == CLIJSONValue {
    mutating func setDefault(_ key: String, to value: CLIJSONValue) {
        if self[key] == nil { self[key] = value }
    }
}
