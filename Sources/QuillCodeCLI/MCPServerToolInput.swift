import Foundation

enum MCPServerApprovalPolicy: String, CaseIterable, Sendable {
    case untrusted
    case onFailure = "on-failure"
    case onRequest = "on-request"
    case never
}

enum MCPServerToolInvocation: Sendable {
    case start(threadID: UUID, input: MCPServerRunInput)
    case reply(threadID: UUID, prompt: String)

    var threadID: UUID {
        switch self {
        case .start(let threadID, _), .reply(let threadID, _): threadID
        }
    }

    init(params: CLIJSONValue) throws {
        guard let params = params.objectValue,
              let name = params["name"]?.stringValue else {
            throw MCPServerToolInputError.invalid("tools/call requires a string name")
        }
        let arguments = params["arguments"] ?? .object([:])
        guard let object = arguments.objectValue else {
            throw MCPServerToolInputError.invalid("tool arguments must be a JSON object")
        }
        switch name {
        case MCPServerToolCatalog.runToolName:
            self = .start(threadID: UUID(), input: try MCPServerRunInput(arguments: object))
        case MCPServerToolCatalog.replyToolName:
            let supported = Set(["prompt", "threadId", "conversationId"])
            let unknown = Set(object.keys).subtracting(supported)
            guard unknown.isEmpty else {
                throw MCPServerToolInputError.invalid(
                    "unsupported codex-reply arguments: \(unknown.sorted().joined(separator: ", "))"
                )
            }
            let prompt = try MCPServerToolArguments.requiredString("prompt", in: object)
            let rawID = object["threadId"]?.stringValue ?? object["conversationId"]?.stringValue
            guard let rawID, let threadID = UUID(uuidString: rawID) else {
                throw MCPServerToolInputError.invalid(
                    "codex-reply requires a valid threadId (or deprecated conversationId)"
                )
            }
            self = .reply(threadID: threadID, prompt: prompt)
        default:
            throw MCPServerToolInputError.invalid("Unknown tool '\(name)'")
        }
    }
}

struct MCPServerRunInput: Sendable {
    var prompt: String
    var approvalPolicy: MCPServerApprovalPolicy?
    var baseInstructions: String?
    var compactPrompt: String?
    var config: [String: CLIJSONValue]
    var cwd: String?
    var developerInstructions: String?
    var model: String?
    var sandbox: CLISandboxMode?

    init(arguments: [String: CLIJSONValue]) throws {
        let supported = Set([
            "prompt", "approval-policy", "base-instructions", "compact-prompt", "config",
            "cwd", "developer-instructions", "model", "sandbox"
        ])
        let unknown = Set(arguments.keys).subtracting(supported)
        guard unknown.isEmpty else {
            throw MCPServerToolInputError.invalid(
                "unsupported codex arguments: \(unknown.sorted().joined(separator: ", "))"
            )
        }
        self.prompt = try MCPServerToolArguments.requiredString("prompt", in: arguments)
        if let rawPolicy = try MCPServerToolArguments.optionalString(
            "approval-policy",
            in: arguments
        ) {
            guard let policy = MCPServerApprovalPolicy(rawValue: rawPolicy) else {
                throw MCPServerToolInputError.invalid("approval-policy is not supported")
            }
            self.approvalPolicy = policy
        } else {
            self.approvalPolicy = nil
        }
        self.baseInstructions = try MCPServerToolArguments.optionalString(
            "base-instructions",
            in: arguments
        )
        self.compactPrompt = try MCPServerToolArguments.optionalString(
            "compact-prompt",
            in: arguments
        )
        if let value = arguments["config"], value != .null {
            guard let config = value.objectValue else {
                throw MCPServerToolInputError.invalid("config must be an object")
            }
            self.config = config
        } else {
            self.config = [:]
        }
        self.cwd = try MCPServerToolArguments.optionalString("cwd", in: arguments)
        self.developerInstructions = try MCPServerToolArguments.optionalString(
            "developer-instructions",
            in: arguments
        )
        self.model = try MCPServerToolArguments.optionalString("model", in: arguments)
        if let rawSandbox = try MCPServerToolArguments.optionalString("sandbox", in: arguments) {
            guard let sandbox = CLISandboxMode(rawValue: rawSandbox) else {
                throw MCPServerToolInputError.invalid("sandbox is not supported")
            }
            self.sandbox = sandbox
        } else {
            self.sandbox = nil
        }
    }
}

private enum MCPServerToolArguments {
    static func optionalString(
        _ key: String,
        in object: [String: CLIJSONValue]
    ) throws -> String? {
        guard let value = object[key], value != .null else { return nil }
        guard let string = value.stringValue else {
            throw MCPServerToolInputError.invalid("\(key) must be a string or null")
        }
        return string
    }

    static func requiredString(
        _ key: String,
        in object: [String: CLIJSONValue]
    ) throws -> String {
        guard let value = object[key]?.stringValue else {
            throw MCPServerToolInputError.invalid("\(key) must be a string")
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPServerToolInputError.invalid("\(key) must not be empty")
        }
        return value
    }
}

struct MCPServerToolInputError: LocalizedError, Sendable {
    var reason: String

    static func invalid(_ reason: String) -> MCPServerToolInputError {
        MCPServerToolInputError(reason: reason)
    }

    var errorDescription: String? { reason }
}
