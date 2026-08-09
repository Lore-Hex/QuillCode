import QuillCodeCore

public extension ToolDefinition {
    static let pdfMerge = ToolDefinition(
        name: "host.pdf.merge",
        description: """
        Merge workspace PDF files into one real PDF without installing dependencies. Inputs are \
        appended in the supplied order. The result includes one outline bookmark per input and, by \
        default, a visible table-of-contents page. Use `labels` to control bookmark and table labels; \
        otherwise input filenames are used. Read or list the source files first, then read the merged \
        output with host.file.read to verify it.
        """,
        parametersJSON: """
        {"type":"object","properties":{"inputs":{"type":"array","items":{"type":"string"},\
        "description":"Ordered workspace-relative PDF paths to merge."},"output":{"type":"string",\
        "description":"Workspace-relative .pdf path to create."},"labels":{"type":"array","items":\
        {"type":"string"},"description":"Optional labels matching inputs one-for-one."},\
        "title":{"type":"string","description":"Optional document and contents-page title."},\
        "includeTableOfContents":{"type":"boolean","description":"Add a visible contents page; \
        defaults to true."}},"required":["inputs","output"]}
        """,
        host: .local,
        risk: .append
    )
}
