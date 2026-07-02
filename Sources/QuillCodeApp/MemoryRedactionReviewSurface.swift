import Foundation
import QuillCodeCore

struct MemoryRedactionReviewPayload: Codable, Sendable, Hashable {
    static let eventSummary = "Memory redaction blocked"

    var action: String
    var redactedInput: String
    var reason: String
    var guidance: String

    static func payload(action: WorkspaceMemoryFailureKind, userText: String) -> Self? {
        guard let actionLabel = action.redactionActionLabel else { return nil }
        return Self(
            action: actionLabel,
            redactedInput: redactedUserText(action: action, userText: userText),
            reason: "The attempted memory looked like a credential, token, password, or private key.",
            guidance: "Store secrets in a password manager or secret store. Save only durable preferences or facts."
        )
    }

    static func redactedUserText(action: WorkspaceMemoryFailureKind, userText: String) -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .save:
            return trimmed.hasPrefix("/")
                ? "/remember \(ToolCall.redactedMemoryContentValue)"
                : "Memory request \(ToolCall.redactedMemoryContentValue)"
        case .update:
            let firstLine = trimmed
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? "/remember-edit"
            return "\(firstLine)\n\(ToolCall.redactedMemoryContentValue)"
        case .delete:
            return "Forget memory"
        }
    }
}

public struct MemoryRedactionReviewSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var redactedInput: String
    public var guidance: String
    public var addCommandID: String

    init(event: ThreadEvent, payload: MemoryRedactionReviewPayload) {
        self.id = event.id.uuidString
        self.title = MemoryRedactionReviewPayload.eventSummary
        self.summary = payload.reason
        self.redactedInput = payload.redactedInput
        self.guidance = payload.guidance
        self.addCommandID = "memory-add"
    }

    static func reviews(events: [ThreadEvent], limit: Int = 4) -> [Self] {
        events.reversed().compactMap(review(from:)).prefix(limit).map { $0 }
    }

    static func event(action: WorkspaceMemoryFailureKind, userText: String) -> ThreadEvent? {
        guard let payload = MemoryRedactionReviewPayload.payload(action: action, userText: userText),
              let payloadJSON = try? JSONHelpers.encodePretty(payload)
        else {
            return nil
        }
        return ThreadEvent(
            kind: .notice,
            summary: MemoryRedactionReviewPayload.eventSummary,
            payloadJSON: payloadJSON
        )
    }

    private static func review(from event: ThreadEvent) -> Self? {
        if let payload = explicitPayload(from: event) {
            return Self(event: event, payload: payload)
        }
        if let payload = failedToolPayload(from: event) {
            return Self(event: event, payload: payload)
        }
        return nil
    }

    private static func explicitPayload(from event: ThreadEvent) -> MemoryRedactionReviewPayload? {
        guard event.kind == .notice,
              event.summary == MemoryRedactionReviewPayload.eventSummary,
              let payloadJSON = event.payloadJSON
        else {
            return nil
        }
        return try? JSONHelpers.decode(MemoryRedactionReviewPayload.self, from: payloadJSON)
    }

    private static func failedToolPayload(from event: ThreadEvent) -> MemoryRedactionReviewPayload? {
        guard event.kind == .toolFailed,
              event.summary == "\(ToolDefinition.memoryRemember.name) failed",
              let payloadJSON = event.payloadJSON,
              let result = try? JSONHelpers.decode(ToolResult.self, from: payloadJSON),
              memoryErrorLooksSensitive(result.error)
        else {
            return nil
        }
        return MemoryRedactionReviewPayload(
            action: "save",
            redactedInput: "\(ToolDefinition.memoryRemember.name) \(ToolCall.redactedMemoryContentValue)",
            reason: "The attempted memory looked like a credential, token, password, or private key.",
            guidance: "Store secrets in a password manager or secret store. Save only durable preferences or facts."
        )
    }

    private static func memoryErrorLooksSensitive(_ error: String?) -> Bool {
        let value = (error ?? "").lowercased()
        return ["credential", "token", "password", "private key"].contains { value.contains($0) }
    }
}
