import Foundation
import QuillCodeCore

struct AppServerThreadInjectItemsRequest {
    let rawThreadID: String
    let threadID: UUID
    let items: [CLIJSONValue]

    init(_ raw: CLIJSONValue) throws {
        guard let object = raw.objectValue else {
            throw AppServerRPCError.invalidRequest("Invalid request: expected an object")
        }
        guard let rawThreadID = object["threadId"]?.stringValue else {
            throw AppServerRPCError.invalidRequest("Invalid request: missing field `threadId`")
        }
        guard let threadID = UUID(uuidString: rawThreadID) else {
            throw AppServerRPCError.invalidRequest(Self.invalidThreadIDMessage(rawThreadID))
        }
        guard let rawItems = object["items"] else {
            throw AppServerRPCError.invalidRequest("Invalid request: missing field `items`")
        }
        guard let items = rawItems.arrayValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: \(AppServerResponseItemValidator.typeDescription(rawItems)), expected a sequence"
            )
        }
        guard !items.isEmpty else {
            throw AppServerRPCError.invalidRequest("items must not be empty")
        }

        self.rawThreadID = rawThreadID
        self.threadID = threadID
        self.items = items
    }

    private static func invalidThreadIDMessage(_ value: String) -> String {
        let simpleLength = value.filter { $0 != "-" }.count
        guard simpleLength == 32 else {
            return "invalid thread id: invalid length: expected length 32 for simple format, found \(simpleLength)"
        }
        return "invalid thread id: \(value)"
    }
}

extension CLIJSONValue {
    var quillJSONValue: QuillJSONValue {
        switch self {
        case .object(let value): return .object(value.mapValues(\.quillJSONValue))
        case .array(let value): return .array(value.map(\.quillJSONValue))
        case .string(let value): return .string(value)
        case .number(let value): return .number(value)
        case .bool(let value): return .bool(value)
        case .null: return .null
        }
    }
}
