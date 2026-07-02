import Foundation

/// A 0-based line/character position, as LSP uses on the wire. The agent-facing tool speaks in
/// 1-based lines (matching `host.file.read`'s numbering), so conversions live at the tool boundary,
/// not here.
public struct LSPPosition: Equatable, Sendable {
    public var line: Int
    public var character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }

    /// The wire form. LSP positions are always 0-based.
    public var wire: [String: Any] { ["line": line, "character": character] }

    /// Parses a position out of an untrusted JSON object, defaulting missing/garbage fields to 0
    /// rather than failing — a server that omits a field should not sink the whole response.
    public static func parse(_ any: Any?) -> LSPPosition? {
        guard let object = any as? [String: Any] else { return nil }
        return LSPPosition(
            line: LSPJSON.int(object["line"]) ?? 0,
            character: LSPJSON.int(object["character"]) ?? 0
        )
    }
}

/// A `[start, end)` span within a document.
public struct LSPRange: Equatable, Sendable {
    public var start: LSPPosition
    public var end: LSPPosition

    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }

    public var wire: [String: Any] { ["start": start.wire, "end": end.wire] }

    public static func parse(_ any: Any?) -> LSPRange? {
        guard let object = any as? [String: Any] else { return nil }
        let start = LSPPosition.parse(object["start"]) ?? LSPPosition(line: 0, character: 0)
        let end = LSPPosition.parse(object["end"]) ?? start
        return LSPRange(start: start, end: end)
    }
}

/// A resolved code location: a file plus a span. `path` is the workspace-relative path when the
/// location falls inside the workspace, else the absolute path (locations can legitimately point at
/// SDK/toolchain files outside the project).
public struct LSPLocation: Equatable, Sendable {
    public var uri: String
    public var range: LSPRange

    public init(uri: String, range: LSPRange) {
        self.uri = uri
        self.range = range
    }

    public static func parse(_ any: Any?) -> LSPLocation? {
        guard let object = any as? [String: Any] else { return nil }
        // Servers return either a `Location` (uri+range) or a `LocationLink` (targetUri+targetRange).
        let uri = (object["uri"] as? String) ?? (object["targetUri"] as? String)
        guard let uri, !uri.isEmpty else { return nil }
        let range = LSPRange.parse(object["range"])
            ?? LSPRange.parse(object["targetRange"])
            ?? LSPRange(start: .init(line: 0, character: 0), end: .init(line: 0, character: 0))
        return LSPLocation(uri: uri, range: range)
    }

    /// Parses a `Location | Location[] | LocationLink[] | null` response into a flat list.
    public static func parseList(_ any: Any?) -> [LSPLocation] {
        if let array = any as? [[String: Any]] {
            return array.compactMap { parse($0) }
        }
        if let single = parse(any) {
            return [single]
        }
        return []
    }
}

/// Severity of a diagnostic, matching the LSP integer codes. Only errors and warnings are surfaced
/// to the model after a write (info/hints are noise for the "did I break it" question).
public enum LSPDiagnosticSeverity: Int, Sendable, Equatable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4

    var label: String {
        switch self {
        case .error: return "error"
        case .warning: return "warning"
        case .information: return "info"
        case .hint: return "hint"
        }
    }
}

/// One diagnostic from `textDocument/publishDiagnostics`.
public struct LSPDiagnostic: Equatable, Sendable {
    public var range: LSPRange
    public var severity: LSPDiagnosticSeverity
    public var message: String

    public init(range: LSPRange, severity: LSPDiagnosticSeverity, message: String) {
        self.range = range
        self.severity = severity
        self.message = message
    }

    public static func parse(_ any: Any?) -> LSPDiagnostic? {
        guard let object = any as? [String: Any] else { return nil }
        let message = (object["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !message.isEmpty else { return nil }
        let severity = LSPDiagnosticSeverity(rawValue: LSPJSON.int(object["severity"]) ?? 1) ?? .error
        let range = LSPRange.parse(object["range"])
            ?? LSPRange(start: .init(line: 0, character: 0), end: .init(line: 0, character: 0))
        return LSPDiagnostic(range: range, severity: severity, message: message)
    }
}

/// A symbol from `textDocument/documentSymbol` or `workspace/symbol`. Kept flat (name + kind + a
/// single location) so the tool output is a concise list the model can scan.
public struct LSPSymbol: Equatable, Sendable {
    public var name: String
    public var kind: Int
    public var location: LSPLocation
    public var containerName: String?

    public init(name: String, kind: Int, location: LSPLocation, containerName: String? = nil) {
        self.name = name
        self.kind = kind
        self.location = location
        self.containerName = containerName
    }

    /// Human-readable name of the LSP `SymbolKind` integer.
    public var kindLabel: String { LSPSymbolKind.label(for: kind) }
}

/// The subset of LSP `SymbolKind` names the tool prints. Unknown values fall back to "symbol" so a
/// forward-compatible server never yields a blank kind.
enum LSPSymbolKind {
    private static let names: [Int: String] = [
        1: "file", 2: "module", 3: "namespace", 4: "package", 5: "class", 6: "method",
        7: "property", 8: "field", 9: "constructor", 10: "enum", 11: "interface",
        12: "function", 13: "variable", 14: "constant", 15: "string", 16: "number",
        17: "boolean", 18: "array", 19: "object", 20: "key", 21: "null", 22: "enum-member",
        23: "struct", 24: "event", 25: "operator", 26: "type-parameter"
    ]

    static func label(for kind: Int) -> String { names[kind] ?? "symbol" }
}
