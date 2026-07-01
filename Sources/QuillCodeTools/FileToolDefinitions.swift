import QuillCodeCore

public extension ToolDefinition {
    static let fileRead = ToolDefinition(
        name: "host.file.read",
        description: "Read a UTF-8 file inside the project workspace.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}"#,
        host: .local,
        risk: .read
    )

    static let fileList = ToolDefinition(
        name: "host.file.list",
        description: """
        List immediate files and directories inside a workspace directory. Returns bounded structured \
        entries with name, path, kind, size, and hidden-file metadata.
        """,
        parametersJSON: """
        {"type":"object","properties":{"path":{"type":"string","description":"Optional workspace-relative \
        directory to list. Defaults to the workspace root."},"includeHidden":{"type":"boolean","description":\
        "Whether to include dotfiles and other hidden entries. Defaults to false."},"maxEntries":{"type":\
        "integer","minimum":1,"maximum":500,"description":"Maximum number of directory entries to return. \
        Defaults to 200."}}}
        """,
        host: .local,
        risk: .read
    )

    static let fileSearch = ToolDefinition(
        name: "host.file.search",
        description: """
        Search UTF-8 text files inside the project workspace for a literal query. Returns bounded file, \
        line, and preview matches; skips heavy dependency/build directories and large or binary files.
        """,
        parametersJSON: """
        {"type":"object","properties":{"query":{"type":"string","description":"Literal text to search for."},\
        "path":{"type":"string","description":"Optional workspace-relative file or directory to search. \
        Defaults to the workspace root."},"maxResults":{"type":"integer","minimum":1,"maximum":100,\
        "description":"Maximum number of matches to return. Defaults to 20."}},"required":["query"]}
        """,
        host: .local,
        risk: .read
    )

    static let fileWrite = ToolDefinition(
        name: "host.file.write",
        description: "Write a UTF-8 file inside the project workspace.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}"#,
        host: .local,
        risk: .append
    )
}
