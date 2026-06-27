import Foundation

public enum ToolHost: String, Codable, Sendable {
    case local
    case browser
    case computer
    case plugin
    case mcp
}

public enum ToolRiskClass: String, Codable, Sendable {
    case read
    case append
    case destructive
}

public struct ToolDefinition: Codable, Sendable, Hashable {
    public var name: String
    public var description: String
    public var parametersJSON: String
    public var host: ToolHost
    public var risk: ToolRiskClass

    public init(
        name: String,
        description: String,
        parametersJSON: String,
        host: ToolHost = .local,
        risk: ToolRiskClass = .read
    ) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
        self.host = host
        self.risk = risk
    }
}

public struct ToolCall: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var argumentsJSON: String

    public init(id: String = "tool-\(UUID().uuidString)", name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public extension ToolCall {
    static let redactedEnvironmentValue = "<redacted>"

    func redactedForTranscript() -> ToolCall {
        let redactedArguments = Self.redactedArgumentsJSON(argumentsJSON)
        guard redactedArguments != argumentsJSON else {
            return self
        }
        return ToolCall(id: id, name: name, argumentsJSON: redactedArguments)
    }

    static func redactedArgumentsJSON(_ argumentsJSON: String) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return argumentsJSON
        }

        var didRedact = false
        for key in ["environment", "env"] where object[key] != nil {
            object[key] = redactedEnvironmentPayload(object[key])
            didRedact = true
        }
        guard didRedact,
              JSONSerialization.isValidJSONObject(object),
              let output = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              )
        else {
            return argumentsJSON
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func redactedEnvironmentPayload(_ payload: Any?) -> Any {
        guard let environment = payload as? [String: Any] else {
            return redactedEnvironmentValue
        }
        return Dictionary(uniqueKeysWithValues: environment.keys.sorted().map {
            ($0, redactedEnvironmentValue)
        })
    }
}

public struct ToolResult: Codable, Sendable, Hashable {
    public var ok: Bool
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32?
    public var error: String?
    public var artifacts: [String]

    public init(
        ok: Bool,
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32? = nil,
        error: String? = nil,
        artifacts: [String] = []
    ) {
        self.ok = ok
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.error = error
        self.artifacts = artifacts
    }
}

public struct BrowserInspectionComment: Codable, Sendable, Hashable {
    public var url: String
    public var text: String
    public var createdAt: Date

    public init(url: String, text: String, createdAt: Date) {
        self.url = url
        self.text = text
        self.createdAt = createdAt
    }
}

public enum BrowserInspectionDepth: String, Codable, Sendable, Hashable, CaseIterable {
    case metadataOnly = "metadata_only"
    case fileMetadata = "file_metadata"
    case staticHTMLSnapshot = "static_html_snapshot"
    case networkHTMLSnapshot = "network_html_snapshot"
    case liveDOMSnapshot = "live_dom_snapshot"

    public var label: String {
        switch self {
        case .metadataOnly:
            return "Metadata only"
        case .fileMetadata:
            return "File metadata"
        case .staticHTMLSnapshot:
            return "Static HTML snapshot"
        case .networkHTMLSnapshot:
            return "Network HTML snapshot"
        case .liveDOMSnapshot:
            return "Live DOM snapshot"
        }
    }
}

public struct BrowserInspectionToolOutput: Codable, Sendable, Hashable {
    public var url: String
    public var title: String
    public var status: String
    public var sourceLabel: String
    public var inspectionDepth: BrowserInspectionDepth
    public var summary: String
    public var details: [String]
    public var outline: [String]
    public var textSnippet: String?
    public var comments: [BrowserInspectionComment]

    private enum CodingKeys: String, CodingKey {
        case url
        case title
        case status
        case sourceLabel
        case inspectionDepth
        case summary
        case details
        case outline
        case textSnippet
        case comments
    }

    public init(
        url: String,
        title: String,
        status: String,
        sourceLabel: String,
        inspectionDepth: BrowserInspectionDepth = .metadataOnly,
        summary: String,
        details: [String],
        outline: [String] = [],
        textSnippet: String? = nil,
        comments: [BrowserInspectionComment] = []
    ) {
        self.url = url
        self.title = title
        self.status = status
        self.sourceLabel = sourceLabel
        self.inspectionDepth = inspectionDepth
        self.summary = summary
        self.details = details
        self.outline = outline
        self.textSnippet = textSnippet
        self.comments = comments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.title = try container.decode(String.self, forKey: .title)
        self.status = try container.decode(String.self, forKey: .status)
        self.sourceLabel = try container.decode(String.self, forKey: .sourceLabel)
        self.inspectionDepth = try container.decodeIfPresent(
            BrowserInspectionDepth.self,
            forKey: .inspectionDepth
        ) ?? .metadataOnly
        self.summary = try container.decode(String.self, forKey: .summary)
        self.details = try container.decode([String].self, forKey: .details)
        self.outline = try container.decodeIfPresent([String].self, forKey: .outline) ?? []
        self.textSnippet = try container.decodeIfPresent(String.self, forKey: .textSnippet)
        self.comments = try container.decodeIfPresent(
            [BrowserInspectionComment].self,
            forKey: .comments
        ) ?? []
    }
}

public struct MemoryRememberToolOutput: Codable, Sendable, Hashable {
    public var title: String
    public var relativePath: String
    public var content: String

    public init(title: String, relativePath: String, content: String) {
        self.title = title
        self.relativePath = relativePath
        self.content = content
    }
}

public extension ToolDefinition {
    static let planUpdate = ToolDefinition(
        name: "host.plan.update",
        description: "Update the visible task plan for the current thread. Use this before or during multi-step work so the Activity pane reflects the model-authored plan. Provide 1-12 concise steps and at most one in_progress item.",
        parametersJSON: #"{"type":"object","properties":{"explanation":{"type":"string"},"plan":{"type":"array","minItems":1,"maxItems":12,"items":{"type":"object","properties":{"step":{"type":"string"},"status":{"type":"string","enum":["pending","in_progress","completed"]},"detail":{"type":"string"}},"required":["step","status"]}}},"required":["plan"]}"#,
        host: .local,
        risk: .read
    )

    static let handoffUpdate = ToolDefinition(
        name: "host.handoff.update",
        description: "Update the Activity pane handoff summary for the current thread. Use this when a task reaches a handoff point or when the next agent/user needs a concise summary of current state, decisions, verification, and remaining steps.",
        parametersJSON: #"{"type":"object","properties":{"summary":{"type":"string","description":"Concise handoff summary for the current task state."},"nextSteps":{"type":"array","maxItems":8,"items":{"type":"string"},"description":"Optional ordered next steps for a future continuation."}},"required":["summary"]}"#,
        host: .local,
        risk: .read
    )

    static let browserInspect = ToolDefinition(
        name: "host.browser.inspect",
        description: "Inspect the current QuillCode browser preview page, including URL, title, inspection depth, summary, visible page outline, text snippet, and attached browser comments.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .browser,
        risk: .read
    )

    static let browserOpen = ToolDefinition(
        name: "host.browser.open",
        description: "Open an http, https, file, localhost, or project-relative page in the QuillCode browser preview, then return the browser snapshot that is available for agent review.",
        parametersJSON: #"{"type":"object","properties":{"url":{"type":"string","description":"The page to open. Accepts http, https, file, localhost, or project-relative paths."}},"required":["url"]}"#,
        host: .browser,
        risk: .read
    )

    static let memoryRemember = ToolDefinition(
        name: "host.memory.remember",
        description: "Save a durable user preference or stable project fact as explicit memory for future turns. Use only when the user asks QuillCode to remember something, or when the preference/fact is clearly stable and useful. Never save credentials, tokens, passwords, private keys, or other secrets.",
        parametersJSON: #"{"type":"object","properties":{"content":{"type":"string","description":"The durable preference or stable fact to remember. Do not include credentials, tokens, passwords, private keys, or other secrets."},"reason":{"type":"string","description":"Optional short rationale for why this should become durable memory."}},"required":["content"]}"#,
        host: .local,
        risk: .append
    )
}
