import QuillCodeCore

public extension ToolDefinition {
    static let chartRender = ToolDefinition(
        name: "host.chart.render",
        description: """
        Render a real PNG bar chart inside the project workspace without external plotting libraries. \
        Pass category labels plus a `series` object whose keys are legend labels and whose values are \
        comma-separated numbers. Use `seriesOrder` to control legend/stack order. Supports stacked \
        (default) and grouped bars, optional title/axis labels/colors, and 800x450 or larger output. \
        After rendering, read the PNG path with host.file.read to verify its dimensions and format.
        """,
        parametersJSON: """
        {"type":"object","properties":{"path":{"type":"string","description":"Workspace-relative \
        output path ending in .png."},"title":{"type":"string"},"categories":{"type":"array",\
        "items":{"type":"string"},"minItems":1,"maxItems":24},"series":{"type":"object",\
        "additionalProperties":{"type":"string"},"description":"Legend label to comma-separated \
        numeric values, one per category. Example values: East=10,20,30,40."},"seriesOrder":\
        {"type":"array","items":{"type":"string"}},"stacked":{"type":"boolean","default":true},\
        "colors":{"type":"object","additionalProperties":{"type":"string"},"description":"Optional \
        series label to #RRGGBB color."},"xAxisLabel":{"type":"string"},"yAxisLabel":{"type":"string"},\
        "width":{"type":"integer","minimum":800,"maximum":2400},"height":{"type":"integer",\
        "minimum":450,"maximum":1600}},"required":["path","categories","series"]}
        """,
        host: .local,
        risk: .append
    )
}
