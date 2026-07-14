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

    static let workflowRecordingDefinitions: [ToolDefinition] = [
        .workflowRecordStart,
        .workflowRecordStop
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

    static let workflowRecordStart = ToolDefinition(
        name: "host.workflow.record.start",
        description: "Start a consented Computer Use recording of screenshots and typed text across apps. "
            + "The capture is sent to TrustedRouter to create a reusable skill; password fields are redacted. "
            + "Call this immediately when the user asks to record a skill; do not merely promise to start.",
        parametersJSON: #"{"type":"object","properties":{"goal":{"type":"string","description":"What the reusable workflow should accomplish."}},"required":["goal"]}"#,
        host: .computer,
        risk: .destructive
    )

    static let workflowRecordStop = ToolDefinition(
        name: "host.workflow.record.stop",
        description: "Stop the active workflow recording and return bounded actions plus screenshot artifacts for drafting the skill in the same turn.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .computer,
        risk: .read
    )
}
