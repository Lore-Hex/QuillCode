import CoreFoundation
import Foundation
import QuillCodeCore

public enum MCPClientToolEvent: Sendable, Hashable {
    case progress(ToolExecutionProgress)
    case result(MCPToolCallResult)
}

struct MCPProgressRequestContext: Sendable, Hashable {
    var token: MCPProgressToken
    var metadata: [String: MCPJSONValue]

    init(metadata value: MCPJSONValue?) throws {
        var metadata: [String: MCPJSONValue]
        switch value {
        case .none:
            metadata = [:]
        case .object(let object):
            metadata = object
        default:
            throw MCPProbeError.invalidMessage("MCP request metadata must be a JSON object.")
        }

        if let supplied = MCPProgressToken(metadata["progressToken"]) {
            token = supplied
        } else {
            token = .string("quillcode-\(UUID().uuidString.lowercased())")
            metadata["progressToken"] = token.jsonValue
        }
        self.metadata = metadata
    }
}

enum MCPProgressToken: Sendable, Hashable {
    case integer(Int64)
    case string(String)

    init?(_ value: Any?) {
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        switch value {
        case let value as String where !value.isEmpty:
            self = .string(value)
        case let value as Int:
            self = .integer(Int64(value))
        case let value as Int64:
            self = .integer(value)
        case let value as NSNumber:
            let double = value.doubleValue
            guard double.isFinite,
                  double.rounded(.towardZero) == double,
                  double >= Double(Int64.min),
                  double <= Double(Int64.max)
            else {
                return nil
            }
            self = .integer(Int64(double))
        default:
            return nil
        }
    }

    init?(_ value: MCPJSONValue?) {
        switch value {
        case .string(let value) where !value.isEmpty:
            self = .string(value)
        case .number(let value) where value.isFinite && value.rounded(.towardZero) == value
            && value >= Double(Int64.min) && value <= Double(Int64.max):
            self = .integer(Int64(value))
        default:
            return nil
        }
    }

    var jsonValue: MCPJSONValue {
        switch self {
        case .integer(let value): .number(Double(value))
        case .string(let value): .string(value)
        }
    }

    var foundationObject: Any {
        switch self {
        case .integer(let value): value
        case .string(let value): value
        }
    }
}

struct MCPProgressTracker {
    private(set) var lastCompleted: Double?
    private(set) var acceptedCount = 0
    let token: MCPProgressToken

    init(token: MCPProgressToken) {
        self.token = token
    }

    mutating func consume(_ object: [String: Any]) -> ToolExecutionProgress? {
        guard acceptedCount < Self.maximumUpdates,
              object["method"] as? String == "notifications/progress",
              let params = object["params"] as? [String: Any],
              MCPProgressToken(params["progressToken"]) == token,
              let completed = Self.finiteDouble(params["progress"]),
              completed >= 0,
              lastCompleted.map({ completed > $0 }) ?? true
        else {
            return nil
        }

        let total = Self.finiteDouble(params["total"]).flatMap { $0 > 0 ? $0 : nil }
        let message = Self.boundedMessage(params["message"] as? String)
        lastCompleted = completed
        acceptedCount += 1
        return ToolExecutionProgress(completed: completed, total: total, message: message)
    }

    private static func finiteDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        let number: Double?
        switch value {
        case let value as Double: number = value
        case let value as Int: number = Double(value)
        case let value as Int64: number = Double(value)
        case let value as NSNumber: number = value.doubleValue
        default: number = nil
        }
        guard let number, number.isFinite else { return nil }
        return number
    }

    private static func boundedMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
            .joined()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumMessageCharacters))
    }

    private static let maximumUpdates = 256
    private static let maximumMessageCharacters = 240
}

final class MCPProgressObserver: @unchecked Sendable {
    private var tracker: MCPProgressTracker
    private let lock = NSLock()
    private let onProgress: @Sendable (ToolExecutionProgress) -> Void

    init(
        token: MCPProgressToken,
        onProgress: @escaping @Sendable (ToolExecutionProgress) -> Void
    ) {
        self.tracker = MCPProgressTracker(token: token)
        self.onProgress = onProgress
    }

    func receive(_ object: [String: Any]) {
        lock.lock()
        let progress = tracker.consume(object)
        lock.unlock()
        if let progress { onProgress(progress) }
    }
}
