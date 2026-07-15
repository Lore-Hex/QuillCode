import Foundation
import QuillCodeCore
import QuillCodeTools
import TOMLDecoder

struct CodexHookConfiguration: Decodable {
    var hooks: [String: [CodexHookGroup]]
    var hooksFeatureOverride: Bool?
    var allowManagedHooksOnly: Bool?

    private enum CodingKeys: String, CodingKey {
        case hooks
        case features
        case allowManagedHooksOnly
        case allowManagedHooksOnlySnake = "allow_managed_hooks_only"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hooks = try container.decodeIfPresent(CodexHookTable.self, forKey: .hooks)?.events ?? [:]
        let features = try container.decodeIfPresent(CodexHookFeatures.self, forKey: .features)
        hooksFeatureOverride = features?.hooks ?? features?.legacyHooks
        allowManagedHooksOnly = try container.decodeIfPresent(Bool.self, forKey: .allowManagedHooksOnly)
            ?? container.decodeIfPresent(Bool.self, forKey: .allowManagedHooksOnlySnake)
    }
}

private struct CodexHookFeatures: Decodable {
    var hooks: Bool?
    var legacyHooks: Bool?

    private enum CodingKeys: String, CodingKey {
        case hooks
        case legacyHooks = "codex_hooks"
    }
}

/// A hooks table may contain policy metadata such as `managed_dir` next to event arrays.
/// Decode only array-shaped event entries so managed requirements remain forward compatible.
private struct CodexHookTable: Decodable {
    var events: [String: [CodexHookGroup]]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var events: [String: [CodexHookGroup]] = [:]
        for key in container.allKeys {
            if let groups = try? container.decode([CodexHookGroup].self, forKey: key) {
                events[key.stringValue] = groups
            }
        }
        self.events = events
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct CodexHookGroup: Decodable {
    var matcher: String?
    var hooks: [CodexHookHandler]
}

struct CodexHookHandler: Decodable {
    var type: String?
    var command: String?
    var commandWindows: String?
    var statusMessage: String?
    var timeout: Int?
    var isAsync: Bool?

    private enum CodingKeys: String, CodingKey {
        case type
        case command
        case commandWindows
        case commandWindowsSnake = "command_windows"
        case statusMessage
        case statusMessageSnake = "status_message"
        case timeout
        case isAsync = "async"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        commandWindows = try container.decodeIfPresent(String.self, forKey: .commandWindows)
            ?? container.decodeIfPresent(String.self, forKey: .commandWindowsSnake)
        statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
            ?? container.decodeIfPresent(String.self, forKey: .statusMessageSnake)
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
        isAsync = try container.decodeIfPresent(Bool.self, forKey: .isAsync)
    }
}

enum CodexHookConfigurationDecoder {
    static func decodeJSON(_ data: Data) -> CodexHookConfiguration? {
        try? JSONDecoder().decode(CodexHookConfiguration.self, from: data)
    }

    static func decodeTOML(_ data: Data) -> CodexHookConfiguration? {
        try? TOMLDecoder().decode(CodexHookConfiguration.self, from: data)
    }
}

struct CodexHookDefinitionSource: Sendable, Hashable {
    var idPrefix: String
    var ownerID: String
    var ownerName: String
    var relativePath: String
    var pluginRootRelativePath: String?
    var trustScope: ProjectHookTrustScope?

    init(
        idPrefix: String,
        ownerID: String,
        ownerName: String,
        relativePath: String,
        pluginRootRelativePath: String?,
        trustScope: ProjectHookTrustScope? = nil
    ) {
        self.idPrefix = idPrefix
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.relativePath = relativePath
        self.pluginRootRelativePath = pluginRootRelativePath
        self.trustScope = trustScope
    }
}

enum CodexHookDefinitionBuilder {
    static let defaultTimeoutSeconds = 600
    static let maxTimeoutSeconds = 3_600

    static func definitions(
        from configuration: CodexHookConfiguration,
        source: CodexHookDefinitionSource,
        limit: Int
    ) -> [ProjectPluginHook] {
        guard limit > 0 else { return [] }
        var definitions: [ProjectPluginHook] = []
        for event in configuration.hooks.keys.sorted() {
            guard let eventID = normalizedIdentifier(event),
                  let groups = configuration.hooks[event]
            else { continue }
            for (groupIndex, group) in groups.enumerated() {
                let matcher = normalizedOptionalText(group.matcher, maxLength: 1_000)
                for (handlerIndex, handler) in group.hooks.enumerated() {
                    guard definitions.count < limit,
                          let handlerType = normalizedOptionalText(
                            handler.type,
                            maxLength: 80
                          )?.lowercased()
                    else { continue }
                    let command = normalizedOptionalText(handler.command, maxLength: 8_000)
                    let commandWindows = normalizedOptionalText(handler.commandWindows, maxLength: 8_000)
                    let statusMessage = normalizedOptionalText(handler.statusMessage, maxLength: 240)
                    let timeoutSeconds = normalizedTimeout(handler.timeout)
                    let isAsync = handler.isAsync ?? false
                    definitions.append(ProjectPluginHook(
                        id: "\(source.idPrefix).\(eventID).\(groupIndex).\(handlerIndex)",
                        pluginID: source.ownerID,
                        pluginName: source.ownerName,
                        event: event,
                        matcher: matcher,
                        handlerType: handlerType,
                        command: command,
                        commandWindows: commandWindows,
                        statusMessage: statusMessage,
                        timeoutSeconds: timeoutSeconds,
                        isAsync: isAsync,
                        relativePath: "\(source.relativePath)#\(event)/\(groupIndex)/\(handlerIndex)",
                        pluginRootRelativePath: source.pluginRootRelativePath,
                        definitionHash: definitionHash(
                            event: event,
                            matcher: matcher,
                            handlerType: handlerType,
                            command: command,
                            commandWindows: commandWindows,
                            statusMessage: statusMessage,
                            timeoutSeconds: timeoutSeconds,
                            isAsync: isAsync,
                            pluginRootRelativePath: source.pluginRootRelativePath
                        ),
                        trustScope: source.trustScope,
                        trustStatus: source.trustScope == .managed ? .trusted : .reviewRequired,
                        supportStatus: supportStatus(
                            event: event,
                            matcher: matcher,
                            handlerType: handlerType,
                            command: command,
                            isAsync: isAsync
                        )
                    ))
                }
                if definitions.count == limit { break }
            }
            if definitions.count == limit { break }
        }
        return definitions
    }

    private static func supportStatus(
        event: String,
        matcher: String?,
        handlerType: String,
        command: String?,
        isAsync: Bool
    ) -> ProjectHookSupportStatus {
        if isAsync { return .asynchronousHandler }
        if handlerType != "command" { return .unsupportedHandler }
        if command == nil { return .missingCommand }
        switch event {
        case "UserPromptSubmit", "Stop":
            if let matcher, matcher != "*" { return .unsupportedMatcher }
            return .supported
        case "PreToolUse", "PostToolUse", "PermissionRequest", "PreCompact", "PostCompact",
             "SessionStart", "SubagentStart", "SubagentStop":
            return ProjectPluginHookMatcher.isValid(matcher)
                ? .supported
                : .unsupportedMatcher
        default:
            return .unsupportedEvent
        }
    }

    private static func definitionHash(
        event: String,
        matcher: String?,
        handlerType: String,
        command: String?,
        commandWindows: String?,
        statusMessage: String?,
        timeoutSeconds: Int,
        isAsync: Bool,
        pluginRootRelativePath: String?
    ) -> String {
        let canonical = [
            event,
            matcher ?? "",
            handlerType,
            command ?? "",
            commandWindows ?? "",
            statusMessage ?? "",
            String(timeoutSeconds),
            isAsync ? "true" : "false",
            pluginRootRelativePath ?? ""
        ].joined(separator: "\u{1F}")
        return MCPCrypto.sha256(Array(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func normalizedTimeout(_ value: Int?) -> Int {
        min(max(value ?? defaultTimeoutSeconds, 1), maxTimeoutSeconds)
    }

    private static func normalizedIdentifier(_ value: String) -> String? {
        let result = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
        return result.isEmpty || result.count > 128 ? nil : result
    }

    private static func normalizedOptionalText(_ value: String?, maxLength: Int) -> String? {
        guard let result = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty,
              result.count <= maxLength,
              !result.contains("\0")
        else { return nil }
        return result
    }
}
