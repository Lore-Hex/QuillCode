import CoreFoundation
import Foundation

/// MCP client features QuillCode may advertise during `initialize`.
///
/// Standard form elicitation and OpenAI's richer form extension are separate capabilities. This
/// prevents a server from sending an extension request to a client surface that cannot render it.
public struct MCPClientCapabilities: Sendable, Hashable {
    public var supportsFormElicitation: Bool
    public var supportsOpenAIFormElicitation: Bool

    public init(
        supportsFormElicitation: Bool = false,
        supportsOpenAIFormElicitation: Bool = false
    ) {
        self.supportsFormElicitation = supportsFormElicitation
        self.supportsOpenAIFormElicitation = supportsOpenAIFormElicitation
    }

    public static let none = Self()

    var initializeObject: [String: Any] {
        var capabilities: [String: Any] = [:]
        if supportsFormElicitation {
            capabilities["elicitation"] = [String: Any]()
        }
        if supportsOpenAIFormElicitation {
            capabilities["extensions"] = ["openai/form": [String: Any]()]
        }
        return capabilities
    }

    func supports(_ request: MCPClientElicitationRequest) -> Bool {
        switch request {
        case .form, .url: supportsFormElicitation
        case .openAIForm: supportsOpenAIFormElicitation
        }
    }
}

/// A normalized MCP server-to-client elicitation request.
public enum MCPClientElicitationRequest: Sendable, Hashable {
    case form(message: String, requestedSchema: MCPJSONValue, metadata: MCPJSONValue?)
    case openAIForm(message: String, requestedSchema: MCPJSONValue, metadata: MCPJSONValue?)
    case url(message: String, url: String, elicitationID: String, metadata: MCPJSONValue?)

    public var message: String {
        switch self {
        case .form(let message, _, _),
             .openAIForm(let message, _, _),
             .url(let message, _, _, _):
            message
        }
    }

    public var metadata: MCPJSONValue? {
        switch self {
        case .form(_, _, let metadata),
             .openAIForm(_, _, let metadata),
             .url(_, _, _, let metadata):
            metadata
        }
    }
}

public enum MCPClientElicitationAction: String, Codable, Sendable, Hashable {
    case accept
    case decline
    case cancel
}

/// The client response returned to the requesting MCP server.
public struct MCPClientElicitationResponse: Sendable, Hashable {
    public var action: MCPClientElicitationAction
    public var content: MCPJSONValue?
    public var metadata: MCPJSONValue?

    public init(
        action: MCPClientElicitationAction,
        content: MCPJSONValue? = nil,
        metadata: MCPJSONValue? = nil
    ) {
        self.action = action
        self.content = action == .accept ? content : nil
        self.metadata = metadata
    }

    public static func accept(
        content: MCPJSONValue,
        metadata: MCPJSONValue? = nil
    ) -> Self {
        Self(action: .accept, content: content, metadata: metadata)
    }

    public static func decline(metadata: MCPJSONValue? = nil) -> Self {
        Self(action: .decline, metadata: metadata)
    }

    public static func cancel(metadata: MCPJSONValue? = nil) -> Self {
        Self(action: .cancel, metadata: metadata)
    }

    var foundationObject: [String: Any] {
        var object: [String: Any] = ["action": action.rawValue]
        if let content { object["content"] = content.foundationObject }
        if let metadata { object["_meta"] = metadata.foundationObject }
        return object
    }
}

public typealias MCPClientElicitationHandler = @Sendable (
    MCPClientElicitationRequest
) async -> MCPClientElicitationResponse

enum MCPJSONRPCRequestID: Sendable, Hashable {
    case integer(Int64)
    case string(String)

    init?(_ value: Any?) {
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        switch value {
        case let value as String where !value.isEmpty && value.count <= 512:
            self = .string(value)
        case let value as Int:
            self = .integer(Int64(value))
        case let value as Int64:
            self = .integer(value)
        case let value as NSNumber:
            let number = value.doubleValue
            guard number.isFinite,
                  number.rounded(.towardZero) == number,
                  number >= Double(Int64.min),
                  number <= Double(Int64.max)
            else {
                return nil
            }
            self = .integer(Int64(number))
        default:
            return nil
        }
    }

    var foundationObject: Any {
        switch self {
        case .integer(let value): value
        case .string(let value): value
        }
    }
}

struct MCPServerElicitationEnvelope: Sendable, Hashable {
    let id: MCPJSONRPCRequestID
    let request: MCPClientElicitationRequest

    static func requestIDIfRecognized(in object: [String: Any]) -> MCPJSONRPCRequestID? {
        guard let method = object["method"] as? String,
              method == "elicitation/create" || method == "openai/form"
        else {
            return nil
        }
        return MCPJSONRPCRequestID(object["id"])
    }

    static func decode(from object: [String: Any]) throws -> Self {
        guard let id = requestIDIfRecognized(in: object),
              let method = object["method"] as? String,
              let params = object["params"] as? [String: Any]
        else {
            throw MCPProbeError.invalidMessage("MCP elicitation request was malformed.")
        }

        let message = try boundedString(
            params["message"],
            name: "message",
            maximumCharacters: 16_384,
            permitsEmpty: true
        )
        let metadata = try sanitizedMetadata(params["_meta"])
        let mode = method == "openai/form"
            ? "openai/form"
            : (params["mode"] as? String ?? "form")

        let request: MCPClientElicitationRequest
        switch mode {
        case "form":
            let schema = try requestedSchema(params["requestedSchema"], typed: true)
            request = .form(message: message, requestedSchema: schema, metadata: metadata)
        case "openai/form":
            let schema = try requestedSchema(params["requestedSchema"], typed: false)
            request = .openAIForm(message: message, requestedSchema: schema, metadata: metadata)
        case "url":
            let url = try boundedString(
                params["url"],
                name: "url",
                maximumCharacters: 8_192,
                permitsEmpty: false
            )
            let elicitationID = try boundedString(
                params["elicitationId"],
                name: "elicitationId",
                maximumCharacters: 512,
                permitsEmpty: false
            )
            request = .url(
                message: message,
                url: url,
                elicitationID: elicitationID,
                metadata: metadata
            )
        default:
            throw MCPProbeError.invalidMessage("MCP elicitation mode '\(mode)' is unsupported.")
        }
        return Self(id: id, request: request)
    }

    private static func requestedSchema(_ value: Any?, typed: Bool) throws -> MCPJSONValue {
        guard let value else {
            throw MCPProbeError.invalidMessage("MCP elicitation requestedSchema is required.")
        }
        let schema = try MCPJSONValue(jsonObject: value)
        guard schema.objectValue != nil else {
            throw MCPProbeError.invalidMessage("MCP elicitation requestedSchema must be an object.")
        }
        if typed { try MCPFormElicitationSchemaValidator.validate(schema) }
        return schema
    }

    private static func sanitizedMetadata(_ value: Any?) throws -> MCPJSONValue? {
        guard let value else { return nil }
        let metadata = try MCPJSONValue(jsonObject: value)
        guard case .object(var object) = metadata else {
            throw MCPProbeError.invalidMessage("MCP elicitation metadata must be an object.")
        }
        // Request progress belongs to the enclosing tool call and must not leak into the form.
        object.removeValue(forKey: "progressToken")
        return object.isEmpty ? nil : .object(object)
    }

    private static func boundedString(
        _ value: Any?,
        name: String,
        maximumCharacters: Int,
        permitsEmpty: Bool
    ) throws -> String {
        guard let value = value as? String,
              (permitsEmpty || !value.isEmpty),
              value.count <= maximumCharacters
        else {
            throw MCPProbeError.invalidMessage("MCP elicitation \(name) was invalid.")
        }
        return value
    }
}

/// Waits for an async app client while a synchronous MCP transport owns its read loop.
///
/// The transport itself always runs off-actor. The condition only blocks that worker, while the
/// handler remains free to suspend on app-server I/O. Cancellation and the tool deadline are
/// checked frequently so a disconnected client cannot strand the transport indefinitely.
enum MCPAsyncElicitationBridge {
    static func resolve(
        _ request: MCPClientElicitationRequest,
        using handler: MCPClientElicitationHandler?,
        deadline: Date
    ) throws -> MCPClientElicitationResponse {
        guard let handler else { return .cancel() }

        let state = State()
        let task = Task.detached {
            let response = await handler(request)
            state.complete(response)
        }
        defer { task.cancel() }
        return try state.wait(until: deadline)
    }

    private final class State: @unchecked Sendable {
        private let condition = NSCondition()
        private var response: MCPClientElicitationResponse?

        func complete(_ response: MCPClientElicitationResponse) {
            condition.lock()
            guard self.response == nil else {
                condition.unlock()
                return
            }
            self.response = response
            condition.broadcast()
            condition.unlock()
        }

        func wait(until deadline: Date) throws -> MCPClientElicitationResponse {
            condition.lock()
            defer { condition.unlock() }
            while response == nil {
                if Task.isCancelled { throw CancellationError() }
                guard Date() < deadline else { return .cancel() }
                _ = condition.wait(until: min(deadline, Date().addingTimeInterval(0.05)))
            }
            return response ?? .cancel()
        }
    }
}
