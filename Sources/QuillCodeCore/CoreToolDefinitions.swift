import Foundation

public extension ToolDefinition {
    static let planUpdate = ToolDefinition(
        name: "host.plan.update",
        description: """
        Update the visible task plan for the current thread. Use this before or during multi-step work so the Activity \
        pane reflects the model-authored plan. Provide 1-12 concise steps and at most one in_progress item.
        """,
        parametersJSON: """
        {"type":"object","properties":{"explanation":{"type":"string"},"plan":{"type":"array","minItems":1,"maxItems":12,"items":{"type":"object","properties":{"step":{"type":"string"},"status":{"type":"string","enum":["pending","in_progress","completed"]},"detail":{"type":"string"}},"required":["step","status"]}}},"required":["plan"]}
        """,
        host: .local,
        risk: .read
    )

    static let handoffUpdate = ToolDefinition(
        name: "host.handoff.update",
        description: """
        Update the Activity pane handoff summary for the current thread. Use this when a task reaches a handoff point \
        or when the next agent/user needs a concise summary of current state, decisions, verification, and remaining \
        steps.
        """,
        parametersJSON: """
        {"type":"object","properties":{"summary":{"type":"string","description":"Concise handoff summary for the current task state."},"nextSteps":{"type":"array","maxItems":8,"items":{"type":"string"},"description":"Optional ordered next steps for a future continuation."}},"required":["summary"]}
        """,
        host: .local,
        risk: .read
    )

    static let subagentsUpdate = ToolDefinition(
        name: "host.subagents.update",
        description: """
        Update visible subagent progress for an explicitly requested parallel-agent workflow. Use this only when the \
        user asks to spawn, delegate to, or run parallel subagents. Include each subagent's role, status, and concise \
        summary so the Activity pane can show progress without polluting the main transcript.
        """,
        parametersJSON: """
        {"type":"object","properties":{"objective":{"type":"string","description":"Optional shared objective for the subagent workflow."},"subagents":{"type":"array","minItems":1,"maxItems":12,"items":{"type":"object","properties":{"name":{"type":"string","description":"Short stable label such as Security reviewer, Test scout, or Frontend/Verifier for nested plans."},"groupPath":{"type":"array","maxItems":4,"items":{"type":"string"},"description":"Optional parent path for nested plans, for example [\\"Frontend\\"] when name is Frontend/Verifier."},"role":{"type":"string","description":"What this subagent is responsible for."},"status":{"type":"string","enum":["queued","running","blocked","completed","cancelled","failed"]},"summary":{"type":"string","description":"Current finding, blocker, or result summary."}},"required":["name","role","status"]}}},"required":["subagents"]}
        """,
        host: .local,
        risk: .read
    )

    static let browserInspect = ToolDefinition(
        name: "host.browser.inspect",
        description: """
        Inspect the current QuillCode browser preview page, including URL, title, inspection depth, summary, visible \
        page outline, text snippet, and attached browser comments.
        """,
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .browser,
        risk: .read
    )

    static let browserOpen = ToolDefinition(
        name: "host.browser.open",
        description: """
        Open an http, https, file, localhost, or project-relative page in the QuillCode browser preview, then return \
        the browser snapshot that is available for agent review.
        """,
        parametersJSON: """
        {"type":"object","properties":{"url":{"type":"string","description":"The page to open. Accepts http, https, file, localhost, or project-relative paths."}},"required":["url"]}
        """,
        host: .browser,
        risk: .read
    )

    static let browserClick = ToolDefinition(
        name: "host.browser.click",
        description: """
        Click an element in the visible QuillCode browser session by CSS selector. Use after opening a browser session \
        when the user asks to interact with the page. Do not use this for hidden data extraction or broad scripting.
        """,
        parametersJSON: """
        {"type":"object","properties":{"selector":{"type":"string","description":"CSS selector for the element to click in the visible browser session."}},"required":["selector"]}
        """,
        host: .browser,
        risk: .append
    )

    static let browserType = ToolDefinition(
        name: "host.browser.type",
        description: """
        Type text into an editable element in the visible QuillCode browser session by CSS selector. Set submit to true \
        only when the user asked to submit the form or press Enter.
        """,
        parametersJSON: """
        {"type":"object","properties":{"selector":{"type":"string","description":"CSS selector for an input, textarea, select, or contenteditable element."},"text":{"type":"string","description":"Text to enter."},"submit":{"type":"boolean","description":"Whether to submit the containing form or press Enter after typing."}},"required":["selector","text"]}
        """,
        host: .browser,
        risk: .append
    )

    static let memoryRemember = ToolDefinition(
        name: "host.memory.remember",
        description: """
        Save a durable user preference or stable project fact as explicit memory for future turns. Use only when the \
        user asks QuillCode to remember something, or when the preference/fact is clearly stable and useful. Never \
        save credentials, tokens, passwords, private keys, or other secrets.
        """,
        parametersJSON: """
        {"type":"object","properties":{"content":{"type":"string","description":"The durable preference or stable fact to remember. Do not include credentials, tokens, passwords, private keys, or other secrets."},"reason":{"type":"string","description":"Optional short rationale for why this should become durable memory."}},"required":["content"]}
        """,
        host: .local,
        risk: .append
    )
}
