import Foundation

/// Session-only ownership for agent work that can continue independently in multiple chats.
///
/// Conversation state remains in `ChatThread`; this registry only answers which threads currently
/// own a live task and which status should be projected when one of those threads is selected.
public struct WorkspaceAgentRunRegistry: Sendable, Hashable {
    private struct Entry: Sendable, Hashable {
        var runID: UUID
        var status: String
    }

    private var entriesByThreadID: [UUID: Entry]

    public init(statusesByThreadID: [UUID: String] = [:]) {
        self.entriesByThreadID = statusesByThreadID.mapValues {
            Entry(runID: UUID(), status: $0)
        }
    }

    public var activeThreadIDs: Set<UUID> {
        Set(entriesByThreadID.keys)
    }

    public var activeCount: Int {
        entriesByThreadID.count
    }

    public func isRunning(_ threadID: UUID?) -> Bool {
        threadID.map { entriesByThreadID[$0] != nil } ?? false
    }

    public func isRunning(_ threadID: UUID?, runID: UUID) -> Bool {
        threadID.flatMap { entriesByThreadID[$0]?.runID } == runID
    }

    public func status(for threadID: UUID?) -> String? {
        threadID.flatMap { entriesByThreadID[$0]?.status }
    }

    public func runID(for threadID: UUID?) -> UUID? {
        threadID.flatMap { entriesByThreadID[$0]?.runID }
    }

    @discardableResult
    public mutating func begin(threadID: UUID, status: String) -> Bool {
        begin(threadID: threadID, runID: UUID(), status: status)
    }

    @discardableResult
    public mutating func begin(threadID: UUID, runID: UUID, status: String) -> Bool {
        let inserted = entriesByThreadID[threadID] == nil
        entriesByThreadID[threadID] = Entry(runID: runID, status: status)
        return inserted
    }

    public mutating func update(threadID: UUID, runID: UUID? = nil, status: String) {
        guard var entry = entriesByThreadID[threadID],
              runID == nil || entry.runID == runID
        else {
            return
        }
        entry.status = status
        entriesByThreadID[threadID] = entry
    }

    @discardableResult
    public mutating func finish(threadID: UUID) -> String? {
        entriesByThreadID.removeValue(forKey: threadID)?.status
    }

    @discardableResult
    public mutating func finish(threadID: UUID, runID: UUID) -> String? {
        guard entriesByThreadID[threadID]?.runID == runID else { return nil }
        return entriesByThreadID.removeValue(forKey: threadID)?.status
    }

    @discardableResult
    public mutating func finishAll() -> Bool {
        guard !entriesByThreadID.isEmpty else { return false }
        entriesByThreadID.removeAll(keepingCapacity: true)
        return true
    }
}
