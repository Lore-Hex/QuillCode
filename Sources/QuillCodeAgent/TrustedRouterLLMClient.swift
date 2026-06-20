import Foundation
import QuillCodeCore
import QuillCodeSafety
import TrustedRouter

public enum TrustedRouterAgentError: Error, CustomStringConvertible {
    case missingAPIKey
    case emptyResponse
    case invalidActionJSON(String)
    case emptyToolArguments(String)

    public var description: String {
        switch self {
        case .missingAPIKey:
            return "TrustedRouter API key is not configured. Sign in or enable the developer override."
        case .emptyResponse:
            return "TrustedRouter returned an empty response."
        case .invalidActionJSON(let text):
            return "Model did not return a valid QuillCode action JSON object: \(text)"
        case .emptyToolArguments(let toolName):
            return "Model returned an empty argument object for \(toolName)."
        }
    }
}

public struct TrustedRouterLLMClient: LLMClient {
    public var sessionStore: (any TrustedRouterSessionStore)?
    public var apiKeyOverride: String?
    public var model: String
    public var baseURL: String

    public init(
        sessionStore: (any TrustedRouterSessionStore)? = nil,
        apiKeyOverride: String? = nil,
        model: String = TrustedRouterDefaults.defaultModel,
        baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL
    ) {
        self.sessionStore = sessionStore
        self.apiKeyOverride = apiKeyOverride
        self.model = model
        self.baseURL = baseURL
    }

    public func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        let apiKey = try configuredAPIKey()
        let client = try TrustedRouter(options: .init(apiKey: apiKey, baseUrl: baseURL))
        let messages = Self.messages(thread: thread, userMessage: userMessage, tools: tools)
        let completion = try await client.chatCompletions(model: model, messages: messages)
        guard let text = completion.choices.first?.message.content?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
              !text.isEmpty
        else {
            throw TrustedRouterAgentError.emptyResponse
        }
        return try AgentActionJSONParser.parse(text)
    }

    public func configuredAPIKey() throws -> String {
        if let apiKeyOverride, !apiKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiKeyOverride
        }
        if let key = try sessionStore?.apiKey(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        throw TrustedRouterAgentError.missingAPIKey
    }

    public static func messages(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt(tools: tools)]
        ]
        if !thread.instructions.isEmpty {
            messages.append(["role": "system", "content": projectInstructionsPrompt(thread.instructions)])
        }
        for message in thread.messages.suffix(20) {
            switch message.role {
            case .system:
                messages.append(["role": "system", "content": message.content])
            case .user:
                messages.append(["role": "user", "content": message.content])
            case .assistant:
                messages.append(["role": "assistant", "content": message.content])
            case .tool:
                messages.append(["role": "assistant", "content": "Tool output: \(message.content)"])
            }
        }
        if thread.messages.last?.content != userMessage {
            messages.append(["role": "user", "content": userMessage])
        }
        return messages
    }

    public static func projectInstructionsPrompt(_ instructions: [ProjectInstruction]) -> String {
        let blocks = instructions.map { instruction in
            """
            # \(instruction.title) (\(instruction.path))
            \(instruction.content)
            """
        }.joined(separator: "\n\n")
        return """
        Follow these project instructions while working in this project. Higher-priority system and safety instructions still apply.

        \(blocks)
        """
    }

    public static func systemPrompt(tools: [ToolDefinition]) -> String {
        let toolList = tools.map { tool in
            "- \(tool.name): \(tool.description). Parameters JSON schema: \(tool.parametersJSON)"
        }.joined(separator: "\n")
        return """
        You are QuillCode, a native Swift coding agent.

        Return exactly one JSON object and no markdown.

        To answer without tools:
        {"type":"say","text":"..."}

        To run a tool:
        {"type":"tool","name":"host.shell.run","arguments":{"cmd":"whoami"}}

        Requirements:
        - If the user asks to run a command, create a host.shell.run action immediately.
        - host.shell.run MUST include a non-empty "cmd" string. Never emit {} for shell arguments.
        - If the user asks to create or write a file, use host.file.write with non-empty "path" and "content".
        - If the user asks to push or publish a git branch, use host.git.push instead of host.shell.run.
        - If the user asks to open or create a pull request/PR, use host.git.pr.create instead of host.shell.run.
        - host.git.pr.create should include a non-empty "title" unless you set "fill": true.
        - Do not say "I'll do it" unless you are returning the tool call that does it.
        - Keep commands bounded to the current project unless the user explicitly asks otherwise.

        Available tools:
        \(toolList)
        """
    }
}

public enum AgentActionJSONParser {
    public static func parse(_ text: String) throws -> AgentAction {
        let trimmed = stripFences(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let data = trimmed.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else {
            throw TrustedRouterAgentError.invalidActionJSON(text)
        }
        switch type {
        case "say":
            return .say((object["text"] as? String) ?? "")
        case "tool":
            guard let name = object["name"] as? String else {
                throw TrustedRouterAgentError.invalidActionJSON(text)
            }
            let arguments = object["arguments"] as? [String: Any] ?? [:]
            if arguments.isEmpty {
                throw TrustedRouterAgentError.emptyToolArguments(name)
            }
            if name == "host.shell.run" {
                let cmd = arguments["cmd"] as? String
                guard cmd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    throw TrustedRouterAgentError.emptyToolArguments(name)
                }
            }
            let argumentsData = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
            return .tool(.init(name: name, argumentsJSON: String(decoding: argumentsData, as: UTF8.self)))
        default:
            throw TrustedRouterAgentError.invalidActionJSON(text)
        }
    }

    private static func stripFences(_ text: String) -> String {
        var output = text
        if output.hasPrefix("```json") {
            output.removeFirst("```json".count)
        } else if output.hasPrefix("```") {
            output.removeFirst("```".count)
        }
        if output.hasSuffix("```") {
            output.removeLast("```".count)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TrustedRouterSafetyModelClient: SafetyModelClient {
    public var sessionStore: (any TrustedRouterSessionStore)?
    public var apiKeyOverride: String?
    public var baseURL: String

    public init(
        sessionStore: (any TrustedRouterSessionStore)? = nil,
        apiKeyOverride: String? = nil,
        baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL
    ) {
        self.sessionStore = sessionStore
        self.apiKeyOverride = apiKeyOverride
        self.baseURL = baseURL
    }

    public func review(prompt: String, model: String) async throws -> String {
        let apiKey = try configuredAPIKey()
        let client = try TrustedRouter(options: .init(apiKey: apiKey, baseUrl: baseURL))
        let completion = try await client.chatCompletions(
            model: model,
            messages: [
                ["role": "system", "content": "Return only the requested JSON object."],
                ["role": "user", "content": prompt]
            ]
        )
        guard let text = completion.choices.first?.message.content,
              !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        else {
            throw TrustedRouterAgentError.emptyResponse
        }
        return text
    }

    private func configuredAPIKey() throws -> String {
        if let apiKeyOverride, !apiKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiKeyOverride
        }
        if let key = try sessionStore?.apiKey(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        throw TrustedRouterAgentError.missingAPIKey
    }
}
