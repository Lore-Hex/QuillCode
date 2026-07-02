import Foundation
import QuillCodeCore
import QuillCodeSafety

/// Result of loading a per-project permission rule file. Loading NEVER throws and never crashes on
/// a bad file: a corrupt or newer-versioned file degrades to an empty table plus human-readable
/// diagnostics the caller can surface.
public struct PermissionRuleLoadResult: Sendable {
    public var table: PermissionRuleTable
    public var diagnostics: [String]

    public init(table: PermissionRuleTable = PermissionRuleTable(), diagnostics: [String] = []) {
        self.table = table
        self.diagnostics = diagnostics
    }
}

public enum PermissionRuleStoreError: Error, CustomStringConvertible {
    /// The on-disk file was written by a NEWER QuillCode. Appending would rewrite (and downgrade)
    /// it, so the save is refused instead of destroying rules this build cannot represent.
    case newerFileVersion(found: Int, supported: Int)

    public var description: String {
        switch self {
        case .newerFileVersion(let found, let supported):
            return "Permission rules file uses newer format version \(found) (this build supports \(supported)); not overwriting it."
        }
    }
}

/// Per-project JSON persistence for permission rule tables, following the shape of the other
/// QuillCode JSON stores (atomic writes, ISO-friendly stable formatting, one file per subject).
/// Files live in one directory keyed by the canonical (symlink-resolved) workspace root so every
/// spelling of the same project path shares one rule table.
public struct PermissionRuleFileStore: Sendable {
    public static let currentVersion = 1

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func fileURL(forWorkspaceRoot root: URL) -> URL {
        let canonicalPath = WorkspaceBoundary.symlinkResolvedPath(root.standardizedFileURL)
        let name = Self.sanitizedComponent(URL(fileURLWithPath: canonicalPath).lastPathComponent)
        return directory.appendingPathComponent("\(name)-\(Self.fnv1a64Hex(canonicalPath)).json")
    }

    /// Loads the workspace's rule table. Missing file → empty table, no diagnostics. Corrupt or
    /// newer-versioned file → empty table + diagnostics (the file itself is left untouched).
    public func load(forWorkspaceRoot root: URL) -> PermissionRuleLoadResult {
        let fileURL = fileURL(forWorkspaceRoot: root)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PermissionRuleLoadResult()
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return PermissionRuleLoadResult(diagnostics: [
                "Could not read permission rules file \(fileURL.lastPathComponent): \(error.localizedDescription). Using no saved rules."
            ])
        }
        return Self.decode(data, fileName: fileURL.lastPathComponent).result
    }

    /// Appends one rule (the "always allow/deny" save path) and persists atomically. A corrupt
    /// existing file is backed up alongside (never silently destroyed) and a fresh table is
    /// started; a NEWER-versioned file refuses the append instead. Returns the diagnostics that
    /// should be surfaced to the user (empty in the happy path).
    @discardableResult
    public func append(_ rule: PermissionRule, forWorkspaceRoot root: URL) throws -> [String] {
        let fileURL = fileURL(forWorkspaceRoot: root)
        var diagnostics: [String] = []
        var table = PermissionRuleTable()

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            if let version = Self.decodedVersion(data), version > Self.currentVersion {
                throw PermissionRuleStoreError.newerFileVersion(found: version, supported: Self.currentVersion)
            }
            let loaded = Self.decode(data, fileName: fileURL.lastPathComponent)
            table = loaded.result.table
            diagnostics = loaded.result.diagnostics
            if loaded.wasCorrupt {
                let backupURL = Self.backupURL(for: fileURL)
                try? FileManager.default.moveItem(at: fileURL, to: backupURL)
                diagnostics.append(
                    "Backed up the unreadable rules file to \(backupURL.lastPathComponent) and started a fresh one."
                )
            }
        }

        table.append(rule)
        try save(table, forWorkspaceRoot: root)
        return diagnostics
    }

    public func save(_ table: PermissionRuleTable, forWorkspaceRoot root: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = WirePayload(version: Self.currentVersion, rules: table.rules)
        try encoder.encode(payload).write(to: fileURL(forWorkspaceRoot: root), options: .atomic)
    }

    // MARK: - Tolerant decoding

    private struct WirePayload: Codable {
        var version: Int
        var rules: [PermissionRule]
    }

    private struct LenientPayload: Decodable {
        var version: Int
        var rules: [LenientRule]
    }

    /// Wraps each rule so one malformed entry degrades to a diagnostic instead of discarding the
    /// whole file.
    private struct LenientRule: Decodable {
        var rule: PermissionRule?

        init(from decoder: Decoder) throws {
            rule = try? PermissionRule(from: decoder)
        }
    }

    private static func decode(_ data: Data, fileName: String) -> LoadOutcome {
        let payload: LenientPayload
        do {
            payload = try JSONDecoder().decode(LenientPayload.self, from: data)
        } catch {
            return LoadOutcome(
                result: PermissionRuleLoadResult(diagnostics: [
                    "Permission rules file \(fileName) is not valid JSON; using no saved rules."
                ]),
                wasCorrupt: true
            )
        }
        guard payload.version <= currentVersion else {
            return LoadOutcome(
                result: PermissionRuleLoadResult(diagnostics: [
                    "Permission rules file \(fileName) uses newer format version \(payload.version); using no saved rules."
                ]),
                wasCorrupt: false
            )
        }

        var diagnostics: [String] = []
        var rules: [PermissionRule] = []
        var droppedRules = 0
        for lenient in payload.rules {
            guard let rule = lenient.rule else {
                droppedRules += 1
                continue
            }
            if rule.match == .pattern, patternExceedsCap(rule) {
                diagnostics.append(
                    "Ignoring an oversized wildcard pattern in \(fileName) (patterns are capped at \(PermissionWildcardPattern.maxPatternScalarCount) characters)."
                )
            }
            rules.append(rule)
        }
        if droppedRules > 0 {
            diagnostics.append("Skipped \(droppedRules) malformed rule\(droppedRules == 1 ? "" : "s") in \(fileName).")
        }
        if rules.count > PermissionRuleTable.maxRuleCount {
            diagnostics.append(
                "Permission rules file \(fileName) has \(rules.count) rules; only the first \(PermissionRuleTable.maxRuleCount) are used."
            )
        }
        return LoadOutcome(
            result: PermissionRuleLoadResult(table: PermissionRuleTable(rules: rules), diagnostics: diagnostics),
            wasCorrupt: false
        )
    }

    private struct LoadOutcome {
        var result: PermissionRuleLoadResult
        var wasCorrupt: Bool
    }

    private static func decodedVersion(_ data: Data) -> Int? {
        struct VersionOnly: Decodable { var version: Int }
        return (try? JSONDecoder().decode(VersionOnly.self, from: data))?.version
    }

    private static func patternExceedsCap(_ rule: PermissionRule) -> Bool {
        rule.action.unicodeScalars.count > PermissionWildcardPattern.maxPatternScalarCount
            || rule.resource.unicodeScalars.count > PermissionWildcardPattern.maxPatternScalarCount
    }

    private static func backupURL(for fileURL: URL) -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
    }

    // MARK: - Workspace keying

    private static func sanitizedComponent(_ component: String) -> String {
        let allowed = component.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }
            return "_"
        }
        let name = String(allowed.prefix(40))
        return name.isEmpty ? "project" : name
    }

    private static func fnv1a64Hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

extension PermissionRuleFileStore: PermissionRulesProviding {
    /// Review-time reads go straight to disk (rule tables are tiny; a tool step already spans LLM
    /// round-trips), so a rule saved a moment ago — possibly by another window — always applies to
    /// the next gate. Diagnostics are dropped here; the save path surfaces them.
    public func ruleTable(forWorkspaceRoot root: URL) -> PermissionRuleTable {
        load(forWorkspaceRoot: root).table
    }
}
