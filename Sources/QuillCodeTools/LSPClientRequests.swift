import Foundation

public extension LSPClient {
    /// `textDocument/definition`.
    func definition(
        path: String,
        line: Int,
        character: Int,
        timeout: TimeInterval = 5.0
    ) throws -> [LSPLocation] {
        let result = try request(
            method: "textDocument/definition",
            params: positionParams(path: path, line: line, character: character),
            timeout: timeout
        )
        return LSPLocation.parseList(result)
    }

    /// `textDocument/references`.
    func references(
        path: String,
        line: Int,
        character: Int,
        includeDeclaration: Bool = true,
        timeout: TimeInterval = 5.0
    ) throws -> [LSPLocation] {
        var params = positionParams(path: path, line: line, character: character)
        params["context"] = ["includeDeclaration": includeDeclaration]
        let result = try request(method: "textDocument/references", params: params, timeout: timeout)
        return LSPLocation.parseList(result)
    }

    /// `textDocument/hover`, flattened to plain text.
    func hover(
        path: String,
        line: Int,
        character: Int,
        timeout: TimeInterval = 5.0
    ) throws -> String? {
        let result = try request(
            method: "textDocument/hover",
            params: positionParams(path: path, line: line, character: character),
            timeout: timeout
        )
        return LSPHoverText.extract(from: result)
    }

    /// `textDocument/documentSymbol` — the symbols defined in one file.
    func documentSymbols(path: String, timeout: TimeInterval = 5.0) throws -> [LSPSymbol] {
        let result = try request(
            method: "textDocument/documentSymbol",
            params: ["textDocument": ["uri": LSPURI.from(path: path)]],
            timeout: timeout
        )
        return LSPSymbolParser.documentSymbols(from: result, uri: LSPURI.from(path: path))
    }

    /// `workspace/symbol` — project-wide symbol search by name.
    func workspaceSymbols(query: String, timeout: TimeInterval = 5.0) throws -> [LSPSymbol] {
        let result = try request(method: "workspace/symbol", params: ["query": query], timeout: timeout)
        return LSPSymbolParser.workspaceSymbols(from: result)
    }

    /// `textDocument/formatting`. Returns the ordered text edits the server would apply, or an empty
    /// array when the file is already formatted. `nil` capability check is the caller's job via
    /// `supportsFormatting`.
    func formatting(
        path: String,
        tabSize: Int = 4,
        insertSpaces: Bool = true,
        timeout: TimeInterval = 5.0
    ) throws -> [LSPTextEdit] {
        let result = try request(method: "textDocument/formatting", params: [
            "textDocument": ["uri": LSPURI.from(path: path)],
            "options": ["tabSize": tabSize, "insertSpaces": insertSpaces]
        ], timeout: timeout)
        return LSPTextEdit.parseList(result)
    }
}
