import Foundation
import QuillCodeCore
import QuillCodeSafety

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
        WorkspaceScopedStoreFileLocator.fileURL(directory: directory, workspaceRoot: root)
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
            // The file exists but is unreadable: fail safe (degraded), do NOT report "no rules".
            return PermissionRuleLoadResult(degraded: true, diagnostics: [
                Self.unreadableFileDiagnostic(fileName: fileURL.lastPathComponent, error: error)
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
            if loaded.hadUnrepresentableRules {
                // The file holds otherwise-valid rules this build can't represent (possibly a
                // deny). Rewriting on append would silently drop them, so refuse — the file is
                // left untouched.
                throw PermissionRuleStoreError.unrepresentableRules(count: loaded.unrepresentableRuleCount)
            }
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

    /// Wraps each rule so one bad entry degrades to a diagnostic instead of discarding the whole
    /// file — but distinguishes WHY a rule failed:
    /// - `.parsed` — a fully representable rule.
    /// - `.malformed` — structurally broken JSON (missing/mistyped `action`/`resource`/`decision`).
    ///   Dropped tolerantly; not degraded on its own.
    /// - `.unrepresentable` — a well-STRUCTURED rule whose `match` or `decision` is a real string
    ///   this build does not know (e.g. a newer build's `regex` match kind, or an extra decision,
    ///   written without bumping the file `version`, or a hand edit). We CANNOT know its intent —
    ///   it might be a deny — so the load is degraded (force-ask fail-safe) even though other rules
    ///   loaded fine.
    private enum LenientRule: Decodable {
        case parsed(PermissionRule)
        case malformed
        case unrepresentable

        /// The rule's fields decoded permissively — enum-valued fields kept as raw strings so we can
        /// tell "absent" from "present but unknown".
        private struct RawRule: Decodable {
            var action: String?
            var resource: String?
            var match: String?
            var decision: String?
        }

        init(from decoder: Decoder) throws {
            if let rule = try? PermissionRule(from: decoder) {
                self = .parsed(rule)
                return
            }
            // PermissionRule failed. Decide whether it was garbage or an unknown enum value.
            guard let raw = try? RawRule(from: decoder),
                  raw.action != nil, raw.resource != nil
            else {
                // Missing/mistyped required string fields → structurally malformed.
                self = .malformed
                return
            }
            let unknownMatch = raw.match.map { PermissionRuleMatchKind(rawValue: $0) == nil } ?? false
            let unknownDecision: Bool
            if let decision = raw.decision {
                unknownDecision = PermissionRuleDecision(rawValue: decision) == nil
            } else {
                // `decision` is required by PermissionRule; its absence is structural malformation,
                // not an unknown value.
                unknownDecision = false
            }
            self = (unknownMatch || unknownDecision) ? .unrepresentable : .malformed
        }
    }

    private static func decode(_ data: Data, fileName: String) -> LoadOutcome {
        let payload: LenientPayload
        do {
            payload = try JSONDecoder().decode(LenientPayload.self, from: data)
        } catch {
            // Not valid JSON: fail safe (degraded). We cannot know what a prior rule said.
            return LoadOutcome(
                result: PermissionRuleLoadResult(degraded: true, diagnostics: [
                    "Permission rules file \(fileName) is not valid JSON; asking for confirmation until it is repaired."
                ]),
                wasCorrupt: true
            )
        }
        guard payload.version <= currentVersion else {
            // Newer format: fail safe (degraded). A rule this build cannot represent might be a
            // deny; do not auto-approve past it.
            return LoadOutcome(
                result: PermissionRuleLoadResult(degraded: true, diagnostics: [
                    Self.newerVersionDiagnostic(fileName: fileName, version: payload.version)
                ]),
                wasCorrupt: false
            )
        }

        var diagnostics: [String] = []
        var rules: [PermissionRule] = []
        var droppedRules = 0
        var unrepresentableRules = 0
        for lenient in payload.rules {
            switch lenient {
            case .parsed(let rule):
                if rule.match == .pattern, patternExceedsCap(rule) {
                    diagnostics.append(Self.oversizedPatternDiagnostic(fileName: fileName))
                }
                rules.append(rule)
            case .malformed:
                droppedRules += 1
            case .unrepresentable:
                unrepresentableRules += 1
            }
        }
        if droppedRules > 0 {
            diagnostics.append("Skipped \(droppedRules) malformed rule\(droppedRules == 1 ? "" : "s") in \(fileName).")
        }
        // A rule with a well-formed structure but an unknown `match`/`decision` value could be a
        // DENY this build cannot represent. Silently dropping it while reporting a healthy load
        // would let a matching call auto-approve in Auto — so ANY unrepresentable rule degrades the
        // load (force-ask fail-safe), even though other rules parsed fine.
        if unrepresentableRules > 0 {
            return LoadOutcome(
                result: PermissionRuleLoadResult(
                    table: PermissionRuleTable(rules: rules),
                    degraded: true,
                    diagnostics: diagnostics + [
                        Self.unrepresentableRulesDiagnostic(count: unrepresentableRules, fileName: fileName)
                    ]
                ),
                wasCorrupt: false,
                unrepresentableRuleCount: unrepresentableRules
            )
        }
        // A single structurally-malformed rule is skipped tolerantly (the rest still load) — a
        // partial read, not an unreadable file, so NOT degraded. But if EVERY rule was malformed
        // the file is effectively corrupt: fail safe.
        let allRulesMalformed = !payload.rules.isEmpty && rules.isEmpty
        if allRulesMalformed {
            return LoadOutcome(
                result: PermissionRuleLoadResult(degraded: true, diagnostics: diagnostics + [
                    "Every rule in \(fileName) was malformed; asking for confirmation until it is repaired."
                ]),
                wasCorrupt: true
            )
        }
        if rules.count > PermissionRuleTable.maxRuleCount {
            diagnostics.append(Self.ruleCountCapDiagnostic(count: rules.count, fileName: fileName))
        }
        return LoadOutcome(
            result: PermissionRuleLoadResult(table: PermissionRuleTable(rules: rules), diagnostics: diagnostics),
            wasCorrupt: false
        )
    }

    private struct LoadOutcome {
        var result: PermissionRuleLoadResult
        var wasCorrupt: Bool
        /// How many rules had an unknown match/decision. Distinct from `wasCorrupt` (garbage JSON):
        /// the file is otherwise valid, so append must REFUSE (not back-up-and-rewrite) to avoid
        /// silently dropping the unrepresentable — possibly deny — rules.
        var unrepresentableRuleCount: Int = 0

        var hadUnrepresentableRules: Bool { unrepresentableRuleCount > 0 }
    }

    private static func decodedVersion(_ data: Data) -> Int? {
        struct VersionOnly: Decodable { var version: Int }
        return (try? JSONDecoder().decode(VersionOnly.self, from: data))?.version
    }

    private static func patternExceedsCap(_ rule: PermissionRule) -> Bool {
        rule.action.unicodeScalars.count > PermissionWildcardPattern.maxPatternScalarCount
            || rule.resource.unicodeScalars.count > PermissionWildcardPattern.maxPatternScalarCount
    }

    private static func unreadableFileDiagnostic(fileName: String, error: Error) -> String {
        "Could not read permission rules file \(fileName): \(error.localizedDescription). " +
            "Asking for confirmation until it is readable."
    }

    private static func newerVersionDiagnostic(fileName: String, version: Int) -> String {
        "Permission rules file \(fileName) uses newer format version \(version); " +
            "asking for confirmation until this build is updated."
    }

    private static func oversizedPatternDiagnostic(fileName: String) -> String {
        "Ignoring an oversized wildcard pattern in \(fileName) " +
            "(patterns are capped at \(PermissionWildcardPattern.maxPatternScalarCount) characters)."
    }

    private static func unrepresentableRulesDiagnostic(count: Int, fileName: String) -> String {
        "\(count) rule\(count == 1 ? "" : "s") in \(fileName) use an unknown match/decision " +
            "this build can't represent; asking for confirmation until this build is updated " +
            "or the file is repaired."
    }

    private static func ruleCountCapDiagnostic(count: Int, fileName: String) -> String {
        "Permission rules file \(fileName) has \(count) rules; only the last " +
            "\(PermissionRuleTable.maxRuleCount) (highest priority) are used."
    }

    private static func backupURL(for fileURL: URL) -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
    }

}

extension PermissionRuleFileStore: PermissionRulesProviding {
    /// Review-time reads go straight to disk (rule tables are tiny; a tool step already spans LLM
    /// round-trips), so a rule saved a moment ago — possibly by another window — always applies to
    /// the next gate. The `degraded` flag is propagated so a broken rules file fails safe (the
    /// reviewer forces an approval gate) rather than silently reading as "no rules".
    public func loadRuleOutcome(forWorkspaceRoot root: URL) -> PermissionRuleLoadOutcome {
        let result = load(forWorkspaceRoot: root)
        return PermissionRuleLoadOutcome(
            table: result.table,
            degraded: result.degraded,
            diagnostics: result.diagnostics
        )
    }
}
