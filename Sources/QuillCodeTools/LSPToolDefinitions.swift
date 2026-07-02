import QuillCodeCore

public extension ToolDefinition {
    static let lspDefinition = ToolDefinition(
        name: "host.lsp.definition",
        description: """
        Jump to the definition of the symbol at a position, via the language server. \
        `path` is a workspace file; `line` is 1-based (matching host.file.read numbering); \
        `character` is the 0-based column. Returns the defining file:line locations.
        """,
        parametersJSON: LSPToolParameterSchema.position,
        host: .local,
        risk: .read
    )

    static let lspReferences = ToolDefinition(
        name: "host.lsp.references",
        description: """
        Find all references to the symbol at a position, project-wide, via the language server. \
        `line` is 1-based; `character` is the 0-based column. Returns file:line locations.
        """,
        parametersJSON: LSPToolParameterSchema.references,
        host: .local,
        risk: .read
    )

    static let lspHover = ToolDefinition(
        name: "host.lsp.hover",
        description: """
        Get hover info (type, signature, docs) for the symbol at a position, via the language \
        server. `line` is 1-based; `character` is the 0-based column.
        """,
        parametersJSON: LSPToolParameterSchema.position,
        host: .local,
        risk: .read
    )

    static let lspDocumentSymbol = ToolDefinition(
        name: "host.lsp.document_symbol",
        description: "List the symbols (types, functions, properties) defined in a file, via the language server.",
        parametersJSON: LSPToolParameterSchema.path,
        host: .local,
        risk: .read
    )

    static let lspWorkspaceSymbol = ToolDefinition(
        name: "host.lsp.workspace_symbol",
        description: "Search the whole project for symbols matching a name, via the language server.",
        parametersJSON: LSPToolParameterSchema.query,
        host: .local,
        risk: .read
    )
}

private enum LSPToolParameterSchema {
    static let position = ToolParameterSchema.object(
        properties: positionProperties,
        required: ["path", "line", "character"]
    )

    static let references = ToolParameterSchema.object(
        properties: positionProperties.merging([
            "includeDeclaration": .boolean()
        ]) { current, _ in current },
        required: ["path", "line", "character"]
    )

    static let path = ToolParameterSchema.object(
        properties: ["path": .string()],
        required: ["path"]
    )

    static let query = ToolParameterSchema.object(
        properties: ["query": .string()],
        required: ["query"]
    )

    private static let positionProperties: [String: ToolParameterProperty] = [
        "path": .string(),
        "line": .integer(description: "1-based line"),
        "character": .integer(description: "0-based column")
    ]
}
