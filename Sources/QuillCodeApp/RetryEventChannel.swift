import Foundation
import QuillCodeAgent

/// A retry the model client performed: which attempt (1-based) and why.
public struct RetryEvent: Sendable, Hashable {
    public var attempt: Int
    public var kind: TransientFailureClass

    public init(attempt: Int, kind: TransientFailureClass) {
        self.attempt = attempt
        self.kind = kind
    }
}

/// Associates retry callbacks with the chat run that triggered the model call. Task-local scope
/// propagates through the retry client's async work without adding thread identifiers to the LLM API.
public enum AgentRunRetryScope {
    @TaskLocal public static var threadID: UUID?
}

/// A thread-safe hand-off from the retry decorator to the model. The decorator's `onRetry` fires deep
/// inside an async model call, off the main actor; it records the event here. The model drains the
/// channel on the main actor when the run ends and turns each event into a "Self-healing" thread
/// notice, so a run that quietly survived a blip says so.
///
public final class RetryEventChannel: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingByThreadID: [UUID: [RetryEvent]] = [:]
    private var unscopedPending: [RetryEvent] = []

    public init() {}

    public func record(attempt: Int, kind: TransientFailureClass) {
        lock.lock()
        defer { lock.unlock() }
        let event = RetryEvent(attempt: attempt, kind: kind)
        if let threadID = AgentRunRetryScope.threadID {
            pendingByThreadID[threadID, default: []].append(event)
        } else {
            unscopedPending.append(event)
        }
    }

    /// Returns retry events for exactly one chat run and clears only that run's bucket.
    public func drain(threadID: UUID) -> [RetryEvent] {
        lock.lock()
        defer { lock.unlock() }
        return pendingByThreadID.removeValue(forKey: threadID) ?? []
    }

    /// Compatibility/testing drain for callers that do not establish a run scope. It also clears
    /// every scoped bucket so runtime replacement cannot leak old notices into a later session.
    public func drain() -> [RetryEvent] {
        lock.lock()
        defer { lock.unlock() }
        let events = unscopedPending + pendingByThreadID
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .flatMap(\.value)
        unscopedPending.removeAll(keepingCapacity: true)
        pendingByThreadID.removeAll(keepingCapacity: true)
        return events
    }
}
