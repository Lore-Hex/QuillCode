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

/// A thread-safe hand-off from the retry decorator to the model. The decorator's `onRetry` fires deep
/// inside an async model call, off the main actor; it records the event here. The model drains the
/// channel on the main actor (each run-progress tick, and again when the run ends) and turns each event
/// into a "Self-healing" thread notice, so a run that quietly survived a blip says so.
///
/// One channel per runtime. v1 limitation: concurrent runs (e.g. subagents) share the one channel, so
/// their retry notices attribute to whichever thread drains first — acceptable for an informational row.
public final class RetryEventChannel: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [RetryEvent] = []

    public init() {}

    public func record(attempt: Int, kind: TransientFailureClass) {
        lock.lock()
        defer { lock.unlock() }
        pending.append(RetryEvent(attempt: attempt, kind: kind))
    }

    /// Returns the pending events and clears them.
    public func drain() -> [RetryEvent] {
        lock.lock()
        defer { lock.unlock() }
        let events = pending
        pending.removeAll()
        return events
    }
}
