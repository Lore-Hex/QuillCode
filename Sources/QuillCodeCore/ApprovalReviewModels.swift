import Foundation

public enum ApprovalReviewOutcome: String, Codable, Sendable, Hashable {
    case approved
    case denied
    case clarificationRequired = "clarification_required"
    case timedOut = "timed_out"
    case aborted

    public init(verdict: ApprovalVerdict) {
        self = switch verdict {
        case .approve: .approved
        case .deny: .denied
        case .clarify: .clarificationRequired
        }
    }

    public var countsAsDenial: Bool { self == .denied }

    public var displayLabel: String {
        switch self {
        case .approved: "Approved"
        case .denied: "Denied"
        case .clarificationRequired: "Needs detail"
        case .timedOut: "Timed out"
        case .aborted: "Aborted"
        }
    }
}

public enum ApprovalRiskLevel: String, Codable, Sendable, Hashable, CaseIterable {
    case low
    case medium
    case high
    case critical
    case unknown
}

public enum ApprovalUserAuthorization: String, Codable, Sendable, Hashable, CaseIterable {
    case explicit
    case implicit
    case missing
    case mismatched
    case unknown
}

public enum ApprovalReviewAttemptKind: String, Codable, Sendable, Hashable {
    case initial
    case denialOverride = "denial_override"
}

public struct ApprovalReviewAttempt: Codable, Sendable, Hashable {
    public var kind: ApprovalReviewAttemptKind
    public var retryOfRequestID: String?

    public init(kind: ApprovalReviewAttemptKind, retryOfRequestID: String? = nil) {
        self.kind = kind
        self.retryOfRequestID = retryOfRequestID
    }

    public static let initial = ApprovalReviewAttempt(kind: .initial)

    public static func denialOverride(requestID: String) -> ApprovalReviewAttempt {
        ApprovalReviewAttempt(kind: .denialOverride, retryOfRequestID: requestID)
    }
}

/// Presentation-safe identity for one reviewed action. It deliberately stores the canonical
/// redacted arguments rather than a process-random hash, so equality is deterministic on macOS,
/// Linux, and after relaunch. Calls whose executable arguments required redaction are not replayable.
public struct ApprovalActionIdentity: Codable, Sendable, Hashable {
    public var toolName: String
    public var canonicalArgumentsJSON: String
    public var turnID: String
    public var workspacePath: String
    public var mode: AgentMode
    public var isReplayable: Bool

    public init(
        toolName: String,
        canonicalArgumentsJSON: String,
        turnID: String,
        workspacePath: String,
        mode: AgentMode,
        isReplayable: Bool
    ) {
        self.toolName = toolName
        self.canonicalArgumentsJSON = canonicalArgumentsJSON
        self.turnID = turnID
        self.workspacePath = workspacePath
        self.mode = mode
        self.isReplayable = isReplayable
    }

    public static func make(
        executableCall: ToolCall,
        presentedCall: ToolCall,
        thread: ChatThread,
        workspaceRoot: URL
    ) -> ApprovalActionIdentity {
        ApprovalActionIdentity(
            toolName: presentedCall.name,
            canonicalArgumentsJSON: canonicalJSON(presentedCall.argumentsJSON),
            turnID: currentTurnID(in: thread),
            workspacePath: workspaceRoot.standardizedFileURL.path,
            mode: thread.mode,
            isReplayable: executableCall == presentedCall
        )
    }

    public func matches(
        call: ToolCall,
        thread: ChatThread,
        workspaceRoot: URL
    ) -> Bool {
        isReplayable
            && toolName == call.name
            && canonicalArgumentsJSON == Self.canonicalJSON(call.argumentsJSON)
            && turnID == Self.currentTurnID(in: thread)
            && workspacePath == workspaceRoot.standardizedFileURL.path
            && mode == thread.mode
    }

    public static func currentTurnID(in thread: ChatThread) -> String {
        guard let message = thread.messages.last(where: { $0.role == .user }) else {
            return thread.id.uuidString.lowercased()
        }
        return message.turnID ?? message.id.uuidString.lowercased()
    }

    public static func canonicalJSON(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let canonical = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else {
            return trimmed
        }
        return String(decoding: canonical, as: UTF8.self)
    }
}

public enum AutoReviewDenialRetryState: String, Codable, Sendable, Hashable {
    case available
    case consumed
    case unavailable
    case contextChanged = "context_changed"
}

public struct AutoReviewDenialRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String { request.id }
    public var request: ApprovalRequest
    public var decision: ApprovalDecision
    public var createdAt: Date
    public var retryState: AutoReviewDenialRetryState
    public var retryRequestID: String?

    public init(
        request: ApprovalRequest,
        decision: ApprovalDecision,
        createdAt: Date,
        retryState: AutoReviewDenialRetryState,
        retryRequestID: String? = nil
    ) {
        self.request = request
        self.decision = decision
        self.createdAt = createdAt
        self.retryState = retryState
        self.retryRequestID = retryRequestID
    }
}

public enum AutoReviewDenialHistory {
    public static let maximumRecords = 10

    public static func records(
        in thread: ChatThread,
        workspaceRoot: URL? = nil
    ) -> [AutoReviewDenialRecord] {
        var requests: [String: (ApprovalRequest, Date)] = [:]
        var decisions: [String: ApprovalDecision] = [:]
        var retryRequests: [String: String] = [:]

        for event in thread.events {
            switch event.kind {
            case .approvalRequested:
                guard let request = decode(ApprovalRequest.self, event.payloadJSON) else { continue }
                requests[request.id] = (request, event.createdAt)
                if request.reviewAttempt.kind == .denialOverride,
                   let originalID = request.reviewAttempt.retryOfRequestID {
                    retryRequests[originalID] = request.id
                }
            case .approvalDecided:
                guard let decision = decode(ApprovalDecision.self, event.payloadJSON) else { continue }
                decisions[decision.requestID] = decision
            default:
                continue
            }
        }

        return requests.values.compactMap { request, createdAt in
            guard request.scope == .tool,
                  request.reviewAttempt.kind == .initial,
                  let decision = decisions[request.id],
                  decision.reviewOutcome == .denied
            else {
                return nil
            }
            let retryRequestID = retryRequests[request.id]
            let retryState: AutoReviewDenialRetryState
            if retryRequestID != nil {
                retryState = .consumed
            } else if request.actionIdentity?.isReplayable != true {
                retryState = .unavailable
            } else if let workspaceRoot,
                      request.actionIdentity?.matches(
                        call: request.toolCall,
                        thread: thread,
                        workspaceRoot: workspaceRoot
                      ) != true {
                retryState = .contextChanged
            } else {
                retryState = .available
            }
            return AutoReviewDenialRecord(
                request: request,
                decision: decision,
                createdAt: createdAt,
                retryState: retryState,
                retryRequestID: retryRequestID
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id > rhs.id
        }
        .prefix(maximumRecords)
        .map { $0 }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}
