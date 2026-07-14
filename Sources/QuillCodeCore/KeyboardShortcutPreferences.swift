import Foundation

public enum KeyboardShortcutModifier: String, Codable, Sendable, Hashable, CaseIterable {
    case command
    case control
    case option
    case shift
}

public struct KeyboardShortcutOverride: Codable, Sendable, Hashable, Identifiable {
    public var id: String { commandID }
    public let commandID: String
    public let key: String
    public let modifiers: [KeyboardShortcutModifier]

    private enum CodingKeys: String, CodingKey {
        case commandID
        case key
        case modifiers
    }

    public init(
        commandID: String,
        key: String,
        modifiers: [KeyboardShortcutModifier]
    ) {
        self.commandID = Self.normalizedCommandID(commandID)
        self.key = Self.normalizedKey(key)
        self.modifiers = Self.normalizedModifiers(modifiers)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            commandID: try container.decodeIfPresent(String.self, forKey: .commandID) ?? "",
            key: try container.decodeIfPresent(String.self, forKey: .key) ?? "",
            modifiers: try container.decodeIfPresent(
                [KeyboardShortcutModifier].self,
                forKey: .modifiers
            ) ?? []
        )
    }

    public var isValid: Bool {
        !commandID.isEmpty && hasSupportedKey && isSafeGlobalBinding
    }

    public var hasSupportedKey: Bool {
        if Self.namedKeys.contains(key) {
            return true
        }
        return key.count == 1 && key.first?.isWhitespace == false
    }

    public var isSafeGlobalBinding: Bool {
        if key == "escape" || key == "tab" {
            return true
        }
        return modifiers.contains(.command)
            || modifiers.contains(.control)
            || modifiers.contains(.option)
    }

    private static func normalizedCommandID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 1 {
            return trimmed.lowercased()
        }
        return canonicalNamedKeys[trimmed.lowercased()] ?? trimmed
    }

    private static func normalizedModifiers(
        _ values: [KeyboardShortcutModifier]
    ) -> [KeyboardShortcutModifier] {
        KeyboardShortcutModifier.allCases.filter(Set(values).contains)
    }

    private static let namedKeys = Set(canonicalNamedKeys.values)
    private static let canonicalNamedKeys = [
        "arrowleft": "arrowLeft",
        "arrowright": "arrowRight",
        "arrowup": "arrowUp",
        "arrowdown": "arrowDown",
        "escape": "escape",
        "tab": "tab"
    ]
}

public struct KeyboardShortcutPreferences: Codable, Sendable, Hashable {
    public let overrides: [KeyboardShortcutOverride]

    private enum CodingKeys: String, CodingKey {
        case overrides
    }

    public init(overrides: [KeyboardShortcutOverride] = []) {
        var latestByCommandID: [String: KeyboardShortcutOverride] = [:]
        for override in overrides where override.isValid {
            latestByCommandID[override.commandID] = override
        }
        self.overrides = latestByCommandID.values.sorted {
            $0.commandID < $1.commandID
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(overrides: try container.decodeIfPresent(
            [KeyboardShortcutOverride].self,
            forKey: .overrides
        ) ?? [])
    }

    public func override(for commandID: String) -> KeyboardShortcutOverride? {
        overrides.first { $0.commandID == commandID }
    }
}
