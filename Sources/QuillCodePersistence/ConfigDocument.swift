import Foundation
import TOML

public enum ConfigDocumentError: Error, CustomStringConvertible, Sendable, Equatable {
    case invalidKeyPath(String)
    case invalidRoot
    case invalidValue(String)

    public var description: String {
        switch self {
        case .invalidKeyPath(let reason): reason
        case .invalidRoot: "The TOML document root must be a table."
        case .invalidValue(let reason): reason
        }
    }
}

public struct ConfigKeyPath: Sendable, Hashable {
    public let segments: [String]

    public init(_ rawValue: String) throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigDocumentError.invalidKeyPath("keyPath must not be empty")
        }

        var segments: [String] = []
        var segment = ""
        var iterator = rawValue.makeIterator()
        var quoted = false

        while let character = iterator.next() {
            switch character {
            case "\"" where segment.isEmpty && !quoted:
                quoted = true
            case "\"" where quoted:
                quoted = false
            case "\\" where quoted:
                guard let escaped = iterator.next() else {
                    throw ConfigDocumentError.invalidKeyPath("unterminated escape in keyPath")
                }
                segment.append(escaped)
            case "." where !quoted:
                guard !segment.isEmpty else {
                    throw ConfigDocumentError.invalidKeyPath("keyPath segments must not be empty")
                }
                segments.append(segment)
                segment.removeAll(keepingCapacity: true)
            case "\"":
                throw ConfigDocumentError.invalidKeyPath("invalid quoted keyPath segment")
            default:
                segment.append(character)
            }
        }

        guard !quoted else {
            throw ConfigDocumentError.invalidKeyPath("unterminated quoted keyPath segment")
        }
        guard !segment.isEmpty else {
            throw ConfigDocumentError.invalidKeyPath("keyPath segments must not be empty")
        }
        segments.append(segment)
        self.segments = segments
    }
}

public enum ConfigMergeStrategy: String, Sendable, Equatable {
    case replace
    case upsert
}

public struct ConfigDocumentEdit: Sendable, Equatable {
    public var keyPath: ConfigKeyPath
    public var value: ConfigValue?
    public var mergeStrategy: ConfigMergeStrategy

    public init(
        keyPath: ConfigKeyPath,
        value: ConfigValue?,
        mergeStrategy: ConfigMergeStrategy
    ) {
        self.keyPath = keyPath
        self.value = value
        self.mergeStrategy = mergeStrategy
    }
}

public struct ConfigDocument: Sendable, Equatable {
    public var values: [String: ConfigValue]

    public init(values: [String: ConfigValue] = [:]) {
        self.values = values
    }

    public func value(at keyPath: ConfigKeyPath) -> ConfigValue? {
        var current = ConfigValue.object(values)
        for segment in keyPath.segments {
            guard case .object(let object) = current,
                  let next = object[segment]
            else { return nil }
            current = next
        }
        return current
    }

    @discardableResult
    public mutating func apply(_ edit: ConfigDocumentEdit) -> Bool {
        let original = value(at: edit.keyPath)
        var root = ConfigValue.object(values)
        root = Self.applying(
            value: edit.value,
            at: ArraySlice(edit.keyPath.segments),
            to: root,
            strategy: edit.mergeStrategy
        )
        values = root.objectValue ?? [:]
        return original != value(at: edit.keyPath)
    }

    public mutating func removeValue(at keyPath: ConfigKeyPath) {
        apply(ConfigDocumentEdit(keyPath: keyPath, value: nil, mergeStrategy: .replace))
    }

    /// Applies a higher-precedence document using the same recursive table merge as TOML config
    /// layers: scalar and array values replace, while tables merge recursively.
    public mutating func merge(overridingWith incoming: ConfigDocument) {
        values = Self.recursivelyMerging(
            .object(values),
            with: .object(incoming.values)
        ).objectValue ?? [:]
    }

    private static func applying(
        value: ConfigValue?,
        at segments: ArraySlice<String>,
        to current: ConfigValue,
        strategy: ConfigMergeStrategy
    ) -> ConfigValue {
        guard let segment = segments.first else { return value ?? current }
        var object = current.objectValue ?? [:]

        if segments.count == 1 {
            guard let value else {
                object.removeValue(forKey: segment)
                return .object(object)
            }
            if strategy == .upsert,
               let existing = object[segment],
               case .object = existing,
               case .object = value {
                object[segment] = recursivelyMerging(existing, with: value)
            } else {
                object[segment] = value
            }
            return .object(object)
        }

        guard value != nil || object[segment] != nil else { return .object(object) }
        let child = object[segment] ?? .object([:])
        object[segment] = applying(
            value: value,
            at: segments.dropFirst(),
            to: child,
            strategy: strategy
        )
        return .object(object)
    }

    private static func recursivelyMerging(_ existing: ConfigValue, with incoming: ConfigValue) -> ConfigValue {
        guard case .object(var destination) = existing,
              case .object(let source) = incoming
        else { return incoming }
        for (key, value) in source {
            if let current = destination[key],
               case .object = current,
               case .object = value {
                destination[key] = recursivelyMerging(current, with: value)
            } else {
                destination[key] = value
            }
        }
        return .object(destination)
    }
}

public struct ConfigDocumentSnapshot: Sendable, Equatable {
    public var document: ConfigDocument
    public var bytes: Data

    public init(document: ConfigDocument, bytes: Data) {
        self.document = document
        self.bytes = bytes
    }
}

public struct ConfigDocumentStore: Sendable {
    public static let maximumBytes = 4 * 1_024 * 1_024

    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ConfigDocument {
        try loadSnapshot().document
    }

    public func loadSnapshot() throws -> ConfigDocumentSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ConfigDocumentSnapshot(document: ConfigDocument(), bytes: Data())
        }
        let bytes = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard bytes.count <= Self.maximumBytes else {
            throw ConfigDocumentError.invalidValue(
                "Config exceeds the \(Self.maximumBytes)-byte limit."
            )
        }
        guard let source = String(data: bytes, encoding: .utf8) else {
            throw ConfigDocumentError.invalidValue("Config must be UTF-8.")
        }
        let normalized = Self.normalizingLegacyRepeatedKeys(source)
        let values = try TOMLDecoder().decode([String: ConfigValue].self, from: normalized)
        return ConfigDocumentSnapshot(document: ConfigDocument(values: values), bytes: bytes)
    }

    public func save(_ document: ConfigDocument) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = TOMLEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        var source = try encoder.encodeToString(document.values)
        if !source.isEmpty, !source.hasSuffix("\n") { source.append("\n") }
        guard let bytes = source.data(using: .utf8), bytes.count <= Self.maximumBytes else {
            throw ConfigDocumentError.invalidValue(
                "Encoded config exceeds the \(Self.maximumBytes)-byte limit."
            )
        }
        try bytes.write(to: fileURL, options: .atomic)
    }

    private static let legacyRepeatedKeys: Set<String> = [
        "favorite_model",
        "computer_use_approved_bundle_identifier",
        "computer_use_approved_app_name",
        "browser_allowed_domain",
        "browser_blocked_domain",
        "disabled_skill_path",
        "disabled_skill_name"
    ]

    /// Early QuillCode releases emitted repeated scalar keys, which TOML correctly rejects.
    /// Collapse only those known legacy list keys before handing the document to the strict parser.
    private static func normalizingLegacyRepeatedKeys(_ source: String) -> String {
        var lines = source.components(separatedBy: .newlines)
        var occurrences: [String: [(index: Int, value: String)]] = [:]

        for (index, line) in lines.enumerated() {
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2,
                  legacyRepeatedKeys.contains(parts[0]),
                  let value = legacyString(String(parts[1]))
            else { continue }
            occurrences[parts[0], default: []].append((index, value))
        }

        for (key, values) in occurrences where values.count > 1 {
            let encoded = values.map { quotedString($0.value) }.joined(separator: ", ")
            lines[values[0].index] = "\(key) = [\(encoded)]"
            for value in values.dropFirst() { lines[value.index] = "" }
        }
        return lines.joined(separator: "\n")
    }

    private static func legacyString(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return nil }
        let inner = String(value.dropFirst().dropLast())
        var output = ""
        var escaping = false
        for character in inner {
            if escaping {
                switch character {
                case "n": output.append("\n")
                case "r": output.append("\r")
                case "t": output.append("\t")
                default: output.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                output.append(character)
            }
        }
        if escaping { output.append("\\") }
        return output
    }

    private static func quotedString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
