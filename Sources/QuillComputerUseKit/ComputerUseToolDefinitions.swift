import QuillCodeCore

public extension ToolDefinition {
    static let computerUseDefinitions: [ToolDefinition] = [
        .computerScreenshot,
        .computerClick,
        .computerType,
        .computerScroll,
        .computerMove,
        .computerKey
    ]

    static let computerScreenshot = ToolDefinition(
        name: "host.computer.screenshot",
        description: "Capture a screenshot of the active desktop.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .computer,
        risk: .read
    )

    static let computerClick = ToolDefinition(
        name: "host.computer.click",
        description: "Click a point on the active desktop.",
        parametersJSON: #"{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"}},"required":["x","y"]}"#,
        host: .computer,
        risk: .destructive
    )

    static let computerType = ToolDefinition(
        name: "host.computer.type",
        description: "Type text into the focused application.",
        parametersJSON: #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#,
        host: .computer,
        risk: .destructive
    )

    static let computerScroll = ToolDefinition(
        name: "host.computer.scroll",
        description: "Scroll the active desktop view by a delta.",
        parametersJSON: #"{"type":"object","properties":{"dx":{"type":"integer"},"dy":{"type":"integer"}}}"#,
        host: .computer,
        risk: .destructive
    )

    static let computerMove = ToolDefinition(
        name: "host.computer.move",
        description: "Move the cursor to a point on the active desktop.",
        parametersJSON: #"{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"}},"required":["x","y"]}"#,
        host: .computer,
        risk: .destructive
    )

    static let computerKey = ToolDefinition(
        name: "host.computer.key",
        description: "Press a keyboard key or shortcut in the focused application.",
        parametersJSON: #"{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}"#,
        host: .computer,
        risk: .destructive
    )
}
