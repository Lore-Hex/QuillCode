import Foundation

/// A composer submission that was entered while a run was already active, parked as a
/// visible chip until the current turn finishes. The queue drains one item per turn
/// boundary (FIFO), so a walk-away prompt becomes a queued shift of work rather than a
/// rejected keystroke against a locked composer.
public struct FollowUpItem: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Pure, deterministic queue logic for the never-locking composer. The workspace model
/// owns the `[FollowUpItem]` (stored on the thread so it persists and survives reload);
/// this type computes the next queue on every mutation, keeping the ordering, dedup, and
/// drain semantics unit-testable in isolation with no actor or persistence dependencies.
///
/// Invariants the callers rely on:
/// - FIFO: `dequeue` always returns the oldest item; `enqueue` appends to the tail.
/// - Empty/whitespace text never enqueues (mirrors the composer's own submit guard).
/// - Every item id is unique within a queue; `delete` removes exactly the matching id.
/// - `dequeue` removes exactly one item and returns it, so an item drains exactly once.
public enum FollowUpQueue {
    /// The outcome of enqueuing: the updated queue and the item that was appended (nil when
    /// the text was empty/whitespace and nothing was enqueued). Callers persist `queue` and
    /// use `appended` to know whether a chip actually appeared.
    public struct Enqueue: Equatable {
        public var queue: [FollowUpItem]
        public var appended: FollowUpItem?

        public init(queue: [FollowUpItem], appended: FollowUpItem?) {
            self.queue = queue
            self.appended = appended
        }
    }

    /// The outcome of draining one item at a turn boundary: the item to send next (nil when
    /// the queue was empty) and the remaining queue after removing it.
    public struct Drain: Equatable {
        public var next: FollowUpItem?
        public var remaining: [FollowUpItem]

        public init(next: FollowUpItem?, remaining: [FollowUpItem]) {
            self.next = next
            self.remaining = remaining
        }
    }

    /// Appends a trimmed submission to the tail. Empty/whitespace text is rejected (no chip,
    /// queue unchanged) so an accidental Enter during a run never parks a blank turn. The
    /// stored text is the trimmed value — exactly what a direct submit would send.
    public static func enqueue(
        _ text: String,
        into queue: [FollowUpItem],
        id: UUID = UUID(),
        now: Date = Date()
    ) -> Enqueue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Enqueue(queue: queue, appended: nil)
        }
        let item = FollowUpItem(id: id, text: trimmed, createdAt: now)
        return Enqueue(queue: queue + [item], appended: item)
    }

    /// Removes and returns the head (oldest) item for the next turn, or reports an empty
    /// queue when there is nothing to drain. Removing exactly the head keeps drain
    /// exactly-once even if the same queue value is drained repeatedly.
    public static func dequeue(_ queue: [FollowUpItem]) -> Drain {
        guard let next = queue.first else {
            return Drain(next: nil, remaining: queue)
        }
        return Drain(next: next, remaining: Array(queue.dropFirst()))
    }

    /// Removes the item with `id` (a chip's delete affordance). Unknown ids are a no-op, so
    /// deleting an already-drained/already-removed chip never throws or drops another item.
    public static func delete(_ id: UUID, from queue: [FollowUpItem]) -> [FollowUpItem] {
        queue.filter { $0.id != id }
    }
}
