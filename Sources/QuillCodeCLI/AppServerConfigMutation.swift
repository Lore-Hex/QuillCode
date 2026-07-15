import Foundation
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

extension AppServerSession {
    func writeConfigValue(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let keyPath = try configKeyPath(params.requiredString("keyPath"))
        guard let rawValue = params.object["value"] else {
            throw AppServerRPCError.invalidParams("value is required")
        }
        let edit = try configEdit(
            keyPath: keyPath,
            rawValue: rawValue,
            rawStrategy: params.requiredString("mergeStrategy")
        )
        return try await applyConfigEdits(
            [edit],
            filePath: try params.optionalString("filePath"),
            expectedVersion: try params.optionalString("expectedVersion")
        )
    }

    func writeConfigBatch(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        guard let rawEdits = try params.optionalArray("edits") else {
            throw AppServerRPCError.invalidParams("edits is required")
        }
        let edits = try rawEdits.enumerated().map { index, rawEdit in
            let edit: AppServerParams
            do {
                edit = try AppServerParams(rawEdit)
            } catch {
                throw AppServerRPCError.invalidParams("edits[\(index)] must be an object")
            }
            let keyPath = try configKeyPath(edit.requiredString("keyPath"))
            guard let rawValue = edit.object["value"] else {
                throw AppServerRPCError.invalidParams("edits[\(index)].value is required")
            }
            return try configEdit(
                keyPath: keyPath,
                rawValue: rawValue,
                rawStrategy: edit.requiredString("mergeStrategy")
            )
        }
        _ = try params.optionalBool("reloadUserConfig") ?? false
        return try await applyConfigEdits(
            edits,
            filePath: try params.optionalString("filePath"),
            expectedVersion: try params.optionalString("expectedVersion")
        )
    }

    private func configKeyPath(_ rawValue: String) throws -> ConfigKeyPath {
        do {
            return try ConfigKeyPath(rawValue)
        } catch let error as ConfigDocumentError {
            throw Self.configWriteError(.validation, error.description)
        } catch {
            throw Self.configWriteError(.validation, error.localizedDescription)
        }
    }

    private func configEdit(
        keyPath: ConfigKeyPath,
        rawValue: CLIJSONValue,
        rawStrategy: String
    ) throws -> ConfigDocumentEdit {
        guard let strategy = ConfigMergeStrategy(rawValue: rawStrategy) else {
            throw AppServerRPCError.invalidParams("mergeStrategy must be replace or upsert")
        }
        let value: ConfigValue?
        if rawValue == .null {
            value = nil
        } else {
            do {
                value = try ConfigValue(jsonValue: rawValue)
            } catch let error as ConfigDocumentError {
                throw Self.configWriteError(.validation, error.description)
            }
        }
        if value != nil, let first = keyPath.segments.first, first == "profile" || first == "profiles" {
            let message = first == "profile"
                ? "`profile` is a legacy config selector and can no longer be written"
                : "`profiles` contains legacy config profile tables and can no longer be written"
            throw Self.configWriteError(.validation, message)
        }
        return ConfigDocumentEdit(keyPath: keyPath, value: value, mergeStrategy: strategy)
    }

    private func applyConfigEdits(
        _ edits: [ConfigDocumentEdit],
        filePath: String?,
        expectedVersion: String?
    ) async throws -> CLIJSONValue {
        let file = try writableConfigFile(filePath)
        let store = ConfigDocumentStore(fileURL: file)
        let snapshot: ConfigDocumentSnapshot
        do {
            snapshot = try store.loadSnapshot()
        } catch {
            throw Self.configWriteError(.validation, "Invalid configuration: \(error.localizedDescription)")
        }

        let currentVersion = Self.configVersion(snapshot.bytes)
        if let expectedVersion, expectedVersion != currentVersion {
            throw Self.configWriteError(
                .versionConflict,
                "Configuration was modified since last read. Fetch latest version and retry."
            )
        }

        var document = snapshot.document
        for edit in edits { document.apply(edit) }
        try Self.validateConfigDocument(document)
        if document != snapshot.document {
            do {
                try store.save(document)
                appConfig = try ConfigStore(fileURL: file).load()
            } catch let error as AppServerRPCError {
                throw error
            } catch {
                throw AppServerRPCError.internalError(
                    "failed to persist config.toml: \(error.localizedDescription)"
                )
            }

            cachedSkillSnapshots.removeAll(keepingCapacity: true)
            refreshSkillWatcher()
            if edits.contains(where: Self.affectsSkills) {
                await sendNotification("skills/changed", params: .object([:]))
            }
        }
        let nextBytes = (try? Data(contentsOf: file)) ?? Data()
        return .object([
            "status": .string("ok"),
            "version": .string(Self.configVersion(nextBytes)),
            "filePath": .string(file.path),
            "overriddenMetadata": .null
        ])
    }

    private func writableConfigFile(_ suppliedPath: String?) throws -> URL {
        let allowed = Self.normalizedConfigFile(paths.configFile)
        guard let suppliedPath else { return allowed }
        guard NSString(string: suppliedPath).isAbsolutePath else {
            throw Self.configWriteError(.readonlyLayer, "Only writes to the user config are allowed")
        }
        let supplied = Self.normalizedConfigFile(URL(fileURLWithPath: suppliedPath))
        guard supplied.path == allowed.path else {
            throw Self.configWriteError(.readonlyLayer, "Only writes to the user config are allowed")
        }
        return allowed
    }

    private static func normalizedConfigFile(_ file: URL) -> URL {
        let parent = file.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return parent.appendingPathComponent(file.lastPathComponent).standardizedFileURL
    }

    private static func validateConfigDocument(_ document: ConfigDocument) throws {
        let stringKeys: Set<String> = [
            "model", "default_model", "review_model", "model_provider", "approval_policy",
            "approvals_reviewer", "sandbox_mode", "forced_login_method", "web_search",
            "instructions", "developer_instructions", "compact_prompt", "model_reasoning_effort",
            "model_reasoning_summary", "model_verbosity", "service_tier", "mode", "api_base_url"
        ]
        let integerKeys: Set<String> = [
            "model_context_window", "model_auto_compact_token_limit", "max_tool_steps"
        ]
        let objectKeys: Set<String> = [
            "sandbox_workspace_write", "tools", "analytics", "apps", "desktop"
        ]
        for key in stringKeys {
            if let value = document.values[key], value.stringValue == nil {
                throw configWriteError(.validation, "Invalid configuration: `\(key)` must be a string")
            }
        }
        for key in integerKeys {
            if let value = document.values[key], value.integerValue == nil {
                throw configWriteError(.validation, "Invalid configuration: `\(key)` must be an integer")
            }
        }
        for key in objectKeys {
            if let value = document.values[key], value.objectValue == nil {
                throw configWriteError(.validation, "Invalid configuration: `\(key)` must be a table")
            }
        }
        if let mode = document.values["mode"]?.stringValue, AgentMode(rawValue: mode) == nil {
            throw configWriteError(.validation, "Invalid configuration: unknown mode `\(mode)`")
        }
    }

    private static func affectsSkills(_ edit: ConfigDocumentEdit) -> Bool {
        guard let first = edit.keyPath.segments.first else { return false }
        return first == "skills" || first == "disabled_skill_path" || first == "disabled_skill_name"
    }

    static func configVersion(_ bytes: Data) -> String {
        let digest = MCPCrypto.sha256(Array(bytes))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private enum ConfigWriteFailure: String {
        case readonlyLayer = "configLayerReadonly"
        case versionConflict = "configVersionConflict"
        case validation = "configValidationError"
    }

    private static func configWriteError(
        _ code: ConfigWriteFailure,
        _ message: String
    ) -> AppServerRPCError {
        AppServerRPCError(
            code: -32600,
            message: message,
            data: .object(["config_write_error_code": .string(code.rawValue)])
        )
    }
}

private extension ConfigValue {
    init(jsonValue: CLIJSONValue) throws {
        switch jsonValue {
        case .object(let values):
            self = .object(try values.mapValues(ConfigValue.init(jsonValue:)))
        case .array(let values):
            self = .array(try values.map(ConfigValue.init(jsonValue:)))
        case .string(let value): self = .string(value)
        case .number(let value):
            guard value.isFinite else {
                throw ConfigDocumentError.invalidValue("TOML numbers must be finite")
            }
            if value.rounded() == value,
               value >= Double(Int64.min),
               value <= Double(Int64.max) {
                self = .integer(Int64(value))
            } else {
                self = .number(value)
            }
        case .bool(let value): self = .bool(value)
        case .null:
            throw ConfigDocumentError.invalidValue("TOML arrays and tables cannot contain null")
        }
    }
}
