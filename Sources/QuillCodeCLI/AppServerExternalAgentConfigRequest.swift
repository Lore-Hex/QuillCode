import Foundation
import QuillCodeCore

struct AppServerExternalAgentConfigDetectRequest: Sendable {
    static let maximumCWDs = 64

    var cwds: [URL]
    var includeHome: Bool

    init(_ raw: CLIJSONValue) throws {
        let params = try AppServerParams(raw)
        includeHome = try params.optionalBool("includeHome") ?? false
        let values = try params.optionalArray("cwds") ?? []
        guard values.count <= Self.maximumCWDs else {
            throw AppServerRPCError.invalidParams("cwds must contain at most \(Self.maximumCWDs) paths")
        }
        cwds = try values.map { value in
            guard let path = value.stringValue,
                  !path.isEmpty,
                  path.utf8.count <= 4_096,
                  !path.contains("\0"),
                  NSString(string: path).isAbsolutePath
            else {
                throw AppServerRPCError.invalidParams("cwds must contain absolute path strings")
            }
            return URL(fileURLWithPath: path)
        }
    }
}

struct AppServerExternalAgentConfigImportRequest: Sendable {
    static let maximumItems = 256

    var migrationItems: [ExternalAgentConfigMigrationItem]
    var source: String?

    init(_ raw: CLIJSONValue) throws {
        let params = try AppServerParams(raw)
        source = try params.optionalString("source")
        if let source, source.utf8.count > 160 {
            throw AppServerRPCError.invalidParams("source must be at most 160 bytes")
        }
        guard let values = try params.optionalArray("migrationItems") else {
            throw AppServerRPCError.invalidParams("migrationItems is required")
        }
        guard values.count <= Self.maximumItems else {
            throw AppServerRPCError.invalidParams(
                "migrationItems must contain at most \(Self.maximumItems) items"
            )
        }
        migrationItems = try values.map(Self.item)
    }
}

private extension AppServerExternalAgentConfigImportRequest {
    static func item(_ value: CLIJSONValue) throws -> ExternalAgentConfigMigrationItem {
        let params = try AppServerParams(value)
        let rawType = try params.requiredString("itemType")
        guard let itemType = ExternalAgentConfigItemType(rawValue: rawType) else {
            throw AppServerRPCError.invalidParams("itemType is not supported: \(rawType)")
        }
        let description = try params.requiredString("description", allowingEmpty: true)
        guard description.utf8.count <= 8_192 else {
            throw AppServerRPCError.invalidParams("description must be at most 8192 bytes")
        }
        let rawCWD = try params.optionalString("cwd")
        if let rawCWD, rawCWD.utf8.count > 4_096 {
            throw AppServerRPCError.invalidParams("cwd must be at most 4096 bytes")
        }
        let cwd = rawCWD?.isEmpty == true ? nil : rawCWD
        if let cwd {
            try requireAbsolutePath(cwd, key: "cwd")
        }
        let details = try params.optionalObject("details").map(details)
        return .init(itemType: itemType, description: description, cwd: cwd, details: details)
    }

    static func details(
        _ object: [String: CLIJSONValue]
    ) throws -> ExternalAgentConfigMigrationDetails {
        let params = try AppServerParams(.object(object))
        return .init(
            plugins: try array(params, "plugins", limit: 128, transform: plugin),
            sessions: try array(params, "sessions", limit: 200, transform: session),
            mcpServers: try array(params, "mcpServers", limit: 256, transform: named),
            hooks: try array(params, "hooks", limit: 256, transform: named),
            subagents: try array(params, "subagents", limit: 256, transform: named),
            commands: try array(params, "commands", limit: 256, transform: named)
        )
    }

    static func array<T>(
        _ params: AppServerParams,
        _ key: String,
        limit: Int,
        transform: (CLIJSONValue) throws -> T
    ) throws -> [T] {
        let values = try params.optionalArray(key) ?? []
        guard values.count <= limit else {
            throw AppServerRPCError.invalidParams("details.\(key) must contain at most \(limit) items")
        }
        return try values.map(transform)
    }

    static func named(_ value: CLIJSONValue) throws -> ExternalAgentConfigNamedMigration {
        let params = try AppServerParams(value)
        let name = try bounded(try params.requiredString("name"), key: "name")
        return .init(name: name)
    }

    static func plugin(_ value: CLIJSONValue) throws -> ExternalAgentConfigPluginsMigration {
        let params = try AppServerParams(value)
        let marketplace = try bounded(
            try params.requiredString("marketplaceName", allowingEmpty: true),
            key: "marketplaceName"
        )
        let names = try params.optionalArray("pluginNames") ?? []
        guard names.count <= 256 else {
            throw AppServerRPCError.invalidParams("pluginNames must contain at most 256 names")
        }
        return .init(marketplaceName: marketplace, pluginNames: try names.map { value in
            guard let name = value.stringValue else {
                throw AppServerRPCError.invalidParams("pluginNames must contain strings")
            }
            return try bounded(name, key: "pluginNames")
        })
    }

    static func session(_ value: CLIJSONValue) throws -> ExternalAgentConfigSessionMigration {
        let params = try AppServerParams(value)
        let path = try bounded(try params.requiredString("path"), key: "path", limit: 4_096)
        let cwd = try bounded(
            try params.requiredString("cwd", allowingEmpty: true),
            key: "cwd",
            limit: 4_096
        )
        let title = try params.optionalString("title").map {
            try bounded($0, key: "title", limit: 500)
        }
        try requireAbsolutePath(path, key: "path")
        if !cwd.isEmpty {
            try requireAbsolutePath(cwd, key: "cwd")
        }
        return .init(path: path, cwd: cwd, title: title)
    }

    static func requireAbsolutePath(_ value: String, key: String) throws {
        guard !value.contains("\0"), NSString(string: value).isAbsolutePath else {
            throw AppServerRPCError.invalidParams("\(key) must be an absolute path")
        }
    }

    static func bounded(_ value: String, key: String, limit: Int = 500) throws -> String {
        guard value.utf8.count <= limit else {
            throw AppServerRPCError.invalidParams("\(key) must be at most \(limit) bytes")
        }
        return value
    }
}

extension ExternalAgentConfigMigrationItem {
    var appServerJSONValue: CLIJSONValue {
        var object: [String: CLIJSONValue] = [
            "itemType": .string(itemType.rawValue),
            "description": .string(description),
            "cwd": cwd.map(CLIJSONValue.string) ?? .null,
            "details": details.map(\.appServerJSONValue) ?? .null,
        ]
        if cwd == nil { object["cwd"] = .null }
        return .object(object)
    }
}

extension ExternalAgentConfigMigrationDetails {
    var appServerJSONValue: CLIJSONValue {
        .object([
            "plugins": .array(plugins.map { .object([
                "marketplaceName": .string($0.marketplaceName),
                "pluginNames": .array($0.pluginNames.map(CLIJSONValue.string)),
            ]) }),
            "sessions": .array(sessions.map { .object([
                "path": .string($0.path),
                "cwd": .string($0.cwd),
                "title": $0.title.map(CLIJSONValue.string) ?? .null,
            ]) }),
            "mcpServers": .array(mcpServers.map(\.appServerJSONValue)),
            "hooks": .array(hooks.map(\.appServerJSONValue)),
            "subagents": .array(subagents.map(\.appServerJSONValue)),
            "commands": .array(commands.map(\.appServerJSONValue)),
        ])
    }
}

private extension ExternalAgentConfigNamedMigration {
    var appServerJSONValue: CLIJSONValue { .object(["name": .string(name)]) }
}

extension ExternalAgentConfigImportTypeResult {
    var appServerJSONValue: CLIJSONValue {
        .object([
            "itemType": .string(itemType.rawValue),
            "successes": .array(successes.map(\.appServerJSONValue)),
            "failures": .array(failures.map(\.appServerJSONValue)),
        ])
    }
}

private extension ExternalAgentConfigImportSuccess {
    var appServerJSONValue: CLIJSONValue {
        .object([
            "itemType": .string(itemType.rawValue),
            "cwd": cwd.map(CLIJSONValue.string) ?? .null,
            "source": source.map(CLIJSONValue.string) ?? .null,
            "target": target.map(CLIJSONValue.string) ?? .null,
        ])
    }
}

private extension ExternalAgentConfigImportFailure {
    var appServerJSONValue: CLIJSONValue {
        .object([
            "itemType": .string(itemType.rawValue),
            "cwd": cwd.map(CLIJSONValue.string) ?? .null,
            "source": source.map(CLIJSONValue.string) ?? .null,
            "errorType": errorType.map(CLIJSONValue.string) ?? .null,
            "failureStage": .string(failureStage),
            "message": .string(message),
        ])
    }
}

extension ExternalAgentConfigImportHistory {
    var appServerJSONValue: CLIJSONValue {
        .object([
            "importId": .string(importId.uuidString.lowercased()),
            "completedAtMs": .number(Double(completedAtMs)),
            "successes": .array(successes.map(\.appServerJSONValue)),
            "failures": .array(failures.map(\.appServerJSONValue)),
        ])
    }
}
