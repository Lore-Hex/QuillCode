import QuillCodeCore

public extension ToolDefinition {
    static let webFetch = ToolDefinition(
        name: "host.web.fetch",
        description: """
        Fetch a public http(s) URL with GET and return its content as markdown. Use this to pull a docs \
        page, RFC, changelog, or error-report link into context. HTML is converted to markdown (headings, \
        links, lists, code blocks, tables); markdown and plain-text responses pass through; binary content \
        is refused. Responses are capped at 5 MB and long pages are truncated with a marker. Requests to \
        private, loopback, or link-local hosts are refused; redirects are re-checked against the same rules. \
        For pages behind bot protection or requiring JavaScript, use host.browser.open instead.
        """,
        parametersJSON: """
        {"type":"object","properties":{"url":{"type":"string","description":"Absolute http or https URL to fetch."}},"required":["url"]}
        """,
        host: .local,
        risk: .read
    )
}
