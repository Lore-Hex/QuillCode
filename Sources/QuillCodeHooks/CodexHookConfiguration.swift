import Foundation
import QuillCodeCore
import QuillCodeTools
import TOMLDecoder

struct CodexHookConfiguration: Decodable {
    var hooks: [String: [CodexHookGroup]]
    var hookStates: [String: HookConfigurationState]
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
        let hookTable = try container.decodeIfPresent(CodexHookTable.self, forKey: .hooks)
        hooks = hookTable?.events ?? [:]
        hookStates = hookTable?.states ?? [:]
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
    var states: [String: HookConfigurationState]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var events: [String: [CodexHookGroup]] = [:]
        var states: [String: HookConfigurationState] = [:]
        for key in container.allKeys {
            if key.stringValue == "state",
               let stateContainer = try? container.nestedContainer(
                keyedBy: DynamicCodingKey.self,
                forKey: key
               ) {
                for stateKey in stateContainer.allKeys {
                    guard let state = try? stateContainer.decode(
                        CodexHookState.self,
                        forKey: stateKey
                    ) else { continue }
                    states[stateKey.stringValue] = HookConfigurationState(
                        enabled: state.enabled,
                        trustedHash: state.trustedHash
                    )
                }
                continue
            }
            if let groups = try? container.decode([CodexHookGroup].self, forKey: key) {
                events[key.stringValue] = groups
            }
        }
        self.events = events
        self.states = states
    }
}

private struct CodexHookState: Decodable {
    var enabled: Bool?
    var trustedHash: String?

    private enum CodingKeys: String, CodingKey {
        case enabled
        case trustedHash
        case trustedHashSnake = "trusted_hash"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        trustedHash = try container.decodeIfPresent(String.self, forKey: .trustedHash)
            ?? container.decodeIfPresent(String.self, forKey: .trustedHashSnake)
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
        try? decodeJSONThrowing(data)
    }

    static func decodeTOML(_ data: Data) -> CodexHookConfiguration? {
        try? decodeTOMLThrowing(data)
    }

    static func decodeJSONThrowing(_ data: Data) throws -> CodexHookConfiguration {
        try JSONDecoder().decode(CodexHookConfiguration.self, from: data)
    }

    static func decodeTOMLThrowing(_ data: Data) throws -> CodexHookConfiguration {
        try TOMLDecoder().decode(CodexHookConfiguration.self, from: data)
    }
}

public struct CodexHookDefinitionSource: Sendable, Hashable {
    public var idPrefix: String
    public var ownerID: String
    public var ownerName: String
    public var relativePath: String
    public var pluginRootRelativePath: String?
    public var trustScope: ProjectHookTrustScope?
    public var sourcePath: URL?
    public var catalogSource: HookCatalogSource
    public var keyPrefix: String?
    public var pluginIdentifier: String?

    public init(
        idPrefix: String,
        ownerID: String,
        ownerName: String,
        relativePath: String,
        pluginRootRelativePath: String?,
        trustScope: ProjectHookTrustScope? = nil,
        sourcePath: URL? = nil,
        catalogSource: HookCatalogSource = .unknown,
        keyPrefix: String? = nil,
        pluginIdentifier: String? = nil
    ) {
        self.idPrefix = idPrefix
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.relativePath = relativePath
        self.pluginRootRelativePath = pluginRootRelativePath
        self.trustScope = trustScope
        self.sourcePath = sourcePath
        self.catalogSource = catalogSource
        self.keyPrefix = keyPrefix
        self.pluginIdentifier = pluginIdentifier
    }
}

/// Public data-only entry point for plugin packages that keep hooks in JSON.
/// Decoded configuration types remain private to this module so callers cannot couple to parser details.
public enum CodexHookDefinitionLoader {
    public static func definitions(
        fromJSON data: Data,
        source: CodexHookDefinitionSource,
        limit: Int
    ) -> [ProjectPluginHook] {
        catalogDefinitions(fromJSON: data, source: source, limit: limit).map(\.hook)
    }

    public static func catalogDefinitions(
        fromJSON data: Data,
        source: CodexHookDefinitionSource,
        limit: Int
    ) -> [HookCatalogDefinition] {
        (try? validatedCatalogDefinitions(fromJSON: data, source: source, limit: limit)) ?? []
    }

    /// Decodes and builds catalog entries while preserving malformed-document errors for
    /// discovery surfaces that need to report a precise warning to the user.
    public static func validatedCatalogDefinitions(
        fromJSON data: Data,
        source: CodexHookDefinitionSource,
        limit: Int
    ) throws -> [HookCatalogDefinition] {
        let configuration = try CodexHookConfigurationDecoder.decodeJSONThrowing(data)
        return CodexHookDefinitionBuilder.catalogDefinitions(
            from: configuration,
            source: source,
            limit: limit
        )
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
        catalogDefinitions(from: configuration, source: source, limit: limit).map(\.hook)
    }

    static func catalogDefinitions(
        from configuration: CodexHookConfiguration,
        source: CodexHookDefinitionSource,
        limit: Int
    ) -> [HookCatalogDefinition] {
        guard limit > 0 else { return [] }
        var definitions: [HookCatalogDefinition] = []
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
                    let hook = ProjectPluginHook(
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
                    )
                    let sourcePath = source.sourcePath
                        ?? URL(fileURLWithPath: source.relativePath).standardizedFileURL
                    let keyPrefix = source.keyPrefix ?? sourcePath.path
                    definitions.append(HookCatalogDefinition(
                        hook: hook,
                        key: "\(keyPrefix):\(eventKeyLabel(event)):\(groupIndex):\(handlerIndex)",
                        sourcePath: sourcePath,
                        source: source.catalogSource,
                        pluginID: source.pluginIdentifier
                    ))
                }
                if definitions.count == limit { break }
            }
            if definitions.count == limit { break }
        }
        return definitions
    }

    private static func eventKeyLabel(_ event: String) -> String {
        event.reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty { result.append("_") }
            result.append(character.lowercased())
        }
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
