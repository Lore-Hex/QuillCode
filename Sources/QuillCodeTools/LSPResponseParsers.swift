import Foundation

/// Flattens the several shapes a `textDocument/hover` result can take (a `MarkupContent` object, a
/// legacy `MarkedString`, or an array of either) into a single plain-text string. Returns `nil` for
/// an empty/`null` hover so the tool can say "no hover info" rather than print an empty box.
enum LSPHoverText {
    static func extract(from any: Any?) -> String? {
        guard let object = any as? [String: Any] else { return nil }
        let contents = object["contents"]
        let text = stringify(contents).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func stringify(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let object as [String: Any]:
            // `MarkupContent { kind, value }` or legacy `MarkedString { language, value }`.
            return (object["value"] as? String) ?? ""
        case let array as [Any]:
            return array.map { stringify($0) }.filter { !$0.isEmpty }.joined(separator: "\n")
        default:
            return ""
        }
    }
}

/// Parses `documentSymbol` (both the flat `SymbolInformation[]` form and the nested
/// `DocumentSymbol[]` tree) and `workspace/symbol` responses into a flat `[LSPSymbol]`.
enum LSPSymbolParser {
    /// `textDocument/documentSymbol` returns either `SymbolInformation[]` (each with its own
    /// `location`) or a `DocumentSymbol[]` tree (with `range`/`selectionRange` and `children`). We
    /// flatten the tree, attaching the file `uri` since tree nodes carry only ranges.
    static func documentSymbols(from any: Any?, uri: String) -> [LSPSymbol] {
        guard let array = any as? [[String: Any]] else { return [] }
        var symbols: [LSPSymbol] = []
        for node in array {
            appendSymbols(from: node, uri: uri, container: nil, into: &symbols)
        }
        return symbols
    }

    /// `workspace/symbol` returns `SymbolInformation[]` (or `WorkspaceSymbol[]`), each carrying its
    /// own `location`.
    static func workspaceSymbols(from any: Any?) -> [LSPSymbol] {
        guard let array = any as? [[String: Any]] else { return [] }
        return array.compactMap { informationSymbol(from: $0) }
    }

    private static func appendSymbols(
        from node: [String: Any],
        uri: String,
        container: String?,
        into symbols: inout [LSPSymbol]
    ) {
        guard let name = (node["name"] as? String), !name.isEmpty else { return }
        let kind = LSPJSON.int(node["kind"]) ?? 0

        if let location = node["location"] {
            // SymbolInformation shape.
            if let parsed = LSPLocation.parse(location) {
                symbols.append(LSPSymbol(name: name, kind: kind, location: parsed, containerName: node["containerName"] as? String))
            }
            return
        }

        // DocumentSymbol shape: use `selectionRange` (the identifier itself) for the reported location,
        // not `range` (the whole declaration span, which for a symbol with leading doc-comments or
        // attributes starts several lines above the declaration). Fall back to `range` then to origin.
        let range = LSPRange.parse(node["selectionRange"])
            ?? LSPRange.parse(node["range"])
            ?? LSPRange(start: .init(line: 0, character: 0), end: .init(line: 0, character: 0))
        symbols.append(LSPSymbol(
            name: name,
            kind: kind,
            location: LSPLocation(uri: uri, range: range),
            containerName: container
        ))
        if let children = node["children"] as? [[String: Any]] {
            for child in children {
                appendSymbols(from: child, uri: uri, container: name, into: &symbols)
            }
        }
    }

    private static func informationSymbol(from node: [String: Any]) -> LSPSymbol? {
        guard let name = (node["name"] as? String), !name.isEmpty,
              let location = LSPLocation.parse(node["location"])
        else { return nil }
        return LSPSymbol(
            name: name,
            kind: LSPJSON.int(node["kind"]) ?? 0,
            location: location,
            containerName: node["containerName"] as? String
        )
    }
}
