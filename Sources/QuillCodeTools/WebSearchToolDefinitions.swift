import QuillCodeCore

public extension ToolDefinition {
    static let webSearch = ToolDefinition(
        name: "host.web.search",
        description: """
        Search the public web for a query and return a short, ranked list of results (title, URL, \
        and a one- or two-line snippet). Use this to look up an API, an error message, a library \
        version, changelog, or any current fact, then follow the most relevant result with \
        host.web.fetch to read the full page. Provide a focused query the way you would type it \
        into a search engine. Results are capped (up to 10) and routed through TrustedRouter, which \
        selects the search provider. This does NOT return full page text — fetch a result URL for \
        that. Prefer this over driving the browser pane for a quick lookup.
        """,
        parametersJSON: """
        {"type":"object","properties":{"query":{"type":"string","description":"The search query, phrased as you would type it into a search engine."},"maxResults":{"type":"integer","description":"Maximum number of results to return (1-10, default 5)."}},"required":["query"]}
        """,
        host: .local,
        risk: .read
    )
}
