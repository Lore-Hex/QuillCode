import Foundation
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

extension AppServerSession {
    func listExperimentalFeatures(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try Self.experimentalFeatureParams(raw)
        let cursor = try Self.experimentalFeatureOptionalString(params, key: "cursor")
        let limit = try Self.experimentalFeatureLimit(params)
        let cwd = try await experimentalFeatureCWD(params)
        var data: [CLIJSONValue] = []
        data.reserveCapacity(QuillCodeFeatureCatalog.all.count)
        for definition in QuillCodeFeatureCatalog.all {
            data.append(experimentalFeatureValue(
                definition,
                enabled: try await experimentalFeatureEnabled(definition.feature, cwd: cwd)
            ))
        }

        let start = try Self.experimentalFeatureCursorOffset(cursor, total: data.count)
        let pageSize = min(max(limit ?? data.count, 1), data.count)
        let end = min(start + pageSize, data.count)
        return .object([
            "data": .array(Array(data[start..<end])),
            "nextCursor": end < data.count ? .string(String(end)) : .null
        ])
    }

    func setExperimentalFeatureEnablement(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try Self.experimentalFeatureParams(raw)
        guard let value = params["enablement"] else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: missing field `enablement`"
            )
        }
        guard let requested = value.objectValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: invalid type for `enablement`, expected a map of booleans"
            )
        }

        var accepted: [String: Bool] = [:]
        for name in requested.keys.sorted() {
            guard let enabled = requested[name]?.boolValue else {
                throw AppServerRPCError.invalidRequest(
                    "Invalid request: invalid type for `enablement.\(name)`, expected a boolean"
                )
            }
            guard QuillCodeFeatureCatalog.definition(named: name)?.supportsRuntimeEnablement == true else {
                continue
            }
            accepted[name] = enabled
        }
        await runtimeFeatureStore.merge(accepted)
        return .object(["enablement": .object(accepted.mapValues(CLIJSONValue.bool))])
    }

    func experimentalFeatureEnabled(
        _ feature: QuillCodeFeature,
        cwd: URL
    ) async throws -> Bool {
        let definition = QuillCodeFeatureCatalog.definition(for: feature)
        let name = feature.rawValue
        let requirements = try managedRequirements()
        if let enabled = requirements?.featureRequirements?[name] { return enabled }
        if let enabled = request.featureEnablement[name] { return enabled }
        if let enabled = try configuredFeatureEnablement(cwd: cwd)[name] { return enabled }
        if let enabled = await runtimeFeatureStore.value(for: name) { return enabled }
        return definition.defaultEnabled
    }
}

private extension AppServerSession {
    static func experimentalFeatureParams(
        _ raw: CLIJSONValue
    ) throws -> [String: CLIJSONValue] {
        guard let params = raw.objectValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: invalid type for params, expected an object"
            )
        }
        return params
    }

    static func experimentalFeatureOptionalString(
        _ params: [String: CLIJSONValue],
        key: String
    ) throws -> String? {
        guard let value = params[key], value != .null else { return nil }
        guard let string = value.stringValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: invalid type for `\(key)`, expected a string"
            )
        }
        return string
    }

    static func experimentalFeatureLimit(
        _ params: [String: CLIJSONValue]
    ) throws -> Int? {
        guard let value = params["limit"], value != .null else { return nil }
        guard let number = value.numberValue,
              number.isFinite,
              number.rounded() == number,
              number >= 0,
              number <= Double(UInt32.max) else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: invalid type for `limit`, expected an unsigned 32-bit integer"
            )
        }
        return Int(number)
    }

    static func experimentalFeatureCursorOffset(
        _ cursor: String?,
        total: Int
    ) throws -> Int {
        guard let cursor else { return 0 }
        guard let offset = Int(cursor), offset >= 0 else {
            throw AppServerRPCError.invalidRequest("invalid cursor: \(cursor)")
        }
        guard offset <= total else {
            throw AppServerRPCError.invalidRequest(
                "cursor \(offset) exceeds total feature flags \(total)"
            )
        }
        return offset
    }

    func experimentalFeatureCWD(
        _ params: [String: CLIJSONValue]
    ) async throws -> URL {
        guard let rawThreadID = try Self.experimentalFeatureOptionalString(params, key: "threadId") else {
            return currentDirectory
        }
        guard let threadID = UUID(uuidString: rawThreadID), loadedThreadIDs.contains(threadID) else {
            throw AppServerRPCError.invalidRequest("thread not found: \(rawThreadID)")
        }
        do {
            return try await repository.load(threadID).settings.cwd
        } catch {
            throw AppServerRPCError.invalidRequest("thread not found: \(rawThreadID)")
        }
    }

    func experimentalFeatureValue(
        _ definition: QuillCodeFeatureDefinition,
        enabled: Bool
    ) -> CLIJSONValue {
        .object([
            "name": .string(definition.feature.rawValue),
            "stage": .string(definition.stage.rawValue),
            "displayName": definition.displayName.map(CLIJSONValue.string) ?? .null,
            "description": definition.description.map(CLIJSONValue.string) ?? .null,
            "announcement": definition.announcement.map(CLIJSONValue.string) ?? .null,
            "enabled": .bool(enabled),
            "defaultEnabled": .bool(definition.defaultEnabled)
        ])
    }

    func configuredFeatureEnablement(cwd: URL) throws -> [String: Bool] {
        var enablement: [String: Bool] = [:]
        var visited = Set<String>()
        for file in featureConfigurationFiles(cwd: cwd) {
            let file = file.standardizedFileURL
            guard visited.insert(file.path).inserted,
                  FileManager.default.fileExists(atPath: file.path) else { continue }
            let document: ConfigDocument
            do {
                document = try ConfigDocumentStore(fileURL: file).load()
            } catch {
                throw AppServerRPCError.internalError(
                    "failed to reload config at \(file.path): \(error.localizedDescription)"
                )
            }
            guard let features = document.values["features"]?.objectValue else { continue }
            for name in features.keys.sorted() {
                guard QuillCodeFeatureCatalog.definition(named: name) != nil else { continue }
                guard let enabled = features[name]?.boolValue else {
                    throw AppServerRPCError.internalError(
                        "failed to reload config: features.\(name) in \(file.path) must be a boolean"
                    )
                }
                enablement[name] = enabled
            }
        }
        return enablement
    }

    func featureConfigurationFiles(cwd: URL) -> [URL] {
        let configurationRoot = GitRepositoryRootResolver.resolve(containing: cwd)?.configuration
            ?? cwd.standardizedFileURL
        let pathLayers = [
            paths.hookConfigurationPaths.systemCodexDirectory,
            paths.hookConfigurationPaths.systemQuillCodeDirectory,
            paths.hookConfigurationPaths.userCodexDirectory,
            paths.hookConfigurationPaths.userQuillCodeDirectory
        ].compactMap { $0?.appendingPathComponent("config.toml") }
        return pathLayers + [
            configurationRoot.appendingPathComponent(".codex/config.toml"),
            configurationRoot.appendingPathComponent(".quillcode/config.toml")
        ]
    }
}
