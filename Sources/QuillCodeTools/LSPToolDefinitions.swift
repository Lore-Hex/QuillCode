import QuillCodeCore

public extension ToolDefinition {
    static let lspDefinition = ToolDefinition(
        name: "host.lsp.definition",
        description: """
        Jump to the definition of the symbol at a position, via the language server. \
        `path` is a workspace file; `line` is 1-based (matching host.file.read numbering); \
        `character` is the 0-based column. Returns the defining file:line locations.
        """,
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"line":{"type":"integer","description":"1-based line"},"character":{"type":"integer","description":"0-based column"}},"required":["path","line","character"]}"#,
        host: .local,
        risk: .read
    )

    static let lspReferences = ToolDefinition(
        name: "host.lsp.references",
        description: """
        Find all references to the symbol at a position, project-wide, via the language server. \
        `line` is 1-based; `character` is the 0-based column. Returns file:line locations.
        """,
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"line":{"type":"integer","description":"1-based line"},"character":{"type":"integer","description":"0-based column"},"includeDeclaration":{"type":"boolean"}},"required":["path","line","character"]}"#,
        host: .local,
        risk: .read
    )

    static let lspHover = ToolDefinition(
        name: "host.lsp.hover",
        description: """
        Get hover info (type, signature, docs) for the symbol at a position, via the language \
        server. `line` is 1-based; `character` is the 0-based column.
        """,
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"line":{"type":"integer","description":"1-based line"},"character":{"type":"integer","description":"0-based column"}},"required":["path","line","character"]}"#,
        host: .local,
        risk: .read
    )

    static let lspDocumentSymbol = ToolDefinition(
        name: "host.lsp.document_symbol",
        description: "List the symbols (types, functions, properties) defined in a file, via the language server.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}"#,
        host: .local,
        risk: .read
    )

    static let lspWorkspaceSymbol = ToolDefinition(
        name: "host.lsp.workspace_symbol",
        description: "Search the whole project for symbols matching a name, via the language server.",
        parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#,
        host: .local,
        risk: .read
    )
}
